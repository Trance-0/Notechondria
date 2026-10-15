"""Course-repo adapter.

Maps an existing documentation repository (VitePress / Nextra / Docusaurus
/ GitBook / plain markdown) onto a Notechondria course **without moving or
renaming any files**. A small config file at the repo root —
``notechondria.course.yaml`` (our own schema, with per-framework presets)
— declares where the markdown lives and how to group/title it; everything
else in the repo (build config, framework code, CI, non-markdown assets)
is ignored on read and never touched on write.

This module is intentionally free of Django imports so it can be unit
tested on plain dicts and reused by the import endpoint, the lazy-sync
engine, and the Veronica-7 migration script.

v1 scope: **markdown only** (``.md``). MDX (``.mdx``) is deferred — such
files are skipped and reported in ``warnings`` (see docs/TODO.md).
"""

from __future__ import annotations

import posixpath
import re
from typing import Optional

import yaml

CONFIG_FILENAME = "notechondria.course.yaml"

# Per-framework defaults so a repo can opt in with a one-line
# ``preset: vitepress`` (or no config at all — see infer_preset). Each
# preset only needs to differ where the framework's conventions differ.
PRESETS: dict[str, dict] = {
    "vitepress": {
        "content": {"root": "docs", "exclude": [".vitepress/**", "public/**"]},
    },
    "nextra": {
        "content": {"root": "pages", "exclude": []},
    },
    "docusaurus": {
        "content": {"root": "docs", "exclude": []},
    },
    "gitbook": {
        "content": {"root": ".", "exclude": ["node_modules/**", ".gitbook/**"]},
    },
    "custom": {
        "content": {"root": ".", "exclude": []},
    },
}

# Merged under every preset. Globs are relative to ``content.root``.
_BASE_CONFIG: dict = {
    "version": 1,
    "preset": "custom",
    "course": {"title": "", "slug": "", "description": ""},
    "content": {
        "root": ".",
        "include": ["**/*.md"],
        "exclude": ["**/node_modules/**", ".git/**"],
        "module_depth": 1,
        "index_names": ["index.md", "README.md"],
        "title_from": ["frontmatter", "h1", "filename"],
        "order_keys": ["sidebar_position", "order", "nav_order"],
    },
    "sync": {
        # Which files the lazy-sync may overwrite. Markdown only for now;
        # anything not matched here is never written.
        "write": ["**/*.md"],
    },
}

_H1_RE = re.compile(r"^\s{0,3}#\s+(.+?)\s*#*\s*$", re.MULTILINE)
_FRONTMATTER_RE = re.compile(r"^﻿?---\r?\n(.*?)\r?\n---\r?\n?", re.DOTALL)


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

def _deep_merge(base: dict, over: dict) -> dict:
    out = dict(base)
    for key, value in (over or {}).items():
        if isinstance(value, dict) and isinstance(out.get(key), dict):
            out[key] = _deep_merge(out[key], value)
        else:
            out[key] = value
    return out


def infer_preset(paths: list[str]) -> str:
    """Best-effort framework detection from a repo's file list, so a repo
    with no config still binds sensibly."""
    joined = "\n".join(paths)
    if "docs/.vitepress/" in joined or ".vitepress/config" in joined:
        return "vitepress"
    if "docusaurus.config" in joined:
        return "docusaurus"
    if any(p == "theme.config.tsx" or p.endswith("/theme.config.tsx") for p in paths) or "pages/_meta." in joined:
        return "nextra"
    if any(p == "SUMMARY.md" or p.endswith("/SUMMARY.md") for p in paths) or ".gitbook.yaml" in joined:
        return "gitbook"
    return "custom"


def load_course_config(
    config_text: Optional[str],
    *,
    repo_name: str = "",
    paths: Optional[list[str]] = None,
) -> dict:
    """Parse the repo's ``notechondria.course.yaml`` (YAML or JSON — YAML is
    a superset) and merge it over the base + preset defaults. Missing config
    is fine: the preset is inferred from ``paths`` and defaults fill in.
    ``repo_name`` seeds the course title/slug when the config omits them."""
    user: dict = {}
    if config_text and config_text.strip():
        loaded = yaml.safe_load(config_text)
        if isinstance(loaded, dict):
            user = loaded
    preset = user.get("preset") or infer_preset(paths or [])
    if preset not in PRESETS:
        preset = "custom"
    config = _deep_merge(_BASE_CONFIG, PRESETS[preset])
    config["preset"] = preset
    config = _deep_merge(config, user)
    # Course identity fallbacks.
    course = config["course"]
    if not course.get("title"):
        course["title"] = _humanize(repo_name.split("/")[-1]) if repo_name else "Course"
    if not course.get("slug"):
        course["slug"] = _slugify(course["title"])
    return config


# ---------------------------------------------------------------------------
# Glob matching (supports ``**`` across directories)
# ---------------------------------------------------------------------------

def _compile_glob(pattern: str) -> re.Pattern:
    pattern = pattern.strip()
    i, n = 0, len(pattern)
    out = ["^"]
    while i < n:
        c = pattern[i]
        if pattern[i : i + 3] == "**/":
            out.append("(?:.*/)?")
            i += 3
        elif pattern[i : i + 2] == "**":
            out.append(".*")
            i += 2
        elif c == "*":
            out.append("[^/]*")
            i += 1
        elif c == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(c))
            i += 1
    out.append("$")
    return re.compile("".join(out))


def _match_any(path: str, patterns: list[str]) -> bool:
    return any(_compile_glob(p).match(path) for p in patterns)


# ---------------------------------------------------------------------------
# Markdown helpers
# ---------------------------------------------------------------------------

def parse_frontmatter(text: str) -> tuple[dict, str]:
    """Split a leading YAML frontmatter block from the markdown body."""
    match = _FRONTMATTER_RE.match(text or "")
    if not match:
        return {}, text or ""
    try:
        meta = yaml.safe_load(match.group(1)) or {}
    except yaml.YAMLError:
        meta = {}
    if not isinstance(meta, dict):
        meta = {}
    return meta, text[match.end():]


def _humanize(name: str) -> str:
    name = re.sub(r"\.[A-Za-z0-9]+$", "", name or "")
    name = name.replace("-", " ").replace("_", " ").strip()
    if not name:
        return ""
    return " ".join(word[:1].upper() + word[1:] for word in name.split())


def _slugify(text: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", (text or "").lower()).strip("-")
    return slug or "course"


def extract_title(path: str, meta: dict, body: str, title_from: list[str], index_names: list[str]) -> str:
    for source in title_from:
        if source == "frontmatter":
            title = meta.get("title")
            if isinstance(title, str) and title.strip():
                return title.strip()
        elif source == "h1":
            m = _H1_RE.search(body or "")
            if m:
                return m.group(1).strip()
        elif source == "filename":
            base = posixpath.basename(path)
            if base in index_names or base.lower() in {n.lower() for n in index_names}:
                parent = posixpath.basename(posixpath.dirname(path))
                return _humanize(parent) or "Overview"
            return _humanize(base) or base
    return _humanize(posixpath.basename(path)) or path


def compose_markdown(frontmatter: dict, body: str) -> str:
    """Re-emit a markdown file from a (framework) frontmatter dict + body.
    Used on sync write-back so the repo file keeps the frontmatter that
    drives its site rendering (sidebar_position, title, …); only the body
    is the edited content. Empty/absent frontmatter yields a bare body."""
    body = (body or "").lstrip("\n")
    if not frontmatter:
        return body if not body or body.endswith("\n") else body + "\n"
    dumped = yaml.safe_dump(
        frontmatter, sort_keys=False, allow_unicode=True, default_flow_style=False
    ).strip("\n")
    return f"---\n{dumped}\n---\n\n{body}".rstrip("\n") + "\n"


def load_frontmatter_dict(raw_json: str) -> dict:
    """Best-effort decode a note's stored ``custom_meta`` JSON back into a
    frontmatter dict (empty on anything unexpected)."""
    if not raw_json:
        return {}
    try:
        import json as _json

        decoded = _json.loads(raw_json)
        return decoded if isinstance(decoded, dict) else {}
    except (ValueError, TypeError):
        return {}


def _order_value(meta: dict, order_keys: list[str]):
    for key in order_keys:
        if key in meta:
            try:
                return float(meta[key])
            except (TypeError, ValueError):
                continue
    return None


# ---------------------------------------------------------------------------
# Repo -> course structure
# ---------------------------------------------------------------------------

def _rel_under_root(path: str, root: str) -> Optional[str]:
    root = (root or ".").strip("/")
    if root in ("", "."):
        return path
    prefix = root + "/"
    if path == root or path.startswith(prefix):
        return path[len(prefix):] if path.startswith(prefix) else ""
    return None


def parse_course_repo(files: dict[str, str], config: dict) -> dict:
    """Turn a ``{repo_path: text}`` map + a resolved config into a course
    structure: modules (grouped by the ``module_depth``-th path segment
    under the content root), each with ordered notes. Non-markdown and
    excluded files are ignored; ``.mdx`` is skipped and reported."""
    content = config["content"]
    root = content.get("root", ".")
    include = content.get("include", ["**/*.md"])
    exclude = content.get("exclude", [])
    module_depth = int(content.get("module_depth", 1) or 1)
    index_names = content.get("index_names", ["index.md", "README.md"])
    title_from = content.get("title_from", ["frontmatter", "h1", "filename"])
    order_keys = content.get("order_keys", ["sidebar_position", "order", "nav_order"])

    warnings: list[str] = []
    # module key -> {"title", "notes": [...], "_order": min order seen}
    modules: dict[str, dict] = {}

    for path in sorted(files):
        if path.endswith(".mdx"):
            warnings.append(f"skipped MDX (unsupported in v1): {path}")
            continue
        if not path.endswith(".md"):
            continue
        rel = _rel_under_root(path, root)
        if rel is None or rel == "":
            continue
        if not _match_any(rel, include):
            continue
        if exclude and _match_any(rel, exclude):
            continue
        text = files[path]
        meta, body = parse_frontmatter(text)
        if meta.get("notechondria_ignore") is True or meta.get("draft") is True:
            continue
        title = extract_title(path, meta, body, title_from, index_names)
        order = _order_value(meta, order_keys)
        segments = rel.split("/")
        if len(segments) > module_depth:
            module_key = "/".join(segments[:module_depth])
        else:
            module_key = ""  # a top-level file -> default module
        bucket = modules.setdefault(
            module_key, {"key": module_key, "title": "", "notes": [], "_order": None}
        )
        bucket["notes"].append({
            "path": path,
            "rel_path": rel,
            "title": title,
            "order": order,
            "markdown": body,
            "frontmatter": meta,
            "is_index": posixpath.basename(path) in index_names,
        })
        if order is not None and (bucket["_order"] is None or order < bucket["_order"]):
            bucket["_order"] = order

    # Module titles: from an index note's title, else humanized key.
    for key, bucket in modules.items():
        index_note = next((n for n in bucket["notes"] if n["is_index"]), None)
        if key == "":
            bucket["title"] = config["course"]["title"]
        elif index_note is not None:
            bucket["title"] = index_note["title"]
        else:
            bucket["title"] = _humanize(key.split("/")[-1]) or key

    # Order notes within a module, and modules among themselves.
    for bucket in modules.values():
        bucket["notes"].sort(key=lambda n: (
            n["order"] if n["order"] is not None else float("inf"),
            0 if n["is_index"] else 1,
            n["rel_path"].lower(),
        ))
    ordered_modules = sorted(
        modules.values(),
        key=lambda b: (
            b["_order"] if b["_order"] is not None else float("inf"),
            "" if b["key"] == "" else b["key"].lower(),
        ),
    )
    for bucket in ordered_modules:
        bucket.pop("_order", None)

    note_count = sum(len(b["notes"]) for b in ordered_modules)
    return {
        "course": dict(config["course"], preset=config.get("preset", "custom")),
        "modules": ordered_modules,
        "note_count": note_count,
        "warnings": warnings,
    }
