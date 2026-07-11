import hashlib
import json
import secrets
import uuid
from datetime import timedelta

from django.contrib.auth.models import User
from django.test import TestCase, Client
from django.utils import timezone

from creators.models import Creator
from courses.models import Course, CourseSubscription
from notes.models import (
    Note,
    NoteActivitySession,
    NoteVersion,
    RecycleBinEntry,
)
from planner.models import CalendarFeed, PlannerEvent


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

        # 0.1.120: ``Course.is_default`` retired; use a plain category.
        self.course = Course.objects.create(
            creator_id=self.creator, slug="inbox", title="Inbox",
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
        # 0.1.120: ``is_default`` is no longer in the payload.
        self.assertNotIn("is_default", result)
        self.assertTrue(Course.objects.filter(slug="biology-101").exists())

    def test_update_course(self):
        course = Course.objects.create(
            creator_id=self.creator, slug="chem", title="Chemistry",
        )
        resp = self._call_tool("update_course", {"course_id": course.id, "title": "Organic Chem"})
        result = self._tool_result(resp)
        self.assertEqual(result["title"], "Organic Chem")

    def test_set_and_get_course_git_binding(self):
        course = Course.objects.create(
            creator_id=self.creator, slug="git-mcp", title="Git MCP",
        )
        resp = self._call_tool("set_course_git", {
            "course_id": course.id,
            "repo": "octo/repo",
            "sync_enabled": True,
            "sync_timeout_minutes": 8,
        })
        result = self._tool_result(resp)
        self.assertEqual(result["repo"], "octo/repo")
        self.assertTrue(result["is_bound"])
        self.assertEqual(result["sync_timeout_minutes"], 8)
        # get_course_git reflects it.
        got = self._tool_result(self._call_tool("get_course_git", {"course_id": course.id}))
        self.assertEqual(got["repo"], "octo/repo")
        # Unlink clears it.
        cleared = self._tool_result(
            self._call_tool("set_course_git", {"course_id": course.id, "unlink": True})
        )
        self.assertFalse(cleared["is_bound"])

    def test_import_course_git_creates_notes(self):
        from unittest.mock import patch
        from creators.models import GithubIntegration

        course = Course.objects.create(
            creator_id=self.creator, slug="git-import", title="Git Import",
            git_repo="octo/docs", git_branch="main",
        )
        GithubIntegration.objects.create(
            creator=self.creator, installation_id="inst-mcp",
        )
        files = {
            "docs/intro.md": "# Intro\nbody",
            "docs/unit/lesson.md": "# Lesson\nbody",
        }
        with patch("courses.git_service.fetch_course_repo",
                   return_value=(None, files, list(files))):
            resp = self._call_tool("import_course_git", {"course_id": course.id})
        result = self._tool_result(resp)
        self.assertEqual(result["created"], 2)
        self.assertEqual(
            Note.objects.filter(course_id=course).exclude(git_path__isnull=True).count(),
            2,
        )

    def test_sync_course_git_pushes_notes(self):
        from unittest.mock import patch
        from creators.models import GithubIntegration
        import courses.git_service as git_service

        course = Course.objects.create(
            creator_id=self.creator, slug="git-sync", title="Git Sync",
            git_repo="octo/docs", git_branch="main", git_sync_enabled=True,
            git_pending_since=timezone.now(),
        )
        GithubIntegration.objects.create(
            creator=self.creator, installation_id="inst-sync-mcp",
        )
        Note.objects.create(
            creator_id=self.creator, course_id=course, sharing_id=_sid(),
            title="Lesson", content="# Lesson\n\nbody", git_path="docs/l.md",
            custom_meta='{"sidebar_position": 1}',
        )
        with patch.object(git_service, "_commit_files", return_value="sha") as m:
            resp = self._call_tool("sync_course_git", {"course_id": course.id})
        result = self._tool_result(resp)
        self.assertEqual(result["files"], 1)
        m.assert_called_once()
        course.refresh_from_db()
        self.assertIsNone(course.git_pending_since)

    def test_delete_course_orphans_notes_to_uncategorized(self):
        extra = Course.objects.create(
            creator_id=self.creator, slug="extra", title="Extra",
        )
        note = Note.objects.create(
            creator_id=self.creator, course_id=extra, sharing_id=_sid(),
            title="Migrating",
        )
        resp = self._call_tool("delete_course", {"course_id": extra.id})
        result = self._tool_result(resp)
        self.assertTrue(result["deleted"])
        # 0.1.120: ``notes_moved_to`` is gone — SET_NULL drops the
        # reference instead of pointing it at a "default" course.
        self.assertNotIn("notes_moved_to", result)
        note.refresh_from_db()
        self.assertIsNone(note.course_id_id)

    def test_can_delete_any_owned_course(self):
        # 0.1.120: there's no longer a "default" Course to protect, so
        # the previous test_cannot_delete_default_course assertion no
        # longer holds. Every owned category is freely deletable.
        resp = self._call_tool("delete_course", {"course_id": self.course.id})
        result = self._tool_result(resp)
        self.assertTrue(result["deleted"])
        self.assertFalse(Course.objects.filter(pk=self.course.id).exists())

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

    def test_create_event_normalizes_window_like_rest(self):
        # A bare-date create must store the same default noon one-hour
        # window the REST POST assigns (normalize_planner_event_window),
        # so MCP- and app-created events are indistinguishable.
        resp = self._call_tool("create_event", {
            "title": "Bare-date task",
            "event_date": "2026-04-15",
        })
        result = self._tool_result(resp)
        event = PlannerEvent.objects.get(pk=result["id"])
        self.assertIsNotNone(event.starts_at)
        self.assertIsNotNone(event.ends_at)
        self.assertEqual(timezone.localtime(event.starts_at).hour, 12)
        self.assertEqual(event.ends_at - event.starts_at, timedelta(hours=1))
        self.assertEqual(result["starts_at"], event.starts_at.isoformat())

    def test_update_event_reopen_clears_completed_at(self):
        event = PlannerEvent.objects.create(
            creator_id=self.creator,
            title="Done task",
            event_date="2026-04-15",
            is_completed=True,
            completed_at=timezone.now(),
        )
        resp = self._call_tool("update_event", {
            "event_id": event.id,
            "is_completed": False,
        })
        result = self._tool_result(resp)
        self.assertFalse(result["is_completed"])
        event.refresh_from_db()
        self.assertIsNone(event.completed_at)

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

    # --- Recycle bin ---

    def test_recycle_bin_lifecycle(self):
        note = Note.objects.create(
            creator_id=self.creator,
            course_id=self.course,
            sharing_id=_sid(),
            title="Trash me",
        )
        # Soft-delete via existing tool
        del_resp = self._call_tool("delete_note", {"note_id": note.id})
        self.assertEqual(del_resp.status_code, 200)

        list_resp = self._call_tool("list_deleted_notes")
        listed = self._tool_result(list_resp)
        self.assertEqual(len(listed["deleted_notes"]), 1)
        self.assertEqual(listed["deleted_notes"][0]["id"], note.id)

        restore_resp = self._call_tool(
            "restore_deleted_note", {"note_id": note.id}
        )
        restored = self._tool_result(restore_resp)
        self.assertEqual(restored["id"], note.id)
        note.refresh_from_db()
        self.assertIsNone(note.deleted_at)

        # Re-delete so we can test empty_recycle_bin
        self._call_tool("delete_note", {"note_id": note.id})
        empty_resp = self._call_tool("empty_recycle_bin")
        result = self._tool_result(empty_resp)
        self.assertEqual(result["deleted_count"], 1)
        self.assertFalse(Note.objects.filter(pk=note.id).exists())

    # --- Note UUID lookup + version restore ---

    def test_get_note_by_uuid_owner(self):
        note = Note.objects.create(
            creator_id=self.creator,
            course_id=self.course,
            sharing_id=_sid(),
            title="UUID fetch",
            content="body",
        )
        resp = self._call_tool("get_note_by_uuid", {"uuid": str(note.uuid)})
        result = self._tool_result(resp)
        self.assertEqual(result["id"], note.id)
        self.assertEqual(result["title"], "UUID fetch")

    def test_get_note_by_uuid_blocks_private_foreign(self):
        other = User.objects.create_user(
            username="foreign",
            email="foreign@example.com",
            password="Strong1pw",
            is_active=True,
        )
        other_creator = Creator.objects.create(user_id=other)
        foreign_course = Course.objects.create(
            creator_id=other_creator,
            slug="foreign-inbox",
            title="Foreign Inbox",
        )
        foreign_note = Note.objects.create(
            creator_id=other_creator,
            course_id=foreign_course,
            sharing_id=_sid(),
            title="Secret",
            is_public=False,
        )
        resp = self._call_tool(
            "get_note_by_uuid", {"uuid": str(foreign_note.uuid)}
        )
        data = resp.json()
        self.assertTrue(data["result"].get("isError", False))

    def test_restore_note_version_round_trip(self):
        note = Note.objects.create(
            creator_id=self.creator,
            course_id=self.course,
            sharing_id=_sid(),
            title="Original",
            content="v1",
        )
        version = NoteVersion.objects.create(
            note_id=note,
            creator_id=self.creator,
            title="Original",
            content="v1",
            reason="manual",
        )
        # Mutate the current state to prove restore overwrites it
        note.content = "mutated"
        note.save(update_fields=["content"])
        resp = self._call_tool(
            "restore_note_version",
            {"note_id": note.id, "version_id": version.id},
        )
        restored = self._tool_result(resp)
        self.assertEqual(restored["content"], "v1")

    # --- Course subscriptions + reorder ---

    def test_subscribe_unsubscribe_course(self):
        other_creator = Creator.objects.create(
            user_id=User.objects.create_user(
                username="pub", email="pub@example.com", password="Strong1pw",
                is_active=True,
            )
        )
        shared_course = Course.objects.create(
            creator_id=other_creator,
            slug="public-course",
            title="Public Course",
        )
        sub_resp = self._call_tool(
            "subscribe_course", {"course_id": shared_course.id}
        )
        self.assertEqual(sub_resp.status_code, 200)
        self.assertTrue(
            CourseSubscription.objects.filter(
                creator_id=self.creator,
                course_id=shared_course,
                is_active=True,
            ).exists()
        )
        unsub_resp = self._call_tool(
            "unsubscribe_course", {"course_id": shared_course.id}
        )
        result = self._tool_result(unsub_resp)
        self.assertTrue(result["unsubscribed"])
        self.assertFalse(
            CourseSubscription.objects.filter(
                creator_id=self.creator,
                course_id=shared_course,
                is_active=True,
            ).exists()
        )

    def test_reorder_courses(self):
        a = Course.objects.create(
            creator_id=self.creator, slug="a-course", title="A"
        )
        b = Course.objects.create(
            creator_id=self.creator, slug="b-course", title="B"
        )
        c = Course.objects.create(
            creator_id=self.creator, slug="c-course", title="C"
        )
        # Reverse order: c, a, b
        resp = self._call_tool(
            "reorder_courses", {"course_ids": [c.id, a.id, b.id]}
        )
        result = self._tool_result(resp)
        self.assertEqual(result["reordered"], [c.id, a.id, b.id])
        c.refresh_from_db()
        a.refresh_from_db()
        b.refresh_from_db()
        self.assertEqual(c.sort_order, 1)
        self.assertEqual(a.sort_order, 2)
        self.assertEqual(b.sort_order, 3)

    def test_list_course_notes(self):
        Note.objects.create(
            creator_id=self.creator,
            course_id=self.course,
            sharing_id=_sid(),
            title="own note",
        )
        resp = self._call_tool(
            "list_course_notes", {"course_id": self.course.id}
        )
        result = self._tool_result(resp)
        self.assertEqual(result["course_id"], self.course.id)
        self.assertEqual(len(result["notes"]), 1)

    # --- Planner event delete ---

    def test_delete_event(self):
        event = PlannerEvent.objects.create(
            creator_id=self.creator, title="Drop me"
        )
        resp = self._call_tool("delete_event", {"event_id": event.id})
        result = self._tool_result(resp)
        self.assertTrue(result["deleted"])
        self.assertFalse(PlannerEvent.objects.filter(pk=event.id).exists())

    # --- Activity ---

    def test_get_activity_and_week(self):
        Note.objects.create(
            creator_id=self.creator,
            course_id=self.course,
            sharing_id=_sid(),
            title="Recent",
        )
        resp = self._call_tool("get_activity", {"limit": 5})
        result = self._tool_result(resp)
        self.assertGreaterEqual(len(result["notes"]), 1)

        week_resp = self._call_tool("get_activity_week")
        week = self._tool_result(week_resp)
        # Week payload includes a `days` array of length 7.
        self.assertIn("days", week)
        self.assertEqual(len(week["days"]), 7)

    # --- Note sessions ---

    def test_note_session_lifecycle(self):
        note = Note.objects.create(
            creator_id=self.creator,
            course_id=self.course,
            sharing_id=_sid(),
            title="Focus note",
        )
        start_resp = self._call_tool(
            "create_note_session",
            {"note_id": note.id, "title": "Study burst"},
        )
        session = self._tool_result(start_resp)
        sid = session["id"]
        db_session = NoteActivitySession.objects.get(pk=sid)
        self.assertIsNone(db_session.ended_at)

        list_resp = self._call_tool(
            "list_note_sessions", {"note_id": note.id}
        )
        listed = self._tool_result(list_resp)
        self.assertEqual(len(listed["sessions"]), 1)

        end_resp = self._call_tool(
            "end_note_session", {"session_id": sid, "summary": "Done"}
        )
        ended = self._tool_result(end_resp)
        self.assertEqual(ended["summary"], "Done")
        db_session.refresh_from_db()
        self.assertIsNotNone(db_session.ended_at)

    # --- Calendar feeds ---

    def test_calendar_feed_crud(self):
        create_resp = self._call_tool(
            "create_calendar_feed",
            {
                "title": "My feed",
                "source_kind": "I",
                "raw_ical": "BEGIN:VCALENDAR\nEND:VCALENDAR",
            },
        )
        feed = self._tool_result(create_resp)
        self.assertEqual(feed["title"], "My feed")
        feed_id = feed["id"]

        list_resp = self._call_tool("list_calendar_feeds")
        listed = self._tool_result(list_resp)
        self.assertEqual(len(listed["feeds"]), 1)

        update_resp = self._call_tool(
            "update_calendar_feed",
            {"feed_id": feed_id, "title": "Renamed feed", "is_enabled": False},
        )
        updated = self._tool_result(update_resp)
        self.assertEqual(updated["title"], "Renamed feed")
        self.assertFalse(updated["is_enabled"])

        del_resp = self._call_tool(
            "delete_calendar_feed", {"feed_id": feed_id}
        )
        result = self._tool_result(del_resp)
        self.assertTrue(result["deleted"])
        self.assertFalse(CalendarFeed.objects.filter(pk=feed_id).exists())

    # --- Attachment delete ---

    def test_delete_attachment_on_missing_attachment_errors(self):
        # Real file uploads need multipart; exercise the not-found path only.
        note = Note.objects.create(
            creator_id=self.creator,
            course_id=self.course,
            sharing_id=_sid(),
            title="Note with no attachment",
        )
        resp = self._call_tool(
            "delete_attachment",
            {"note_id": note.id, "attachment_id": 99999},
        )
        data = resp.json()
        self.assertTrue(data["result"].get("isError", False))

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
