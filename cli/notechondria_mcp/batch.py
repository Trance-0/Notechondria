"""Batch tool execution: ``notechondria-mcp batch [file]``.

Reads newline-delimited JSON — one ``{"tool": <name>, "arguments":
{...}}`` object per line — from a file (or stdin when the path is
``-`` or omitted) and executes the calls sequentially against the
backend. One JSON result object is printed per input line:

    {"line": 3, "tool": "create_event", "ok": true,  "result": {...}}
    {"line": 4, "tool": "create_event", "ok": false, "error": "..."}

Per-item failures do not stop the run (pass ``--stop-on-error`` to
abort on the first failure). Blank lines and ``#`` comment lines are
skipped. Exit code: 0 when every item succeeded, 1 when any failed,
2 on a malformed input line with ``--stop-on-error``.

This is the bulk path the MCP server instructions point agents to
(importing a syllabus of deadlines, creating many notes) — one
process, sequential requests, no JSON-RPC envelope per line.
"""

from __future__ import annotations

import json
import sys
from typing import Any, Optional, TextIO

from .client import BackendClient, BackendError
from .config import Config
from .tools import call_tool


def run_batch(
    config: Config,
    source: Optional[TextIO] = None,
    sink: Optional[TextIO] = None,
    stop_on_error: bool = False,
) -> int:
    """Execute a JSONL tool-call stream. Returns the process exit code."""
    source = source if source is not None else sys.stdin
    sink = sink if sink is not None else sys.stdout
    client = BackendClient(config)
    any_failed = False

    for line_no, raw in enumerate(source, start=1):
        raw = raw.strip()
        if not raw or raw.startswith("#"):
            continue

        def _emit(payload: dict) -> None:
            sink.write(json.dumps(payload, ensure_ascii=False, default=str) + "\n")
            sink.flush()

        try:
            item = json.loads(raw)
        except ValueError as exc:
            any_failed = True
            _emit({"line": line_no, "ok": False, "error": f"invalid JSON: {exc}"})
            if stop_on_error:
                return 2
            continue

        tool = item.get("tool") if isinstance(item, dict) else None
        arguments = item.get("arguments") or {} if isinstance(item, dict) else {}
        if not isinstance(tool, str) or not tool:
            any_failed = True
            _emit({"line": line_no, "ok": False, "error": "missing 'tool' field"})
            if stop_on_error:
                return 2
            continue

        result: Any
        try:
            result = call_tool(client, tool, arguments)
        except KeyError:
            any_failed = True
            _emit({"line": line_no, "tool": tool, "ok": False, "error": f"unknown tool: {tool}"})
            if stop_on_error:
                return 1
            continue
        except Exception as exc:  # noqa: BLE001 — per-item fault tolerance (incl. BackendError)
            any_failed = True
            _emit({"line": line_no, "tool": tool, "ok": False, "error": str(exc)})
            if stop_on_error:
                return 1
            continue

        _emit({"line": line_no, "tool": tool, "ok": True, "result": result})

    return 1 if any_failed else 0
