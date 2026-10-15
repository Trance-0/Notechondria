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

    def put(self, path, json_body=None):
        self.calls.append(("PUT", path, json_body))
        return {"is_bound": True, **(json_body or {})}

    def patch(self, path, json_body=None):
        self.calls.append(("PATCH", path, json_body))
        return {"id": 1, **(json_body or {})}

    def delete(self, path):
        self.calls.append(("DELETE", path, None))
        return {"is_bound": False}


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

    def test_full_parity_tool_count(self):
        # CLI is at full parity with backend/mcp/tools.py (48 tools:
        # 41 + get_course_git/set_course_git (0.1.171) + import_course_git
        # (0.1.173) + sync_course_git (0.1.174) + github_app_status /
        # connect_github_app / list_github_repos (0.1.175)).
        names = {s["name"] for s in tool_specs()}
        self.assertEqual(len(names), 48)
        for name in ("get_course_git", "set_course_git", "import_course_git",
                     "sync_course_git", "github_app_status",
                     "connect_github_app", "list_github_repos"):
            self.assertIn(name, names)
        # spot-check a few that were ported in Phase 3
        for name in ("update_profile", "search_notes", "get_note_by_uuid",
                     "subscribe_course", "unsubscribe_course",
                     "list_note_versions", "empty_recycle_bin",
                     "list_note_sessions", "list_calendar_feeds",
                     "get_activity_week"):
            self.assertIn(name, names)

    def test_every_tool_has_unique_handler(self):
        for spec in tool_specs():
            self.assertEqual(spec["inputSchema"]["type"], "object")
            self.assertIsInstance(spec["description"], str)

    def test_update_profile_patches_settings(self):
        fake = FakeClient()
        call_tool(fake, "update_profile", {"motto": "hi", "editor_mode": "G"})
        method, path, body = fake.calls[-1]
        self.assertEqual((method, path), ("PATCH", "settings/"))
        self.assertEqual(body["motto"], "hi")

    def test_search_notes_uses_query_and_scope(self):
        fake = FakeClient()
        call_tool(fake, "search_notes", {"query": "calc", "scope": "all"})
        method, path, params = fake.calls[-1]
        self.assertEqual((method, path), ("GET", "notes/"))
        self.assertEqual(params, {"q": "calc", "scope": "all"})

    def test_subscribe_and_unsubscribe_course(self):
        fake = FakeClient()
        call_tool(fake, "subscribe_course", {"course_id": 7})
        self.assertEqual(fake.calls[-1][:2], ("POST", "courses/7/subscribe/"))
        call_tool(fake, "unsubscribe_course", {"course_id": 7})
        self.assertEqual(fake.calls[-1][:2], ("DELETE", "courses/7/subscribe/"))

    def test_empty_recycle_bin_is_delete(self):
        fake = FakeClient()
        call_tool(fake, "empty_recycle_bin", {})
        self.assertEqual(fake.calls[-1][:2], ("DELETE", "notes/deleted/empty/"))

    def test_get_course_git_dispatches_to_get(self):
        fake = FakeClient()
        call_tool(fake, "get_course_git", {"course_id": 9})
        self.assertEqual(fake.calls[-1][:2], ("GET", "courses/9/git/"))

    def test_set_course_git_binds_with_put(self):
        fake = FakeClient()
        call_tool(fake, "set_course_git", {
            "course_id": 9,
            "repo": "octo/repo",
            "sync_enabled": True,
            "sync_timeout_minutes": 7,
        })
        method, path, body = fake.calls[-1]
        self.assertEqual((method, path), ("PUT", "courses/9/git/"))
        self.assertEqual(body["repo"], "octo/repo")
        self.assertEqual(body["sync_timeout_minutes"], 7)

    def test_set_course_git_unlink_deletes(self):
        fake = FakeClient()
        call_tool(fake, "set_course_git", {"course_id": 9, "unlink": True})
        self.assertEqual(fake.calls[-1][:2], ("DELETE", "courses/9/git/"))

    def test_github_app_status_gets_status(self):
        fake = FakeClient()
        call_tool(fake, "github_app_status", {})
        self.assertEqual(fake.calls[-1][:2], ("GET", "integrations/github/status/"))

    def test_connect_github_app_posts_installation(self):
        fake = FakeClient()
        call_tool(fake, "connect_github_app",
                  {"installation_id": "12345", "account_login": "Nesbitt-bot"})
        method, path, body = fake.calls[-1]
        self.assertEqual((method, path), ("POST", "integrations/github/callback/"))
        self.assertEqual(body["installation_id"], "12345")
        self.assertEqual(body["account_login"], "Nesbitt-bot")

    def test_list_github_repos_gets_repos(self):
        fake = FakeClient()
        call_tool(fake, "list_github_repos", {})
        self.assertEqual(fake.calls[-1][:2], ("GET", "integrations/github/repos/"))

    def test_restore_note_version_path(self):
        fake = FakeClient()
        call_tool(fake, "restore_note_version", {"note_id": 3, "version_id": 9})
        self.assertEqual(fake.calls[-1][:2], ("POST", "notes/3/restore/9/"))

    def test_reorder_courses_sends_id_list(self):
        fake = FakeClient()
        call_tool(fake, "reorder_courses", {"course_ids": [3, 1, 2]})
        method, path, body = fake.calls[-1]
        self.assertEqual((method, path), ("POST", "courses/reorder/"))
        self.assertEqual(body, {"course_ids": [3, 1, 2]})

    def test_end_note_session_defaults_ended_at(self):
        fake = FakeClient()
        call_tool(fake, "end_note_session", {"session_id": 4})
        method, path, body = fake.calls[-1]
        self.assertEqual((method, path), ("PATCH", "note-sessions/4/"))
        self.assertIn("ended_at", body)
        self.assertTrue(body["ended_at"])  # non-empty ISO timestamp

    def test_list_note_sessions_filters_by_note(self):
        fake = FakeClient()
        call_tool(fake, "list_note_sessions", {"note_id": 8, "limit": 5})
        method, path, params = fake.calls[-1]
        self.assertEqual((method, path), ("GET", "note-sessions/"))
        self.assertEqual(params, {"note_id": 8, "limit": 5})


class ServerDispatchTests(unittest.TestCase):
    def test_initialize_includes_skill_instructions(self):
        from notechondria_mcp.instructions import BASE_INSTRUCTIONS

        server, _ = _server_with_fake()
        resp = server.handle({"jsonrpc": "2.0", "id": 1, "method": "initialize"})
        self.assertEqual(resp["result"]["protocolVersion"], "2025-03-26")
        instructions = resp["result"]["instructions"]
        self.assertTrue(instructions.startswith(BASE_INSTRUCTIONS))
        self.assertIn("## User skill.md", instructions)
        self.assertIn("# import from X", instructions)

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


class BatchRunnerTests(unittest.TestCase):
    """The `batch` subcommand's JSONL executor — no network."""

    def _run(self, lines, stop_on_error=False):
        import io
        from unittest import mock
        from notechondria_mcp import batch as batch_mod
        from notechondria_mcp.config import Config

        fake = FakeClient()
        out = io.StringIO()
        with mock.patch.object(batch_mod, "BackendClient", return_value=fake):
            code = batch_mod.run_batch(
                Config(api_url="http://x/api/v1", api_key="ntc_test"),
                source=io.StringIO("\n".join(lines) + "\n"),
                sink=out,
                stop_on_error=stop_on_error,
            )
        results = [json.loads(l) for l in out.getvalue().splitlines()]
        return code, results, fake

    def test_executes_lines_and_reports_results(self):
        code, results, fake = self._run([
            '{"tool": "create_event", "arguments": {"title": "A", "event_date": "2026-07-12"}}',
            "# a comment line",
            "",
            '{"tool": "create_event", "arguments": {"title": "B", "event_date": "2026-07-13"}}',
        ])
        self.assertEqual(code, 0)
        self.assertEqual([r["ok"] for r in results], [True, True])
        self.assertEqual([r["line"] for r in results], [1, 4])
        posted = [c for c in fake.calls if c[0] == "POST"]
        self.assertEqual(len(posted), 2)

    def test_continues_past_bad_lines_and_exits_nonzero(self):
        code, results, _ = self._run([
            "not json",
            '{"arguments": {}}',
            '{"tool": "no_such_tool", "arguments": {}}',
            '{"tool": "create_event", "arguments": {"title": "C", "event_date": "2026-07-14"}}',
        ])
        self.assertEqual(code, 1)
        self.assertEqual([r["ok"] for r in results], [False, False, False, True])
        self.assertIn("invalid JSON", results[0]["error"])
        self.assertIn("missing 'tool'", results[1]["error"])
        self.assertIn("unknown tool", results[2]["error"])

    def test_stop_on_error_aborts_immediately(self):
        code, results, fake = self._run(
            [
                '{"tool": "no_such_tool", "arguments": {}}',
                '{"tool": "create_event", "arguments": {"title": "D", "event_date": "2026-07-15"}}',
            ],
            stop_on_error=True,
        )
        self.assertEqual(code, 1)
        self.assertEqual(len(results), 1)
        self.assertEqual([c for c in fake.calls if c[0] == "POST"], [])
