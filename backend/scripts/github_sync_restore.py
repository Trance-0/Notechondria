#!/usr/bin/env python3
"""Restore a Notechondria account from a GitHub data-sync archive.

Walks the layout produced by `creators.services.github_sync.materialize`
(documented in `docs/integrations/github-sync.md`) and POSTs each piece
back into a Notechondria backend over the public REST API. The flow is
idempotent: notes round-trip via `client_draft_id`, courses match by
slug, planner events match by title+date when no explicit id is found.

Usage:

    python backend/scripts/github_sync_restore.py \\
        --repo-path /path/to/cloned-backup-repo \\
        --api-base https://notechondria.example/api/v1 \\
        --token ntc_<mcp-key>

Add `--dry-run` to print every request that would fire without
actually contacting the server. Add `--verbose` for per-section
counters.

Static assets (avatars, attachments, cover images) are referenced by
URL in the export and are not part of this restore. If the original
CDN host is gone, those URLs will 404 in the new account; that is the
known gap documented in github-sync.md.
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path
from typing import Any
from urllib import error, request


logger = logging.getLogger("github_sync_restore")


def _read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def _split_frontmatter(markdown: str) -> tuple[dict[str, str], str]:
    """Parse the YAML-frontmatter block written by `materialize`. The
    block is intentionally simple (one `key: "value"` per line); only
    the formats we emit are accepted, malformed blocks fall through."""
    lines = markdown.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}, markdown
    fm: dict[str, str] = {}
    end_idx = -1
    for idx, raw in enumerate(lines[1:], start=1):
        if raw.strip() == "---":
            end_idx = idx
            break
        if ":" not in raw:
            continue
        key, _sep, value = raw.partition(":")
        fm[key.strip()] = value.strip().strip('"')
    if end_idx == -1:
        return {}, markdown
    body = "\n".join(lines[end_idx + 1:])
    return fm, body.lstrip("\n")


class RestoreClient:
    """Tiny HTTP wrapper. Keeps the script dependency-free (stdlib
    only) so operators can run it in a recovery shell."""

    def __init__(self, api_base: str, token: str, *, dry_run: bool = False):
        self.api_base = api_base.rstrip("/")
        self.token = token
        self.dry_run = dry_run

    def _request(self, method: str, path: str, payload: dict | None = None) -> dict:
        url = f"{self.api_base}{path}"
        body = None
        headers = {
            "Accept": "application/json",
            "Authorization": f"Bearer {self.token}",
            "User-Agent": "github-sync-restore/0.1",
        }
        if payload is not None:
            body = json.dumps(payload).encode("utf-8")
            headers["Content-Type"] = "application/json"
        if self.dry_run:
            preview = ""
            if payload is not None:
                preview_body = json.dumps(payload, sort_keys=True)
                if len(preview_body) > 160:
                    preview_body = preview_body[:160] + "…"
                preview = f" body={preview_body}"
            print(f"[dry-run] {method} {url}{preview}")
            return {}
        req = request.Request(url, data=body, method=method, headers=headers)
        try:
            with request.urlopen(req, timeout=30) as resp:
                raw = resp.read()
        except error.HTTPError as exc:
            try:
                detail = exc.read().decode("utf-8", errors="replace")
            except Exception:
                detail = ""
            raise RuntimeError(
                "Restore aborted: "
                "Backend.Scripts.GithubSyncRestore/request — "
                f"{method} {url} returned {exc.code}: {detail[:200]}."
            ) from exc
        except error.URLError as exc:
            raise RuntimeError(
                "Restore aborted: "
                "Backend.Scripts.GithubSyncRestore/request — "
                f"{method} {url} network error: {exc.reason}."
            ) from exc
        if not raw:
            return {}
        try:
            return json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return {}

    def patch(self, path: str, payload: dict) -> dict:
        return self._request("PATCH", path, payload)

    def post(self, path: str, payload: dict) -> dict:
        return self._request("POST", path, payload)

    def get(self, path: str) -> dict:
        return self._request("GET", path)


def _restore_settings(client: RestoreClient, repo: Path, *, verbose: bool) -> None:
    creator_path = repo / "profile" / "creator.json"
    settings_path = repo / "profile" / "settings.json"
    skill_path = repo / "profile" / "skill.md"
    payload: dict[str, Any] = {}
    if creator_path.exists():
        creator = _read_json(creator_path)
        for key in ("motto", "social_link", "editor_mode",
                    "theme_preset", "theme_mode", "api_base_url"):
            if creator.get(key) not in (None, ""):
                payload[key] = creator[key]
    if settings_path.exists():
        settings = _read_json(settings_path)
        if settings.get("app_settings"):
            payload["app_settings"] = settings["app_settings"]
        if settings.get("app_settings_updated_at"):
            payload["app_settings_updated_at"] = settings["app_settings_updated_at"]
    if skill_path.exists():
        payload["mcp_skill_md"] = skill_path.read_text(encoding="utf-8")
    if not payload:
        if verbose:
            print("settings: nothing to restore (empty profile/)")
        return
    client.patch("/settings/", payload)
    if verbose:
        keys = ", ".join(sorted(payload.keys()))
        print(f"settings: PATCH /settings/ ({keys})")


def _restore_courses(client: RestoreClient, repo: Path, *, verbose: bool) -> dict[str, int]:
    """Idempotent course recreate: match by slug, fall back to
    POST /courses/ when the server doesn't already have it. Returns a
    `{slug: id}` map so notes can rebind by slug."""
    course_dir = repo / "courses"
    slug_to_id: dict[str, int] = {}
    if not course_dir.exists():
        return slug_to_id
    existing: dict[str, int] = {}
    if not client.dry_run:
        try:
            response = client.get("/courses/")
            for course in response.get("courses", []) if isinstance(response, dict) else []:
                slug = course.get("slug")
                if slug:
                    existing[slug] = int(course["id"])
        except RuntimeError as exc:
            logger.warning(
                "courses: skip pre-fetch (server returned an error: %s).",
                exc,
            )
    for json_path in sorted(course_dir.glob("*.json")):
        course = _read_json(json_path)
        slug = course.get("slug")
        if not slug:
            continue
        if slug in existing:
            slug_to_id[slug] = existing[slug]
            if verbose:
                print(f"courses: {slug} already on server → id={existing[slug]}")
            continue
        payload = {
            "slug": slug,
            "title": course.get("title") or slug,
            "description": course.get("description") or "",
            "icon": course.get("icon"),
            "client_course_id": course.get("client_course_id") or slug,
        }
        result = client.post("/courses/", payload)
        cid = result.get("id") if isinstance(result, dict) else None
        if cid:
            slug_to_id[slug] = int(cid)
        if verbose:
            print(f"courses: POST /courses/ {slug} → id={cid}")
    return slug_to_id


def _restore_notes(
    client: RestoreClient,
    repo: Path,
    slug_to_id: dict[str, int],
    *,
    verbose: bool,
) -> int:
    note_dir = repo / "notes"
    if not note_dir.exists():
        return 0
    count = 0
    for sidecar in sorted(note_dir.glob("*.meta.json")):
        meta = _read_json(sidecar)
        body_path = note_dir / sidecar.name.replace(".meta.json", ".md")
        markdown = body_path.read_text(encoding="utf-8") if body_path.exists() else ""
        frontmatter, body = _split_frontmatter(markdown)
        course_slug = frontmatter.get("course_slug") or ""
        course_id = slug_to_id.get(course_slug) if course_slug else None
        title = frontmatter.get("title") or meta.get("uuid") or sidecar.stem
        # client_draft_id keeps reruns idempotent: on repeat the backend
        # find-or-update path on /notes/ matches by `client_draft_id`
        # per the existing NoteListCreateApiView contract.
        client_draft_id = meta.get("client_draft_id") or f"restore:{meta.get('uuid','')}"
        payload = {
            "title": title,
            "description": "",  # leave the markdown body authoritative
            "content": body,
            "is_public": frontmatter.get("is_public") == "true",
            "editor_mode": frontmatter.get("editor_mode") or "P",
            "metadata_json": meta.get("metadata_json") or "",
            "custom_meta": meta.get("custom_meta") or "",
            "client_draft_id": client_draft_id,
            "note_type": meta.get("note_type") or "N",
        }
        if course_id is not None:
            payload["course_id"] = course_id
        client.post("/notes/", payload)
        count += 1
        if verbose:
            print(f"notes: POST /notes/ {title!r} (client_draft_id={client_draft_id})")
    return count


def _restore_planner(client: RestoreClient, repo: Path, *, verbose: bool) -> int:
    events_path = repo / "planner" / "events.json"
    if not events_path.exists():
        return 0
    payload_root = _read_json(events_path)
    events = payload_root.get("events") or []
    count = 0
    for event in events:
        payload = {
            "title": event.get("title") or "Untitled",
            "event_date": event.get("event_date"),
            "starts_at": event.get("starts_at"),
            "ends_at": event.get("ends_at"),
            "difficulty_weight": event.get("difficulty_weight") or 1,
            "description": event.get("description") or "",
            "is_completed": bool(event.get("is_completed")),
        }
        if event.get("course_id") is not None:
            payload["course_id"] = event["course_id"]
        client.post("/planner-events/", payload)
        count += 1
    if verbose:
        print(f"planner: POSTed {count} event(s) to /planner-events/")
    return count


def _restore_calendar_feeds(client: RestoreClient, repo: Path, *, verbose: bool) -> int:
    feeds_path = repo / "planner" / "feeds.json"
    if not feeds_path.exists():
        return 0
    payload_root = _read_json(feeds_path)
    feeds = payload_root.get("feeds") or []
    count = 0
    for feed in feeds:
        payload = {
            "title": feed.get("title") or "Untitled feed",
            "source_kind": feed.get("source_kind") or "S",
            "source_url": feed.get("source_url") or "",
            "is_enabled": bool(feed.get("is_enabled", True)),
        }
        if feed.get("course_id") is not None:
            payload["course_id"] = feed["course_id"]
        client.post("/calendar-feeds/", payload)
        count += 1
    if verbose:
        print(f"calendar-feeds: POSTed {count} feed(s) to /calendar-feeds/")
    return count


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="github_sync_restore",
        description=(
            "Restore a Notechondria account from a GitHub data-sync "
            "archive. See docs/integrations/github-sync.md for the "
            "expected repository layout."
        ),
    )
    parser.add_argument("--repo-path", required=True, type=Path,
                        help="Local path to a cloned data-sync repo.")
    parser.add_argument("--api-base", required=True,
                        help="Notechondria API base URL "
                             "(e.g. https://notechondria.example/api/v1).")
    parser.add_argument("--token", required=True,
                        help="MCP API key (ntc_…) for the destination account.")
    parser.add_argument("--dry-run", action="store_true",
                        help="Print requests instead of issuing them.")
    parser.add_argument("--verbose", action="store_true",
                        help="Print per-section counters.")
    args = parser.parse_args(argv)

    repo = args.repo_path.expanduser().resolve()
    if not repo.is_dir():
        print(f"error: --repo-path is not a directory: {repo}", file=sys.stderr)
        return 2
    manifest = repo / "manifest.json"
    if not manifest.exists():
        print(
            "warning: manifest.json missing — restore will continue "
            "but the layout may not match this script's expectations.",
            file=sys.stderr,
        )

    client = RestoreClient(args.api_base, args.token, dry_run=args.dry_run)
    if args.verbose:
        print(f"Restore source: {repo}")
        print(f"Restore target: {args.api_base}")

    _restore_settings(client, repo, verbose=args.verbose)
    slug_to_id = _restore_courses(client, repo, verbose=args.verbose)
    notes = _restore_notes(client, repo, slug_to_id, verbose=args.verbose)
    events = _restore_planner(client, repo, verbose=args.verbose)
    feeds = _restore_calendar_feeds(client, repo, verbose=args.verbose)

    summary = {
        "courses": len(slug_to_id),
        "notes": notes,
        "planner_events": events,
        "calendar_feeds": feeds,
    }
    print("Restore summary:", json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
