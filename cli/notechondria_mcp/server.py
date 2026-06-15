"""MCP server over stdio (newline-delimited JSON-RPC 2.0).

Mirrors the request handling of the in-backend ``backend/mcp/protocol.py``
(initialize / tools/list / tools/call / ping / notifications) so an agent
sees the same protocol surface, but runs as a local process that calls
the backend over ``/api/v1`` instead of touching the Django ORM.

Transport: read one JSON-RPC message per line from stdin, write one
JSON response per line to stdout. Notifications (no ``id``) get no
response. This is the MCP stdio convention used by desktop agent hosts.
"""

from __future__ import annotations

import json
import sys
from typing import Any, Optional

from . import __version__
from .client import BackendClient, BackendError
from .config import Config
from .tools import call_tool, tool_specs

PROTOCOL_VERSION = "2025-03-26"
SERVER_INFO = {"name": "notechondria-mcp-cli", "version": __version__}


class McpServer:
    def __init__(self, config: Config):
        self._client = BackendClient(config)

    # --- JSON-RPC plumbing --------------------------------------------

    @staticmethod
    def _result(req_id: Any, result: Any) -> dict:
        return {"jsonrpc": "2.0", "id": req_id, "result": result}

    @staticmethod
    def _error(req_id: Any, code: int, message: str) -> dict:
        return {
            "jsonrpc": "2.0",
            "id": req_id,
            "error": {"code": code, "message": message},
        }

    def handle(self, message: dict) -> Optional[dict]:
        """Dispatch one JSON-RPC message; return a response dict, or None
        for notifications (no ``id``)."""
        req_id = message.get("id")
        method = message.get("method")
        params = message.get("params") or {}

        if method == "initialize":
            return self._result(req_id, self._initialize())
        if method == "notifications/initialized":
            return None  # client ack; no response
        if method == "ping":
            return self._result(req_id, {})
        if method == "tools/list":
            return self._result(req_id, {"tools": tool_specs()})
        if method == "tools/call":
            return self._tools_call(req_id, params)

        if req_id is None:
            return None  # unknown notification — ignore
        return self._error(req_id, -32601, f"Method not found: {method}")

    # --- methods ------------------------------------------------------

    def _initialize(self) -> dict:
        # Fetch the user's skill.md so the agent reads the import/export
        # playbook on connect, matching the in-backend MCP behavior.
        instructions = ""
        try:
            profile = call_tool(self._client, "get_profile", {})
            if isinstance(profile, dict):
                instructions = str(profile.get("mcp_skill_md") or "")
        except Exception:  # noqa: BLE001 — initialize must not hard-fail
            instructions = ""
        result = {
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {"tools": {"listChanged": False}},
            "serverInfo": SERVER_INFO,
        }
        if instructions:
            result["instructions"] = instructions
        return result

    def _tools_call(self, req_id: Any, params: dict) -> dict:
        name = params.get("name", "")
        arguments = params.get("arguments") or {}
        try:
            result = call_tool(self._client, name, arguments)
        except KeyError:
            return self._error(req_id, -32602, f"Unknown tool: {name}")
        except BackendError as exc:
            return self._result(req_id, {
                "content": [{"type": "text", "text": str(exc)}],
                "isError": True,
            })
        except Exception as exc:  # noqa: BLE001 — surface as tool error
            return self._result(req_id, {
                "content": [{"type": "text", "text": f"tool failed: {exc}"}],
                "isError": True,
            })
        return self._result(req_id, {
            "content": [{
                "type": "text",
                "text": json.dumps(result, ensure_ascii=False, default=str),
            }],
        })


def serve_stdio(config: Config) -> int:
    """Run the stdio read/dispatch/write loop until EOF. Returns an exit
    code."""
    server = McpServer(config)
    stdin = sys.stdin
    stdout = sys.stdout
    for line in stdin:
        line = line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except ValueError:
            # Per JSON-RPC, a parse error with no id is reported with null.
            _write(stdout, McpServer._error(None, -32700, "Parse error"))
            continue
        response = server.handle(message)
        if response is not None:
            _write(stdout, response)
    return 0


def _write(stdout, payload: dict) -> None:
    stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
    stdout.flush()
