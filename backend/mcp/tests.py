import hashlib
import json
import secrets
import uuid

from django.contrib.auth.models import User
from django.test import TestCase, Client

from creators.models import Creator
from notes.models import Course, Note, PlannerEvent


def _make_api_key():
    """Return (plaintext, sha256_hex) for a test API key."""
    plaintext = f"ntc_{secrets.token_hex(16)}"
    return plaintext, hashlib.sha256(plaintext.encode()).hexdigest()


def _jsonrpc(method, params=None, req_id=1):
    body = {"jsonrpc": "2.0", "method": method, "id": req_id}
    if params is not None:
        body["params"] = params
    return body


def _sid():
    """Generate a unique sharing_id for test notes."""
    return uuid.uuid4().hex[:8]


class ApiKeyAuthTests(TestCase):
    """Tests for API key authentication and rotation."""

    def setUp(self):
        self.client = Client()
        self.user = User.objects.create_user(
            username="mcpuser", email="mcp@example.com", password="Strong1pw", is_active=True,
        )
        self.creator = Creator.objects.create(user_id=self.user)
        self.plaintext, self.key_hash = _make_api_key()
        self.creator.api_key_hash = self.key_hash
        self.creator.api_key_prefix = self.plaintext[:8]
        self.creator.save(update_fields=["api_key_hash", "api_key_prefix"])

    def test_valid_api_key_authenticates(self):
        response = self.client.post(
            "/mcp/",
            data=json.dumps(_jsonrpc("ping")),
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {self.plaintext}",
        )
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["jsonrpc"], "2.0")
        self.assertIn("result", data)

    def test_missing_api_key_returns_401(self):
        response = self.client.post(
            "/mcp/",
            data=json.dumps(_jsonrpc("ping")),
            content_type="application/json",
        )
        self.assertEqual(response.status_code, 401)

    def test_wrong_api_key_returns_401(self):
        response = self.client.post(
            "/mcp/",
            data=json.dumps(_jsonrpc("ping")),
            content_type="application/json",
            HTTP_AUTHORIZATION="Bearer ntc_0000000000000000000000000000dead",
        )
        self.assertEqual(response.status_code, 401)

    def test_non_ntc_bearer_ignored(self):
        response = self.client.post(
            "/mcp/",
            data=json.dumps(_jsonrpc("ping")),
            content_type="application/json",
            HTTP_AUTHORIZATION="Bearer some-other-token",
        )
        self.assertEqual(response.status_code, 401)


class ApiKeyRotationTests(TestCase):
    """Tests for the rotate-api-key endpoint."""

    def setUp(self):
        from rest_framework.authtoken.models import Token
        from rest_framework.test import APIClient

        self.client = APIClient()
        self.user = User.objects.create_user(
            username="rotator", email="rot@example.com", password="Strong1pw", is_active=True,
        )
        self.token = Token.objects.create(user=self.user)

    def test_rotate_api_key_returns_plaintext(self):
        response = self.client.post(
            "/api/v1/auth/rotate-api-key/",
            HTTP_AUTHORIZATION=f"Token {self.token.key}",
        )
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("api_key", data)
        self.assertTrue(data["api_key"].startswith("ntc_"))
        self.assertEqual(len(data["api_key"]), 4 + 32)  # "ntc_" + 32 hex
        self.assertEqual(data["api_key_prefix"], data["api_key"][:8])

    def test_rotated_key_works_for_mcp(self):
        response = self.client.post(
            "/api/v1/auth/rotate-api-key/",
            HTTP_AUTHORIZATION=f"Token {self.token.key}",
        )
        new_key = response.json()["api_key"]

        mcp_response = self.client.post(
            "/mcp/",
            data=_jsonrpc("ping"),
            format="json",
            HTTP_AUTHORIZATION=f"Bearer {new_key}",
        )
        self.assertEqual(mcp_response.status_code, 200)
        self.assertIn("result", mcp_response.json())

    def test_rotate_requires_authentication(self):
        response = self.client.post("/api/v1/auth/rotate-api-key/")
        self.assertIn(response.status_code, [401, 403])


class McpProtocolTests(TestCase):
    """Tests for MCP JSON-RPC protocol methods."""

    def setUp(self):
        self.client = Client()
        self.user = User.objects.create_user(
            username="proto", email="proto@example.com", password="Strong1pw", is_active=True,
        )
        self.creator = Creator.objects.create(user_id=self.user)
        self.plaintext, key_hash = _make_api_key()
        self.creator.api_key_hash = key_hash
        self.creator.api_key_prefix = self.plaintext[:8]
        self.creator.save(update_fields=["api_key_hash", "api_key_prefix"])

    def _post(self, body):
        return self.client.post(
            "/mcp/",
            data=json.dumps(body),
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {self.plaintext}",
        )

    def test_initialize(self):
        resp = self._post(_jsonrpc("initialize"))
        self.assertEqual(resp.status_code, 200)
        result = resp.json()["result"]
        self.assertEqual(result["protocolVersion"], "2025-03-26")
        self.assertEqual(result["serverInfo"]["name"], "notechondria-mcp")
        self.assertIn("tools", result["capabilities"])

    def test_ping(self):
        resp = self._post(_jsonrpc("ping"))
        self.assertEqual(resp.status_code, 200)
        self.assertIn("result", resp.json())

    def test_tools_list_returns_all_tools(self):
        resp = self._post(_jsonrpc("tools/list"))
        self.assertEqual(resp.status_code, 200)
        tools = resp.json()["result"]["tools"]
        self.assertIsInstance(tools, list)
        self.assertGreaterEqual(len(tools), 21)
        names = {t["name"] for t in tools}
        self.assertIn("get_profile", names)
        self.assertIn("list_notes", names)
        self.assertIn("create_note", names)
        self.assertIn("list_courses", names)
        self.assertIn("list_events", names)

    def test_unknown_method_returns_error(self):
        resp = self._post(_jsonrpc("nonexistent/method"))
        self.assertEqual(resp.status_code, 200)
        self.assertIn("error", resp.json())
        self.assertEqual(resp.json()["error"]["code"], -32601)

    def test_invalid_json_returns_parse_error(self):
        resp = self.client.post(
            "/mcp/",
            data="not json at all",
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {self.plaintext}",
        )
        self.assertEqual(resp.status_code, 400)

    def test_missing_jsonrpc_field(self):
        resp = self.client.post(
            "/mcp/",
            data=json.dumps({"method": "ping", "id": 1}),
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {self.plaintext}",
        )
        self.assertEqual(resp.status_code, 400)

    def test_wrong_content_type(self):
        resp = self.client.post(
            "/mcp/",
            data=json.dumps(_jsonrpc("ping")),
            content_type="text/plain",
            HTTP_AUTHORIZATION=f"Bearer {self.plaintext}",
        )
        self.assertEqual(resp.status_code, 415)

    def test_get_returns_405(self):
        resp = self.client.get(
            "/mcp/",
            HTTP_AUTHORIZATION=f"Bearer {self.plaintext}",
        )
        self.assertEqual(resp.status_code, 405)

    def test_delete_returns_200(self):
        resp = self.client.delete(
            "/mcp/",
            HTTP_AUTHORIZATION=f"Bearer {self.plaintext}",
        )
        self.assertEqual(resp.status_code, 200)

    def test_session_id_header_returned(self):
        resp = self._post(_jsonrpc("ping"))
        self.assertIn("Mcp-Session-Id", resp)

    def test_session_id_echoed(self):
        resp = self._post(_jsonrpc("ping"))
        session_id = resp["Mcp-Session-Id"]
        resp2 = self.client.post(
            "/mcp/",
            data=json.dumps(_jsonrpc("ping", req_id=2)),
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {self.plaintext}",
            HTTP_MCP_SESSION_ID=session_id,
        )
        self.assertEqual(resp2["Mcp-Session-Id"], session_id)


class McpToolTests(TestCase):
    """Tests for MCP tool invocations via tools/call."""

    def setUp(self):
        self.client = Client()
        self.user = User.objects.create_user(
            username="tooluser", email="tool@example.com", password="Strong1pw", is_active=True,
        )
        self.creator = Creator.objects.create(user_id=self.user)
        self.plaintext, key_hash = _make_api_key()
        self.creator.api_key_hash = key_hash
        self.creator.api_key_prefix = self.plaintext[:8]
        self.creator.save(update_fields=["api_key_hash", "api_key_prefix"])

        # Create default course for the user
        self.course = Course.objects.create(
            creator_id=self.creator, slug="inbox", title="Inbox", is_default=True,
        )

    def _call_tool(self, name, arguments=None, req_id=1):
        body = _jsonrpc("tools/call", {"name": name, "arguments": arguments or {}}, req_id)
        resp = self.client.post(
            "/mcp/",
            data=json.dumps(body),
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {self.plaintext}",
        )
        return resp

    def _tool_result(self, resp):
        """Extract the parsed JSON from the tool's text content."""
        data = resp.json()
        self.assertIn("result", data, data)
        content = data["result"]["content"]
        self.assertTrue(len(content) > 0)
        return json.loads(content[0]["text"])

    # --- Profile ---

    def test_get_profile(self):
        resp = self._call_tool("get_profile")
        self.assertEqual(resp.status_code, 200)
        result = self._tool_result(resp)
        self.assertEqual(result["username"], "tooluser")
        self.assertEqual(result["email"], "tool@example.com")

    def test_update_profile(self):
        resp = self._call_tool("update_profile", {"motto": "test motto", "first_name": "Test"})
        self.assertEqual(resp.status_code, 200)
        result = self._tool_result(resp)
        self.assertTrue(result["updated"])
        self.creator.refresh_from_db()
        self.assertEqual(self.creator.motto, "test motto")
        self.user.refresh_from_db()
        self.assertEqual(self.user.first_name, "Test")

    # --- Notes ---

    def test_create_and_get_note(self):
        resp = self._call_tool("create_note", {
            "title": "Test Note",
            "content": "Hello MCP",
            "course_id": self.course.id,
        })
        self.assertEqual(resp.status_code, 200)
        created = self._tool_result(resp)
        self.assertEqual(created["title"], "Test Note")
        self.assertEqual(created["content"], "Hello MCP")
        note_id = created["id"]

        resp2 = self._call_tool("get_note", {"note_id": note_id}, req_id=2)
        fetched = self._tool_result(resp2)
        self.assertEqual(fetched["id"], note_id)
        self.assertEqual(fetched["content"], "Hello MCP")

    def test_list_notes(self):
        Note.objects.create(
            creator_id=self.creator, course_id=self.course, sharing_id=_sid(), title="N1", content="c1",
        )
        Note.objects.create(
            creator_id=self.creator, course_id=self.course, sharing_id=_sid(), title="N2", content="c2",
        )
        resp = self._call_tool("list_notes")
        result = self._tool_result(resp)
        self.assertEqual(result["total"], 2)
        self.assertEqual(len(result["notes"]), 2)

    def test_list_notes_filter_by_course(self):
        other_course = Course.objects.create(
            creator_id=self.creator, slug="other", title="Other",
        )
        Note.objects.create(creator_id=self.creator, course_id=self.course, sharing_id=_sid(), title="In Inbox")
        Note.objects.create(creator_id=self.creator, course_id=other_course, sharing_id=_sid(), title="In Other")
        resp = self._call_tool("list_notes", {"course_id": self.course.id})
        result = self._tool_result(resp)
        self.assertEqual(result["total"], 1)
        self.assertEqual(result["notes"][0]["title"], "In Inbox")

    def test_update_note(self):
        note = Note.objects.create(
            creator_id=self.creator, course_id=self.course, sharing_id=_sid(), title="Old Title",
        )
        resp = self._call_tool("update_note", {"note_id": note.id, "title": "New Title"})
        result = self._tool_result(resp)
        self.assertEqual(result["title"], "New Title")
        note.refresh_from_db()
        self.assertEqual(note.title, "New Title")

    def test_delete_note(self):
        note = Note.objects.create(
            creator_id=self.creator, course_id=self.course, sharing_id=_sid(), title="Doomed",
        )
        resp = self._call_tool("delete_note", {"note_id": note.id})
        result = self._tool_result(resp)
        self.assertTrue(result["deleted"])
        note.refresh_from_db()
        self.assertIsNotNone(note.deleted_at)

    def test_search_notes(self):
        Note.objects.create(
            creator_id=self.creator, course_id=self.course, sharing_id=_sid(),
            title="Mitochondria", content="powerhouse",
        )
        Note.objects.create(
            creator_id=self.creator, course_id=self.course, sharing_id=_sid(),
            title="Ribosome", content="protein factory",
        )
        resp = self._call_tool("search_notes", {"query": "powerhouse"})
        result = self._tool_result(resp)
        self.assertEqual(result["count"], 1)
        self.assertEqual(result["notes"][0]["title"], "Mitochondria")

    # --- Courses ---

    def test_list_courses(self):
        resp = self._call_tool("list_courses")
        result = self._tool_result(resp)
        self.assertGreaterEqual(len(result["courses"]), 1)

    def test_create_course(self):
        resp = self._call_tool("create_course", {"title": "Biology 101"})
        result = self._tool_result(resp)
        self.assertEqual(result["title"], "Biology 101")
        self.assertFalse(result["is_default"])
        self.assertTrue(Course.objects.filter(slug="biology-101").exists())

    def test_update_course(self):
        course = Course.objects.create(
            creator_id=self.creator, slug="chem", title="Chemistry",
        )
        resp = self._call_tool("update_course", {"course_id": course.id, "title": "Organic Chem"})
        result = self._tool_result(resp)
        self.assertEqual(result["title"], "Organic Chem")

    def test_delete_course_moves_notes_to_default(self):
        extra = Course.objects.create(
            creator_id=self.creator, slug="extra", title="Extra",
        )
        note = Note.objects.create(
            creator_id=self.creator, course_id=extra, sharing_id=_sid(), title="Migrating",
        )
        resp = self._call_tool("delete_course", {"course_id": extra.id})
        result = self._tool_result(resp)
        self.assertTrue(result["deleted"])
        self.assertEqual(result["notes_moved_to"], self.course.id)
        note.refresh_from_db()
        self.assertEqual(note.course_id_id, self.course.id)

    def test_cannot_delete_default_course(self):
        resp = self._call_tool("delete_course", {"course_id": self.course.id})
        data = resp.json()
        self.assertTrue(data["result"].get("isError", False))

    # --- Planner events ---

    def test_create_and_list_events(self):
        resp = self._call_tool("create_event", {
            "title": "Study Session",
            "event_date": "2026-04-15",
        })
        result = self._tool_result(resp)
        self.assertEqual(result["title"], "Study Session")
        event_id = result["id"]

        resp2 = self._call_tool("list_events", {}, req_id=2)
        result2 = self._tool_result(resp2)
        self.assertEqual(len(result2["events"]), 1)
        self.assertEqual(result2["events"][0]["id"], event_id)

    def test_update_event(self):
        event = PlannerEvent.objects.create(
            creator_id=self.creator, title="Old Event", event_date="2026-04-15",
        )
        resp = self._call_tool("update_event", {
            "event_id": event.id,
            "title": "Updated Event",
            "is_completed": True,
        })
        result = self._tool_result(resp)
        self.assertEqual(result["title"], "Updated Event")
        self.assertTrue(result["is_completed"])

    # --- Versions ---

    def test_snapshot_and_list_versions(self):
        note = Note.objects.create(
            creator_id=self.creator, course_id=self.course, sharing_id=_sid(), title="Versioned", content="v1",
        )
        resp = self._call_tool("snapshot_note", {"note_id": note.id, "reason": "test"})
        result = self._tool_result(resp)
        self.assertIn("version_id", result)

        resp2 = self._call_tool("list_note_versions", {"note_id": note.id}, req_id=2)
        result2 = self._tool_result(resp2)
        self.assertEqual(len(result2["versions"]), 1)
        self.assertEqual(result2["versions"][0]["reason"], "test")

    # --- Attachments ---

    def test_list_attachments_empty(self):
        note = Note.objects.create(
            creator_id=self.creator, course_id=self.course, sharing_id=_sid(), title="No Attachments",
        )
        resp = self._call_tool("list_attachments", {"note_id": note.id})
        result = self._tool_result(resp)
        self.assertEqual(result["attachments"], [])

    # --- Heatmap / Activity ---

    def test_get_heatmap(self):
        resp = self._call_tool("get_heatmap")
        self.assertEqual(resp.status_code, 200)
        self.assertNotIn("isError", resp.json()["result"])

    def test_get_recent_activity(self):
        Note.objects.create(
            creator_id=self.creator, course_id=self.course, sharing_id=_sid(), title="Recent",
        )
        resp = self._call_tool("get_recent_activity")
        result = self._tool_result(resp)
        self.assertEqual(len(result["recent_notes"]), 1)

    # --- Unknown tool ---

    def test_unknown_tool_returns_error(self):
        resp = self._call_tool("nonexistent_tool")
        data = resp.json()
        self.assertIn("error", data)
        self.assertEqual(data["error"]["code"], -32601)

    # --- Cross-user isolation ---

    def test_cannot_access_other_users_note(self):
        other_user = User.objects.create_user(
            username="other", email="other@example.com", password="Strong1pw", is_active=True,
        )
        other_creator = Creator.objects.create(user_id=other_user)
        other_note = Note.objects.create(
            creator_id=other_creator, course_id=self.course, sharing_id=_sid(), title="Secret",
        )
        resp = self._call_tool("get_note", {"note_id": other_note.id})
        data = resp.json()
        # Should be an error result (404 wrapped as tool error)
        self.assertTrue(data["result"].get("isError", False))
