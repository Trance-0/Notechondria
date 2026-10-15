#!/usr/bin/env python3
"""Migrate open `- [ ]` items from docs/TODO.md into GitHub Issues.

Each open checkbox becomes one issue:
  * title  — the item's bolded lead (or first clause), section-prefixed
  * body   — the full item text, its TODO section, and provenance
  * labels — derived from the section heading (area/*) plus `todo-import`

Idempotent: existing open issues with the same title are skipped, so the
script can be re-run after adding new TODO items.

Usage:
    GITHUB_TOKEN=<pat> python3 scripts/todo_to_issues.py --dry-run
    GITHUB_TOKEN=<pat> python3 scripts/todo_to_issues.py --create
The token needs `issues: write` on the repo (classic: `repo`).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request

REPO = os.environ.get("TODO_ISSUES_REPO", "Trance-0/Notechondria")
TODO_PATH = os.path.join(os.path.dirname(__file__), "..", "docs", "TODO.md")
API = "https://api.github.com"

# Section heading (lowercased, matched by substring) -> label.
LABEL_RULES = [
    ("activity", "area:activity"),
    ("github course binding", "area:course-git"),
    ("github sync", "area:github-sync"),
    ("calendar / course", "area:calendar"),
    ("cross-app", "area:cross-app"),
    ("i18n", "area:i18n"),
    ("internationalization", "area:i18n"),
    ("planner", "area:planner"),
    ("editor", "area:editor"),
    ("portal", "area:portal"),
    ("backend", "area:backend"),
    ("auth", "area:auth"),
    ("mcp", "area:mcp"),
    ("release", "area:release-ci"),
    ("documentation", "area:docs"),
    ("tutorials", "area:onboarding"),
    ("global reusable components", "area:shared-ui"),
    ("storage", "area:storage"),
    ("dev plan", "area:roadmap"),
]


def parse_open_items(markdown: str):
    """Yield (section, heading_trail, raw_item_text) for each `- [ ]`."""
    lines = markdown.splitlines()
    h2 = h3 = ""
    items = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("## "):
            h2, h3 = line[3:].strip(), ""
        elif line.startswith("### "):
            h3 = line[4:].strip()
        elif line.startswith("- [ ]"):
            block = [line[5:].strip()]
            i += 1
            # Continuation lines are indented and not a new list item.
            while i < len(lines):
                nxt = lines[i]
                if nxt.startswith("  ") and not nxt.lstrip().startswith("- ["):
                    block.append(nxt.strip())
                    i += 1
                else:
                    break
            items.append((h2, h3, " ".join(block).strip()))
            continue
        i += 1
    return items


def clean_md(text: str) -> str:
    """Strip markdown emphasis for the title line."""
    text = re.sub(r"\*\*(.+?)\*\*", r"\1", text)
    text = re.sub(r"`(.+?)`", r"\1", text)
    return text.strip()


def make_title(item: str) -> str:
    """Prefer the leading **bold** phrase; else the first sentence.

    A leading ``#5`` style index is stripped — GitHub would render it as
    a cross-reference to an unrelated issue.
    """
    item = re.sub(r"^\s*\*\*#\d+\s+", "**", item)
    bold = re.match(r"\s*\*\*(.+?)\*\*", item)
    if bold:
        title = clean_md(bold.group(1)).rstrip(":. ")
    else:
        title = clean_md(re.split(r"(?<=[.!?])\s", item)[0])
    title = re.sub(r"\s+", " ", title).strip(" —-:.")
    return (title[:110].rstrip() + "…") if len(title) > 110 else title


def make_labels(h2: str, h3: str) -> list[str]:
    """Area label from the MOST SPECIFIC heading that matches.

    Matching on `h2 + h3` stacked 4-5 areas onto every item (the h2
    "GitHub course binding & activity UX" alone hits three rules), which
    makes the labels useless for filtering. The subsection wins; the
    parent is only consulted when the subsection matches nothing.
    Likewise `priority:urgent` comes from the item's own heading, so
    explicitly-deferred subsections don't inherit urgency.
    """
    labels = {"todo-import"}
    for heading in (h3, h2):
        if not heading:
            continue
        hay = heading.lower()
        matched = {label for needle, label in LABEL_RULES if needle in hay}
        if matched:
            labels |= matched
            break
    own_heading = (h3 or h2).lower()
    if "urgent" in own_heading:
        labels.add("priority:urgent")
    return sorted(labels)


def make_body(h2: str, h3: str, item: str) -> str:
    section = " › ".join(x for x in (h2, h3) if x)
    section = clean_md(section) if section else "(top level)"
    return (
        f"{item}\n\n"
        "---\n"
        f"**TODO section:** {section}\n\n"
        "_Migrated automatically from `docs/TODO.md` by "
        "`scripts/todo_to_issues.py`. Closing this issue is the source of "
        "truth; the TODO file is no longer the tracker for this item._"
    )


def api(path: str, token: str, method: str = "GET", payload=None):
    req = urllib.request.Request(
        f"{API}{path}",
        method=method,
        data=json.dumps(payload).encode() if payload is not None else None,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "User-Agent": "notechondria-todo-migrator",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)


def existing_titles(token: str) -> set[str]:
    titles, page = set(), 1
    while True:
        rows = api(
            f"/repos/{REPO}/issues?state=all&per_page=100&page={page}", token
        )
        if not rows:
            break
        titles.update(r["title"] for r in rows if "pull_request" not in r)
        if len(rows) < 100:
            break
        page += 1
    return titles


def ensure_labels(token: str, labels: set[str]) -> None:
    have = {l["name"] for l in api(f"/repos/{REPO}/labels?per_page=100", token)}
    palette = {
        "todo-import": "ededed",
        "priority:urgent": "b60205",
    }
    for name in sorted(labels - have):
        try:
            api(
                f"/repos/{REPO}/labels",
                token,
                "POST",
                {"name": name, "color": palette.get(name, "1d76db")},
            )
            print(f"  + label {name}")
        except urllib.error.HTTPError as exc:
            print(f"  ! label {name}: HTTP {exc.code}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--create", action="store_true", help="actually create issues")
    ap.add_argument("--dry-run", action="store_true", help="print only (default)")
    args = ap.parse_args()

    with open(os.path.normpath(TODO_PATH), encoding="utf-8") as fh:
        items = parse_open_items(fh.read())
    print(f"open TODO items found: {len(items)}\n")

    planned = []
    for h2, h3, item in items:
        planned.append(
            {
                "title": make_title(item),
                "body": make_body(h2, h3, item),
                "labels": make_labels(h2, h3),
            }
        )

    if not args.create:
        for p in planned:
            print(f"- {p['title']}\n    labels: {', '.join(p['labels'])}")
        print("\n(dry run — pass --create with GITHUB_TOKEN to publish)")
        return 0

    token = os.environ.get("GITHUB_TOKEN", "").strip()
    if not token:
        print("GITHUB_TOKEN is required with --create", file=sys.stderr)
        return 2

    print("ensuring labels…")
    ensure_labels(token, {l for p in planned for l in p["labels"]})
    have = existing_titles(token)
    created = skipped = 0
    for p in planned:
        if p["title"] in have:
            skipped += 1
            continue
        try:
            issue = api(f"/repos/{REPO}/issues", token, "POST", p)
            print(f"  #{issue['number']} {p['title']}")
            created += 1
        except urllib.error.HTTPError as exc:
            print(f"  ! {p['title']}: HTTP {exc.code} {exc.read().decode()[:120]}")
    print(f"\ncreated {created}, skipped {skipped} (already present)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
