"""Unit tests for the MCP dispatch — no network, no MCP SDK.

Run from the ``cli/`` directory: ``python -m unittest discover tests``.
"""

import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from notechondria_mcp.config import Config  # noqa: E402
from notechondria_mcp.server import McpServer  # noqa: E402
from notechondria_mcp.tools import call_tool, tool_specs  # noqa: E402


class FakeClient:
    """Records calls and returns canned data instead of hitting HTTP."""

    def __init__(self, responses=None):
        self.calls = []
        self.responses = responses or {}

    def get(self, path, params=None):
        self.calls.append(("GET", path, params))
        if path == "settings/":
            return {"username": "alice", "mcp_skill_md": "# import from X"}
        return self.responses.get(("GET", path), {"results": [], "has_more": False})

    def post(self, path, json_body=None):
        self.calls.append(("POST", path, json_body))
        return {"id": 1, **(json_body or {})}

    def patch(self, path, json_body=None):
        self.calls.append(("PATCH", path, json_body))
        return {"id": 1, **(json_body or {})}

    def delete(self, path):
        self.calls.append(("DELETE", path, None))
        return None


def _server_with_fake():
    server = McpServer(Config(api_url="http://x/api/v1", api_key="ntc_test"))
    fake = FakeClient()
    server._client = fake
    return server, fake


class ToolRegistryTests(unittest.TestCase):
    def test_specs_have_required_shape(self):
        specs = tool_specs()
        names = {s["name"] for s in specs}
        self.assertIn("list_notes", names)
        self.assertIn("create_note", names)
        for spec in specs:
            self.assertIn("description", spec)
            self.assertEqual(spec["inputSchema"]["type"], "object")

    def test_list_notes_dispatches_to_get(self):
        fake = FakeClient()
        call_tool(fake, "list_notes", {"course_id": 5, "q": "math"})
        method, path, params = fake.calls[-1]
        self.assertEqual((method, path), ("GET", "notes/"))
        self.assertEqual(params["course_id"], 5)
        self.assertEqual(params["q"], "math")

    def test_create_note_posts_body(self):
        fake = FakeClient()
        call_tool(fake, "create_note", {"title": "Hi", "content": "Body"})
        method, path, body = fake.calls[-1]
        self.assertEqual((method, path), ("POST", "notes/"))
        self.assertEqual(body["title"], "Hi")

    def test_unknown_tool_raises_keyerror(self):
        with self.assertRaises(KeyError):
            call_tool(FakeClient(), "no_such_tool", {})


class ServerDispatchTests(unittest.TestCase):
    def test_initialize_includes_skill_instructions(self):
        server, _ = _server_with_fake()
        resp = server.handle({"jsonrpc": "2.0", "id": 1, "method": "initialize"})
        self.assertEqual(resp["result"]["protocolVersion"], "2025-03-26")
        self.assertEqual(resp["result"]["instructions"], "# import from X")

    def test_tools_list(self):
        server, _ = _server_with_fake()
        resp = server.handle({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
        self.assertTrue(any(t["name"] == "get_note"
                            for t in resp["result"]["tools"]))

    def test_tools_call_wraps_text_content(self):
        server, _ = _server_with_fake()
        resp = server.handle({
            "jsonrpc": "2.0", "id": 3, "method": "tools/call",
            "params": {"name": "list_courses", "arguments": {}},
        })
        content = resp["result"]["content"]
        self.assertEqual(content[0]["type"], "text")
        json.loads(content[0]["text"])  # valid JSON

    def test_tools_call_unknown_tool_is_error(self):
        server, _ = _server_with_fake()
        resp = server.handle({
            "jsonrpc": "2.0", "id": 4, "method": "tools/call",
            "params": {"name": "nope", "arguments": {}},
        })
        self.assertEqual(resp["error"]["code"], -32602)

    def test_notification_returns_none(self):
        server, _ = _server_with_fake()
        resp = server.handle({
            "jsonrpc": "2.0", "method": "notifications/initialized"})
        self.assertIsNone(resp)

    def test_unknown_method_is_error(self):
        server, _ = _server_with_fake()
        resp = server.handle({"jsonrpc": "2.0", "id": 5, "method": "bogus"})
        self.assertEqual(resp["error"]["code"], -32601)


if __name__ == "__main__":
    unittest.main()
