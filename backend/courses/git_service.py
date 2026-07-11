"""Course ↔ GitHub import/sync using the owner's GitHub App installation.

The App installation token (from ``creators.services.github_sync``) grants
access to every repo the App was installed on, so the same token that
backs profile-sync also reads/writes a course's own repo. This module is
the course-git counterpart of ``github_sync``:

- ``import_course_from_repo`` pulls the repo's markdown, parses it with
  the adapter (``courses.course_repo``), and creates/updates the course's
  notes (remembering each note's ``git_path`` for round-trip).
- The network fetch is isolated in ``fetch_course_repo`` so tests can
  mock it with a synthetic file tree.

Markdown only (v1); the adapter skips ``.mdx`` and reports it.
"""

from __future__ import annotations

import base64
import json
import logging

import requests

from courses.course_repo import CONFIG_FILENAME, load_course_config, parse_course_repo
from courses.models import CourseOperationLog, CourseOperationTypeChoices
from creators.models import GithubIntegration
from creators.services import github_sync
from notes.models import Note
from notechondria.utils import generate_unique_id

logger = logging.getLogger("notechondria.courses.git")

GITHUB_API = github_sync.GITHUB_API

# Safety caps so a pathological repo can't exhaust memory / rate limits.
MAX_MARKDOWN_FILES = 2000
MAX_FILE_BYTES = 512 * 1024


class CourseGitServiceError(RuntimeError):
    """Import/sync could not proceed (no App installation, repo not
    reachable, etc.). Callers map this to a 400 / tool error."""


def integration_for(creator) -> "GithubIntegration | None":
    return GithubIntegration.objects.filter(creator=creator).first()


def _get_file_text(repo: str, branch: str, path: str, headers: dict) -> "str | None":
    url = f"{GITHUB_API}/repos/{repo}/contents/{path}"
    try:
        resp = requests.get(url, headers=headers, params={"ref": branch}, timeout=15)
    except requests.RequestException:
        return None
    if resp.status_code != 200:
        return None
    payload = resp.json()
    if payload.get("encoding") == "base64" and payload.get("content"):
        return base64.b64decode(payload["content"]).decode("utf-8", "replace")
    return None


def fetch_course_repo(integration, repo: str, branch: str):
    """Return ``(config_text, files, all_paths)`` for a repo, where
    ``files`` maps repo-relative path -> text for **markdown files only**.
    Uses the App installation token. Isolated for mockability."""
    token = github_sync.installation_token(integration)
    headers = github_sync.github_request_headers(token)

    config_text = _get_file_text(repo, branch, CONFIG_FILENAME, headers)

    tree_url = f"{GITHUB_API}/repos/{repo}/git/trees/{branch}"
    try:
        resp = requests.get(
            tree_url, headers=headers, params={"recursive": "1"}, timeout=30
        )
    except requests.RequestException as exc:
        raise CourseGitServiceError(f"could not read repo tree: {exc}") from exc
    if resp.status_code >= 400:
        raise CourseGitServiceError(
            f"GitHub returned {resp.status_code} reading the repo tree for {repo}."
        )
    tree = resp.json().get("tree", [])
    all_paths = [e.get("path", "") for e in tree if e.get("type") == "blob"]

    files: dict[str, str] = {}
    fetched = 0
    for entry in tree:
        path = entry.get("path", "")
        if entry.get("type") != "blob" or not path.endswith(".md"):
            continue
        if (entry.get("size") or 0) > MAX_FILE_BYTES:
            continue
        if fetched >= MAX_MARKDOWN_FILES:
            break
        blob_url = f"{GITHUB_API}/repos/{repo}/git/blobs/{entry['sha']}"
        try:
            blob = requests.get(blob_url, headers=headers, timeout=20)
        except requests.RequestException:
            continue
        if blob.status_code != 200:
            continue
        data = blob.json()
        if data.get("encoding") == "base64" and data.get("content") is not None:
            files[path] = base64.b64decode(data["content"]).decode("utf-8", "replace")
            fetched += 1
    return config_text, files, all_paths


def import_course_from_repo(course) -> dict:
    """Pull the bound repo's markdown into the course's notes. Idempotent:
    notes are matched by ``git_path`` (created if new, updated if the
    title/content changed). Returns a summary and writes a GIT_IMPORT log."""
    creator = course.creator_id
    if not course.git_repo:
        raise CourseGitServiceError("This course is not bound to a repository.")
    integration = integration_for(creator)
    if integration is None:
        raise CourseGitServiceError(
            "Connect your GitHub account (install the app) before importing."
        )
    branch = course.git_branch or "main"
    config_text, files, all_paths = fetch_course_repo(integration, course.git_repo, branch)
    config = load_course_config(config_text, repo_name=course.git_repo, paths=all_paths)
    parsed = parse_course_repo(files, config)

    created = updated = 0
    for module in parsed["modules"]:
        for note_data in module["notes"]:
            git_path = note_data["path"]
            title = (note_data["title"] or "Untitled")[:100]
            markdown = note_data["markdown"]
            existing = Note.objects.filter(
                creator_id=creator,
                course_id=course,
                git_path=git_path,
                deleted_at__isnull=True,
            ).first()
            if existing is not None:
                if existing.content != markdown or existing.title != title:
                    existing.content = markdown
                    existing.title = title
                    existing.save()
                    updated += 1
            else:
                Note.objects.create(
                    creator_id=creator,
                    course_id=course,
                    sharing_id=generate_unique_id(Note, "sharing_id"),
                    title=title,
                    content=markdown,
                    git_path=git_path,
                    editor_mode="G",
                )
                created += 1

    summary = {
        "repo": course.git_repo,
        "branch": branch,
        "modules": len(parsed["modules"]),
        "note_count": parsed["note_count"],
        "created": created,
        "updated": updated,
        "warnings": parsed["warnings"],
    }
    CourseOperationLog.objects.create(
        creator_id=creator,
        course_id=course,
        operation_type=CourseOperationTypeChoices.GIT_IMPORT,
        metadata_json=json.dumps(
            {k: summary[k] for k in ("repo", "branch", "created", "updated", "note_count")},
            sort_keys=True,
        ),
    )
    logger.info(
        "Course git import: Backend.Courses.Git/import — course id=%s '%s' "
        "from %s@%s (created=%s updated=%s of %s).",
        course.id, course.title, course.git_repo, branch,
        created, updated, parsed["note_count"],
    )
    return summary
