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

from django.db import transaction
from django.utils import timezone

from courses.course_repo import (
    CONFIG_FILENAME,
    compose_markdown,
    load_course_config,
    load_frontmatter_dict,
    parse_course_repo,
)
from courses.models import Course, CourseOperationLog, CourseOperationTypeChoices
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

    from notes.services import ensure_note_name

    created = updated = 0
    for module_index, module in enumerate(parsed["modules"]):
        module_title = (module.get("title") or "")[:160]
        for note_index, note_data in enumerate(module["notes"]):
            # Reading position: modules stay grouped and ordered, notes
            # keep the adapter's within-module order (frontmatter
            # `order`/`sidebar_position`, then path). 1-based so 0 keeps
            # meaning "unset" for natively-created notes.
            sort_order = (module_index + 1) * 1000 + note_index + 1
            git_path = note_data["path"]
            title = (note_data["title"] or "Untitled")[:100]
            markdown = note_data["markdown"]
            # Preserve the file's own frontmatter (sidebar_position, title,
            # …) so a later sync re-emits it and doesn't break the repo's
            # site rendering.
            frontmatter_json = json.dumps(note_data.get("frontmatter") or {}, default=str)
            existing = Note.objects.filter(
                creator_id=creator,
                course_id=course,
                git_path=git_path,
                deleted_at__isnull=True,
            ).first()
            if existing is not None:
                changed = (
                    existing.content != markdown
                    or existing.title != title
                    or existing.custom_meta != frontmatter_json
                    or existing.module != module_title
                    or existing.sort_order != sort_order
                )
                if not existing.name:
                    ensure_note_name(existing)
                    changed = True
                if changed:
                    existing.content = markdown
                    existing.title = title
                    existing.custom_meta = frontmatter_json
                    existing.module = module_title
                    existing.sort_order = sort_order
                    existing.save()
                    updated += 1
            else:
                note = Note.objects.create(
                    creator_id=creator,
                    course_id=course,
                    sharing_id=generate_unique_id(Note, "sharing_id"),
                    title=title,
                    content=markdown,
                    git_path=git_path,
                    custom_meta=frontmatter_json,
                    module=module_title,
                    sort_order=sort_order,
                    editor_mode="G",
                )
                ensure_note_name(note)
                if note.name:
                    note.save(update_fields=["name"])
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


# ---------------------------------------------------------------------------
# Sync (course notes -> repo markdown), lazy-on-request
# ---------------------------------------------------------------------------

def serialize_course_for_sync(course) -> dict[str, str]:
    """Map the course's git-backed notes to ``{repo_path: markdown}``. The
    file's original frontmatter (stored in ``custom_meta`` on import) is
    re-emitted so sync doesn't strip rendering metadata. Only notes with a
    ``.md`` ``git_path`` are written — nothing else in the repo is touched."""
    files: dict[str, str] = {}
    notes = Note.objects.filter(
        course_id=course, deleted_at__isnull=True, git_path__isnull=False
    ).exclude(git_path="")
    for note in notes:
        if not note.git_path.endswith(".md"):
            continue
        frontmatter = load_frontmatter_dict(note.custom_meta)
        files[note.git_path] = compose_markdown(frontmatter, note.content or "")
    return files


def _commit_files(integration, repo: str, branch: str, files: dict[str, str], message: str) -> str:
    """Write every mapped markdown file as ONE atomic commit via the Git
    Data API: build a tree on top of the branch's current tree (so files we
    don't manage are untouched), create a single commit, and fast-forward
    the ref. Returns the new commit sha, or ``""`` when nothing changed.

    This replaces the 0.1.174 per-file Contents API loop, which made one
    commit *per file* — for a large course (e.g. 193 notes) that was 193
    sequential round-trips: it blew past the request/gateway timeout,
    could be killed mid-run (partial, non-atomic push), and flooded the
    repo history. The Git Data API needs a fixed handful of calls
    regardless of file count."""
    import requests as _requests

    token = github_sync.installation_token(integration)
    headers = github_sync.github_request_headers(token)
    git_base = f"{GITHUB_API}/repos/{repo}/git"

    def _get(url: str):
        try:
            resp = _requests.get(url, headers=headers, timeout=30)
        except _requests.RequestException as exc:
            raise CourseGitServiceError(f"network error contacting GitHub: {exc}") from exc
        if resp.status_code >= 400:
            raise CourseGitServiceError(
                f"GitHub returned {resp.status_code} reading {url.rsplit('/git/', 1)[-1]}."
            )
        return resp.json()

    def _post(url: str, body: dict):
        try:
            resp = _requests.post(url, headers=headers, json=body, timeout=60)
        except _requests.RequestException as exc:
            raise CourseGitServiceError(f"network error contacting GitHub: {exc}") from exc
        if resp.status_code >= 400:
            raise CourseGitServiceError(
                f"GitHub returned {resp.status_code} on {url.rsplit('/git/', 1)[-1]}: "
                f"{resp.text[:200]}"
            )
        return resp.json()

    ref = _get(f"{git_base}/ref/heads/{branch}")
    base_commit_sha = (ref.get("object") or {}).get("sha")
    if not base_commit_sha:
        raise CourseGitServiceError(f"branch '{branch}' has no commit to build on.")
    base_tree_sha = ((_get(f"{git_base}/commits/{base_commit_sha}") or {}).get("tree") or {}).get("sha")
    if not base_tree_sha:
        raise CourseGitServiceError("could not resolve the branch's base tree.")

    tree_entries = [
        {"path": path, "mode": "100644", "type": "blob", "content": text}
        for path, text in files.items()
    ]
    new_tree = _post(f"{git_base}/trees", {"base_tree": base_tree_sha, "tree": tree_entries})
    if new_tree.get("sha") == base_tree_sha:
        # Recomposed markdown is byte-identical to the repo — don't create
        # an empty commit.
        return ""

    commit = _post(f"{git_base}/commits", {
        "message": message,
        "tree": new_tree["sha"],
        "parents": [base_commit_sha],
    })
    new_commit_sha = commit.get("sha")
    if not new_commit_sha:
        raise CourseGitServiceError("GitHub did not return a commit sha.")
    try:
        upd = _requests.patch(
            f"{git_base}/refs/heads/{branch}", headers=headers,
            json={"sha": new_commit_sha}, timeout=30,
        )
    except _requests.RequestException as exc:
        raise CourseGitServiceError(f"network error updating ref: {exc}") from exc
    if upd.status_code >= 400:
        raise CourseGitServiceError(
            f"GitHub returned {upd.status_code} updating branch '{branch}': {upd.text[:200]}"
        )
    return new_commit_sha


def sync_course_to_repo(course) -> dict:
    """Push the course's notes back to its bound repo (markdown only) and
    update the sync bookkeeping. Clears ``git_pending_since`` on success;
    records ``git_last_sync_error`` and re-raises on failure."""
    creator = course.creator_id
    if not course.git_repo:
        raise CourseGitServiceError("This course is not bound to a repository.")
    integration = integration_for(creator)
    if integration is None:
        raise CourseGitServiceError(
            "Connect your GitHub account (install the app) before syncing."
        )
    branch = course.git_branch or "main"
    files = serialize_course_for_sync(course)
    if not files:
        # Nothing to write; just clear the pending flag.
        course.git_pending_since = None
        course.git_last_synced_at = timezone.now()
        course.git_last_sync_error = None
        course.save(update_fields=["git_pending_since", "git_last_synced_at", "git_last_sync_error"])
        return {"repo": course.git_repo, "branch": branch, "files": 0, "commit_sha": ""}
    message = f"notechondria: sync course '{course.title}'"
    try:
        sha = _commit_files(integration, course.git_repo, branch, files, message)
    except CourseGitServiceError as exc:
        course.git_last_sync_error = str(exc)[:512]
        course.save(update_fields=["git_last_sync_error"])
        raise
    course.git_pending_since = None
    course.git_last_synced_at = timezone.now()
    course.git_last_sync_error = None
    course.save(update_fields=["git_pending_since", "git_last_synced_at", "git_last_sync_error"])
    CourseOperationLog.objects.create(
        creator_id=creator,
        course_id=course,
        operation_type=CourseOperationTypeChoices.GIT_SYNC,
        metadata_json=json.dumps({"repo": course.git_repo, "branch": branch, "files": len(files)}, sort_keys=True),
    )
    logger.info(
        "Course git sync: Backend.Courses.Git/sync — course id=%s '%s' -> "
        "%s@%s (%s files, sha=%s).",
        course.id, course.title, course.git_repo, branch, len(files), sha,
    )
    return {"repo": course.git_repo, "branch": branch, "files": len(files), "commit_sha": sha}


def mark_course_pending(course) -> None:
    """Arm the lazy-sync debounce: called when a bound, sync-enabled
    course's content changes. Sets ``git_pending_since`` if not already
    armed (so the timer measures 'time since the FIRST unsynced edit'…
    actually since the latest arm — re-armed only when clear)."""
    if not (course.git_sync_enabled and course.git_repo):
        return
    if course.git_pending_since is None:
        course.git_pending_since = timezone.now()
        course.save(update_fields=["git_pending_since"])


def flush_due_course_syncs(creator, *, limit: int = 3) -> int:
    """Lazy-on-request hook: push any of this creator's bound courses whose
    debounce has elapsed. Row-locked so concurrent requests can't double
    push; best-effort (a failing course records its error and is skipped,
    never breaking the caller). Returns the number synced."""
    from datetime import timedelta

    now = timezone.now()
    candidates = list(
        Course.objects.filter(
            creator_id=creator,
            git_sync_enabled=True,
            git_pending_since__isnull=False,
        ).exclude(git_repo__isnull=True).exclude(git_repo="")[: max(1, limit) * 4]
    )
    synced = 0
    for course in candidates:
        if synced >= limit:
            break
        due_at = course.git_pending_since + timedelta(minutes=course.git_sync_timeout_minutes or 5)
        if due_at > now:
            continue
        try:
            with transaction.atomic():
                locked = (
                    Course.objects.select_for_update()
                    .filter(pk=course.pk, git_pending_since__isnull=False)
                    .first()
                )
                if locked is None:
                    continue  # another request already flushed it
                sync_course_to_repo(locked)
                synced += 1
        except CourseGitServiceError as exc:
            logger.warning(
                "Course git sync skipped: Backend.Courses.Git/flush — course "
                "id=%s: %s", course.pk, exc,
            )
        except Exception as exc:  # noqa: BLE001 - never break the request
            logger.exception(
                "Course git sync error: Backend.Courses.Git/flush — course "
                "id=%s: %s", course.pk, exc,
            )
    return synced
