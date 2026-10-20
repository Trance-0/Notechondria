"""Expected values of test/local_folder/planner_recurrence_test.dart.

Run from this directory with CPython 3: `python3 recurrence_cases.py`. It
loads `_add_months`, `_add_period`, `_MAX_OCCURRENCES`,
`_expand_occurrence_dates`, and `normalize_calendar_url` from
backend/notes/services.py itself (by AST, so Django is not needed) and
prints the cases embedded in the test's `_cases` constant.
"""
import ast
import base64
import json
import sys
import urllib.parse
from datetime import date, timedelta
from pathlib import Path
from types import SimpleNamespace

SERVICES = Path(__file__).resolve().parents[4] / "backend" / "notes" / "services.py"
WANTED = {"_add_months", "_add_period", "_MAX_OCCURRENCES",
          "_expand_occurrence_dates", "normalize_calendar_url"}

tree = ast.parse(SERVICES.read_text(encoding="utf-8"))
nodes = []
for node in tree.body:
    if isinstance(node, ast.FunctionDef) and node.name in WANTED:
        nodes.append(node)
    elif isinstance(node, ast.Assign) and any(
            isinstance(t, ast.Name) and t.id in WANTED for t in node.targets):
        nodes.append(node)
scope = {"date": date, "timedelta": timedelta, "urllib": urllib, "base64": base64}
exec(compile(ast.Module(body=nodes, type_ignores=[]), str(SERVICES), "exec"), scope)


def d(text):
    return date.fromisoformat(text) if text else None


# (freq, interval, base, end_date, count, window_start, window_end)
expand_cases = [
    ("N", 1, "2026-10-21", None, None, "2026-10-19", "2026-10-25"),
    ("N", 1, "2026-10-26", None, None, "2026-10-19", "2026-10-25"),
    ("W", 1, "2026-09-01", None, None, "2026-10-19", "2026-11-17"),
    ("W", 2, "2026-10-05", None, 3, "2026-10-01", "2027-01-31"),
    ("W", 1, "2026-10-05", "2026-10-26", None, "2026-10-01", "2026-12-31"),
    ("W", 0, "2026-10-05", None, 2, "2026-10-01", "2026-12-31"),
    ("M", 1, "2027-01-31", None, 6, "2027-01-01", "2027-12-31"),
    ("M", 1, "2028-01-31", None, 3, "2028-01-01", "2028-12-31"),
    ("M", 3, "2026-11-30", "2027-09-01", None, "2026-01-01", "2027-12-31"),
    ("Y", 1, "2028-02-29", None, 5, "2028-01-01", "2033-12-31"),
    ("Y", 2, "2026-10-19", None, None, "2030-01-01", "2034-12-31"),
    ("M", 1, "2026-10-15", None, 1, "2026-11-01", "2026-12-31"),
    ("W", 1, "2026-10-19", None, 0, "2026-10-01", "2026-12-31"),
    ("W", 1, "2026-01-05", None, None, "2101-01-01", "2101-02-01"),
    ("W", 1, "2026-01-05", None, None, "2102-08-01", "2102-09-30"),
]
expand = []
for freq, interval, base, end, count, ws, we in expand_cases:
    event = SimpleNamespace(recurrence_freq=freq, recurrence_interval=interval,
                            event_date=d(base), recurrence_end_date=d(end),
                            recurrence_count=count)
    dates = [x.isoformat() for x in scope["_expand_occurrence_dates"](event, d(ws), d(we))]
    expand.append([freq, interval, base, end, count, ws, we, dates])

cid = base64.urlsafe_b64encode(b"team@group.calendar.google.com").decode().rstrip("=")
url_cases = [
    "",
    "https://example.com/feed.ics",
    "https://calendar.google.com/calendar/ical/abc%40group.calendar.google.com/public/basic.ics",
    "https://calendar.google.com/calendar/embed?src=abc%40group.calendar.google.com&ctz=UTC",
    "https://calendar.google.com/calendar/embed?src=en.usa%23holiday%40group.v.calendar.google.com",
    "https://calendar.google.com/calendar/u/0/r?cid=" + cid,
    "https://calendar.google.com/calendar?cid=" + cid + "==",
    "https://Calendar.Google.com/calendar/embed?src=a+b%21%2A%28%29",
    "https://calendar.google.com/calendar/embed?ctz=UTC",
    "https://calendar.google.com/calendar/embed?src=&cid=" + cid,
    "https://calendar.google.com/calendar/r?cid=%21%21%21",
]
urls = [[u, scope["normalize_calendar_url"](u)] for u in url_cases]
json.dump({"expand": expand, "urls": urls}, sys.stdout, indent=1)
