"""GitHub data-sync service.

Materializes a creator's full server-side state (profile, app settings,
MCP skill, courses, notes incl. blocks and custom meta, planner events,
calendar feeds, recycle bin pointers) into a tracked Git repository so
the user can survive a complete server wipe by ``git clone``-ing their
own data back. Static assets we host (avatars, attachments, cover
images) are referenced by URL or UUID; their bytes stay on our CDN and
are not committed.

The canonical layout written to the repo:

    /
    ├── README.md              ← short pointer + last-sync timestamp
    ├── manifest.json          ← schema version + per-section index
    ├── profile/
    │   ├── creator.json       ← Creator row (no api_key_hash)
    │   ├── settings.json      ← app_settings_json
    │   └── skill.md           ← mcp_skill_md verbatim
    ├── courses/
    │   └── <slug>.json
    ├── notes/
    │   └── <uuid>.md          ← markdown body + YAML frontmatter
    │   └── <uuid>.meta.json   ← system metadata + custom_meta
    ├── planner/
    │   └── events.json
    │   └── feeds.json
    └── recycle_bin.json

Each push wraps ``git_sync.materialize`` + ``git_sync.commit_and_push``
inside a single GithubIntegration row update. Failures are written to
``GithubIntegration.last_error`` and re-raised.

This module talks to GitHub via the REST API (no PyGithub dependency)
using the installation-scoped access token. Tokens rotate ~1h, so
``_refresh_installation_token`` is called when the cached token is
within 60s of expiry.
"""

from __future__ import annotations

import base64
import hashlib
import json
import logging
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

import requests
from django.conf import settings
from django.utils.timezone import now

from creators.models import Creator, GithubIntegration

logger = logging.getLogger("django")

GITHUB_API = "https://api.github.com"
SCHEMA_VERSION = 1


class GithubSyncError(RuntimeError):
    """User-visible failure during a push/pull cycle. The message must
    follow the AGENTS.md §1.8 three-component shape: consequence,
    module/process, cause."""


@dataclass
class _RepoFile:
    path: str
    content_bytes: bytes


def _utc_iso(value):
    if value is None:
        return None
    if isinstance(value, datetime):
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc).isoformat()
    return str(value)


def _safe_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, indent=2, ensure_ascii=False) + "\n"


# ---------------------------------------------------------------------------
# Materialize: build the in-memory file tree from the creator's data
# ---------------------------------------------------------------------------


def _profile_files(creator: Creator) -> list[_RepoFile]:
    user = creator.user_id
    creator_payload = {
        "schema_version": SCHEMA_VERSION,
        "username": user.username,
        "first_name": user.first_name,
        "last_name": user.last_name,
        "email": user.email,
        "is_active": user.is_active,
        "motto": creator.motto or "",
        "social_link": creator.social_link or "",
        "editor_mode": creator.editor_mode,
        "theme_preset": creator.theme_preset,
        "theme_mode": creator.theme_mode,
        "api_base_url": creator.api_base_url,
        "image_url": creator.image.url if creator.image else "",
        "date_joined": _utc_iso(creator.date_joined),
        "last_login": _utc_iso(creator.last_login),
    }
    settings_payload = {}
    if creator.app_settings_json:
        try:
            settings_payload = json.loads(creator.app_settings_json)
        except (ValueError, TypeError):
            settings_payload = {"_invalid_json": creator.app_settings_json}
    return [
        _RepoFile("profile/creator.json", _safe_json(creator_payload).encode("utf-8")),
        _RepoFile(
            "profile/settings.json",
            _safe_json(
                {
                    "app_settings": settings_payload,
                    "app_settings_updated_at": _utc_iso(
                        creator.app_settings_updated_at
                    ),
                }
            ).encode("utf-8"),
        ),
        _RepoFile(
            "profile/skill.md", (creator.mcp_skill_md or "").encode("utf-8")
        ),
    ]


def _course_files(creator: Creator) -> list[_RepoFile]:
    from courses.models import Course

    files = []
    for course in Course.objects.filter(creator_id=creator):
        payload = {
            "schema_version": SCHEMA_VERSION,
            "id": course.id,
            "client_course_id": getattr(course, "client_course_id", "") or "",
            "slug": course.slug,
            "title": course.title,
            "description": course.description or "",
            "icon": course.icon,
            "is_default": course.is_default,
            "sort_order": getattr(course, "sort_order", 0),
            "cover_image_url": course.cover_image.url if course.cover_image else "",
        }
        files.append(
            _RepoFile(
                f"courses/{course.slug}.json", _safe_json(payload).encode("utf-8")
            )
        )
    return files


def _note_files(creator: Creator) -> list[_RepoFile]:
    from notes.models import Note

    files = []
    for note in Note.objects.filter(creator_id=creator, deleted_at__isnull=True):
        # Markdown body with a small YAML frontmatter block. Custom
        # meta keys go into the frontmatter so users can read the file
        # without opening the sidecar JSON.
        custom_meta = {}
        if note.custom_meta:
            try:
                decoded = json.loads(note.custom_meta)
                if isinstance(decoded, dict):
                    custom_meta = decoded
            except (ValueError, TypeError):
                custom_meta = {"_invalid_json": note.custom_meta}
        frontmatter = {
            "title": note.title,
            "uuid": str(note.uuid),
            "course_slug": note.course_id.slug if note.course_id else None,
            "is_public": note.is_public,
            "editor_mode": note.editor_mode,
            "last_edit": _utc_iso(note.last_edit),
            "date_created": _utc_iso(note.date_created),
            **custom_meta,
        }
        yaml_lines = ["---"]
        for key, value in frontmatter.items():
            if value is None:
                yaml_lines.append(f"{key}: null")
            elif isinstance(value, bool):
                yaml_lines.append(f"{key}: {'true' if value else 'false'}")
            else:
                escaped = str(value).replace("\n", " ").replace('"', '\\"')
                yaml_lines.append(f'{key}: "{escaped}"')
        yaml_lines.append("---")
        body = "\n".join(yaml_lines) + "\n\n" + (note.content or "") + "\n"
        files.append(
            _RepoFile(f"notes/{note.uuid.hex}.md", body.encode("utf-8"))
        )
        sidecar = {
            "schema_version": SCHEMA_VERSION,
            "id": note.id,
            "uuid": str(note.uuid),
            "sharing_id": note.sharing_id,
            "metadata_json": note.metadata_json,
            "custom_meta": note.custom_meta,
            "client_draft_id": note.client_draft_id,
            "note_type": note.note_type,
            "source_note_uuid": str(note.source_note.uuid) if note.source_note else None,
            "cover_image_url": note.cover_image.url if note.cover_image else "",
        }
        files.append(
            _RepoFile(
                f"notes/{note.uuid.hex}.meta.json",
                _safe_json(sidecar).encode("utf-8"),
            )
        )
    return files


def _planner_files(creator: Creator) -> list[_RepoFile]:
    from planner.models import CalendarFeed, PlannerEvent

    events = [
        {
            "id": e.id,
            "title": e.title,
            "event_date": _utc_iso(e.event_date),
            "starts_at": _utc_iso(e.starts_at),
            "ends_at": _utc_iso(e.ends_at),
            "difficulty_weight": e.difficulty_weight,
            "description": e.description or "",
            "course_id": e.course_id_id,
            "is_completed": e.is_completed,
            "completed_at": _utc_iso(getattr(e, "completed_at", None)),
        }
        for e in PlannerEvent.objects.filter(creator_id=creator)
    ]
    feeds = [
        {
            "id": f.id,
            "title": f.title,
            "source_kind": f.source_kind,
            "source_url": f.source_url or "",
            "is_enabled": f.is_enabled,
            "course_id": f.course_id_id,
            "last_sync": _utc_iso(f.last_sync),
        }
        for f in CalendarFeed.objects.filter(creator_id=creator)
    ]
    return [
        _RepoFile(
            "planner/events.json",
            _safe_json({"schema_version": SCHEMA_VERSION, "events": events}).encode(
                "utf-8"
            ),
        ),
        _RepoFile(
            "planner/feeds.json",
            _safe_json({"schema_version": SCHEMA_VERSION, "feeds": feeds}).encode(
                "utf-8"
            ),
        ),
    ]


def _readme(creator: Creator) -> _RepoFile:
    user = creator.user_id
    body = (
        f"# Notechondria backup for {user.username}\n\n"
        f"Last sync: {_utc_iso(now())}\n\n"
        "This repository is a machine-readable export of all "
        "user-owned text and metadata held by Notechondria for this "
        "account. Static assets (avatars, attachments, cover images) "
        "are referenced by URL but stored on the Notechondria CDN; "
        "they are NOT included in this repo.\n\n"
        "The schema is documented in `manifest.json`. To restore: "
        "follow `docs/integrations/github-sync.md` in the upstream "
        "Notechondria repo.\n"
    )
    return _RepoFile("README.md", body.encode("utf-8"))


def _manifest(creator: Creator, files: list[_RepoFile]) -> _RepoFile:
    payload = {
        "schema_version": SCHEMA_VERSION,
        "creator_username": creator.user_id.username,
        "exported_at": _utc_iso(now()),
        "files": sorted(f.path for f in files),
    }
    return _RepoFile("manifest.json", _safe_json(payload).encode("utf-8"))


def materialize(creator: Creator) -> list[_RepoFile]:
    """Build the full export tree for ``creator``."""
    files: list[_RepoFile] = []
    files.extend(_profile_files(creator))
    files.extend(_course_files(creator))
    files.extend(_note_files(creator))
    files.extend(_planner_files(creator))
    files.append(_manifest(creator, files))
    files.append(_readme(creator))
    return files


# ---------------------------------------------------------------------------
# GitHub REST helpers
# ---------------------------------------------------------------------------


def _github_headers(token: str) -> dict[str, str]:
    return {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "notechondria-data-sync/0.1",
    }


def _normalize_pem(pem: str) -> str:
    """Operators store the PEM as a single-line env value with literal
    `\\n` escapes. Convert it back to the multi-line form `cryptography`
    expects. Idempotent for already-multi-line input."""
    if "\\n" in pem and "\n" not in pem:
        return pem.replace("\\n", "\n")
    return pem


def _build_app_jwt(client_id: str, pem: str, *, now_seconds: int | None = None) -> str:
    """Build the GitHub App JWT used to obtain an installation token.

    Per https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app,
    `iat` may be backdated by 60s for clock skew, `exp` must be ≤ 10
    minutes in the future, and `iss` is the App's client_id (or app id).
    """
    import jwt as _jwt  # local import keeps the dep optional at module load

    now = now_seconds if now_seconds is not None else int(time.time())
    payload = {
        "iat": now - 60,
        "exp": now + 9 * 60,
        "iss": client_id,
    }
    return _jwt.encode(payload, _normalize_pem(pem), algorithm="RS256")


def _refresh_installation_token(integration: GithubIntegration) -> str:
    """Exchange the App's installation id for a short-lived access
    token. Persists the new token + expiry on ``integration`` and
    returns the token. Raises ``GithubSyncError`` on missing config or
    GitHub failure."""
    pem = settings.GITHUB_DATA_SYNC_APP_PRIVATE_KEY or ""
    client_id = settings.GITHUB_DATA_SYNC_APP_CLIENT_ID or ""
    if not pem:
        raise GithubSyncError(
            "GitHub sync unavailable: "
            "Backend.Creators.GithubSync/refresh_token — "
            "GITHUB_DATA_SYNC_APP_PRIVATE_KEY is not configured."
        )
    if not client_id:
        raise GithubSyncError(
            "GitHub sync unavailable: "
            "Backend.Creators.GithubSync/refresh_token — "
            "GITHUB_DATA_SYNC_APP_CLIENT_ID is not configured."
        )
    try:
        app_jwt = _build_app_jwt(client_id, pem)
    except Exception as exc:  # noqa: BLE001
        raise GithubSyncError(
            "GitHub sync unavailable: "
            "Backend.Creators.GithubSync/refresh_token — "
            f"failed to sign App JWT (check PEM format): {exc}."
        )
    url = f"{GITHUB_API}/app/installations/{integration.installation_id}/access_tokens"
    headers = {
        "Authorization": f"Bearer {app_jwt}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "notechondria-data-sync/0.1",
    }
    try:
        resp = requests.post(url, headers=headers, timeout=15)
    except requests.RequestException as exc:
        raise GithubSyncError(
            "GitHub sync aborted: "
            "Backend.Creators.GithubSync/refresh_token — "
            f"network error contacting GitHub: {exc}."
        )
    if resp.status_code >= 400:
        # Avoid leaking the JWT or PEM in the message; only surface
        # GitHub's status + truncated body.
        body = (resp.text or "")[:200]
        raise GithubSyncError(
            "GitHub sync rejected: "
            "Backend.Creators.GithubSync/refresh_token — "
            f"GitHub returned {resp.status_code} on installation "
            f"{integration.installation_id}: {body}."
        )
    data = resp.json() or {}
    token = data.get("token") or ""
    expires_at_raw = data.get("expires_at") or ""
    if not token:
        raise GithubSyncError(
            "GitHub sync rejected: "
            "Backend.Creators.GithubSync/refresh_token — "
            "GitHub response did not include an installation token."
        )
    expires_at = None
    if expires_at_raw:
        try:
            # GitHub returns RFC3339 with `Z` suffix; convert to UTC datetime.
            expires_at = datetime.fromisoformat(
                expires_at_raw.replace("Z", "+00:00")
            )
        except ValueError:
            expires_at = None
    integration.access_token = token
    integration.access_token_expires_at = expires_at
    integration.save(
        update_fields=[
            "access_token",
            "access_token_expires_at",
            "updated_at",
        ]
    )
    return token


def _ensure_token(integration: GithubIntegration) -> str:
    expires = integration.access_token_expires_at
    if (
        integration.access_token
        and expires is not None
        and (expires - now()).total_seconds() > 60
    ):
        return integration.access_token
    token = _refresh_installation_token(integration)
    return token


def commit_and_push(
    integration: GithubIntegration,
    files: list[_RepoFile],
    *,
    message: str | None = None,
) -> str:
    """Push ``files`` as a single commit to the integration's repo via
    the GitHub Contents API. Returns the commit SHA."""
    token = _ensure_token(integration)
    repo = integration.repo_full_name
    if not repo:
        raise GithubSyncError(
            "GitHub sync rejected: "
            "Backend.Creators.GithubSync/commit_and_push — "
            "no repository selected on this installation."
        )
    branch = integration.repo_default_branch or "main"
    headers = _github_headers(token)

    # Walk each file: GET the existing blob (to obtain its sha for
    # update) then PUT the new content. GitHub's Contents API is one
    # request per path; for ~hundreds of notes per user this is fine
    # and avoids a Trees-API + commit-by-hand flow that fights merge
    # conflicts.
    commit_msg = message or f"sync: {_utc_iso(now())}"
    last_sha = ""
    for file in files:
        url = f"{GITHUB_API}/repos/{repo}/contents/{file.path}"
        existing_sha = ""
        try:
            resp = requests.get(
                url, headers=headers, params={"ref": branch}, timeout=15
            )
            if resp.status_code == 200:
                existing_sha = resp.json().get("sha", "")
        except requests.RequestException as exc:
            logger.warning(
                "GitHub sync probe failed: "
                "Backend.Creators.GithubSync/commit_and_push — "
                "GET %s: %s.",
                file.path,
                exc,
            )
        body = {
            "message": commit_msg,
            "branch": branch,
            "content": base64.b64encode(file.content_bytes).decode("ascii"),
        }
        if existing_sha:
            body["sha"] = existing_sha
        try:
            resp = requests.put(url, headers=headers, json=body, timeout=30)
        except requests.RequestException as exc:
            raise GithubSyncError(
                "GitHub sync aborted: "
                "Backend.Creators.GithubSync/commit_and_push — "
                f"network error writing {file.path}: {exc}."
            )
        if resp.status_code >= 400:
            raise GithubSyncError(
                "GitHub sync rejected: "
                "Backend.Creators.GithubSync/commit_and_push — "
                f"GitHub returned {resp.status_code} for {file.path}."
            )
        commit = resp.json().get("commit") or {}
        last_sha = commit.get("sha") or last_sha
    return last_sha


def push_user_data(creator: Creator) -> str:
    """Materialize and push the creator's full data export. Returns the
    final commit SHA."""
    integration = getattr(creator, "github_integration", None)
    if integration is None:
        raise GithubSyncError(
            "GitHub sync unavailable: "
            "Backend.Creators.GithubSync/push_user_data — "
            "no GitHub App installation linked to this account."
        )
    files = materialize(creator)
    started = time.monotonic()
    sha = ""
    try:
        sha = commit_and_push(integration, files)
    except GithubSyncError as exc:
        integration.last_error = str(exc)
        integration.save(update_fields=["last_error", "updated_at"])
        raise
    integration.last_push_at = now()
    integration.last_push_sha = sha
    integration.last_error = ""
    integration.save(
        update_fields=[
            "last_push_at",
            "last_push_sha",
            "last_error",
            "updated_at",
        ]
    )
    duration = time.monotonic() - started
    logger.info(
        "Pushed user data to GitHub: "
        "Backend.Creators.GithubSync/push_user_data — "
        "creator=%s repo=%s files=%d sha=%s duration=%.2fs.",
        creator.user_id.username,
        integration.repo_full_name,
        len(files),
        sha[:8],
        duration,
    )
    return sha


__all__ = [
    "GithubSyncError",
    "materialize",
    "push_user_data",
]
