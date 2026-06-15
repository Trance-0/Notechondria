"""Tests for the root notechondria package — covers the tiny cross-cutting
API endpoints (`ping`, `handshake`, `health`) that have no app of their
own to host a `tests.py`. Each endpoint is small enough that one test
per behaviour is enough; the heavy lifting lives in `creators/tests.py`,
`notes/tests.py`, and `mcp/tests.py`.
"""

import json

from django.test import TestCase, Client


class PingEndpointTests(TestCase):
    """Verifies the `/api/v1/ping/` liveness endpoint the frontend
    debug-log `ping` command hits to measure backend round-trip
    latency."""

    def setUp(self):
        self.client = Client()

    def test_ping_returns_pong_true(self):
        response = self.client.get("/api/v1/ping/")
        self.assertEqual(response.status_code, 200)
        payload = json.loads(response.content)
        self.assertIs(payload.get("pong"), True)
        self.assertEqual(payload.get("service"), "notechondria-backend")
        self.assertIn("timestamp", payload)
        # Timestamp should be a non-empty string with an ISO-8601 date
        # prefix; we don't parse the full value here, just sanity-check
        # that it looks like what `timezone.now().isoformat()` returns.
        timestamp = payload["timestamp"]
        self.assertIsInstance(timestamp, str)
        self.assertGreater(len(timestamp), 10)
        self.assertEqual(timestamp[4], "-")
        self.assertEqual(timestamp[7], "-")

    def test_ping_rejects_post(self):
        # Endpoint is GET-only via `@require_GET`. A POST should get 405.
        response = self.client.post("/api/v1/ping/")
        self.assertEqual(response.status_code, 405)


class HandshakeEndpointTests(TestCase):
    """Regression coverage for `/api/v1/handshake/`, which the frontend
    calls whenever the user edits the API base URL in Settings to prove
    the candidate server is a Notechondria backend with a compatible
    API version."""

    def setUp(self):
        self.client = Client()

    def test_handshake_identifies_backend(self):
        response = self.client.get("/api/v1/handshake/")
        self.assertEqual(response.status_code, 200)
        payload = json.loads(response.content)
        self.assertEqual(payload.get("service"), "notechondria-backend")
        self.assertEqual(payload.get("api_version"), "v1")
        self.assertIn("version", payload)
        self.assertIn("capabilities", payload)
        self.assertIn("auth", payload["capabilities"])

    def test_handshake_reports_storage_backend_shape(self):
        # The ambient default depends on whether R2 env vars are set, so
        # only assert the field shape here; the branches are pinned below.
        response = self.client.get("/api/v1/handshake/")
        storage = json.loads(response.content).get("storage")
        self.assertIsInstance(storage, dict)
        self.assertIn(storage.get("backend"), {"cloudflare-r2", "local-disk"})
        self.assertIn("label", storage)

    def test_handshake_reports_local_disk_storage(self):
        from django.test import override_settings
        with override_settings(STORAGES={
            "default": {
                "BACKEND":
                    "django.core.files.storage.FileSystemStorage"},
            "staticfiles": {
                "BACKEND":
                    "whitenoise.storage.CompressedManifestStaticFilesStorage"},
        }):
            response = self.client.get("/api/v1/handshake/")
        storage = json.loads(response.content)["storage"]
        self.assertEqual(storage["backend"], "local-disk")
        self.assertEqual(storage["label"], "Local disk")

    def test_handshake_reports_r2_when_s3_storage(self):
        from django.test import override_settings
        with override_settings(STORAGES={
            "default": {
                "BACKEND": "storages.backends.s3boto3.S3Boto3Storage"},
            "staticfiles": {
                "BACKEND": "storages.backends.s3boto3.S3Boto3Storage"},
        }):
            response = self.client.get("/api/v1/handshake/")
        self.assertEqual(
            json.loads(response.content)["storage"]["backend"],
            "cloudflare-r2")


class OauthCallbackAppRoutingTests(TestCase):
    """0.1.128: `oauth_callback` routes its same-tab fallback redirect
    to the app named by the `state` suffix (`_editor` / `_planner` /
    `_portal`), defaulting to the editor for legacy states."""

    def _get(self, state):
        from django.test import RequestFactory
        from . import api_views
        request = RequestFactory().get(
            '/auth/github/callback',
            {'code': 'test-code', 'state': state},
        )
        response = api_views.oauth_callback(request, provider='github')
        self.assertEqual(response.status_code, 200)
        return response.content.decode()

    def test_planner_suffix_routes_to_planner(self):
        body = self._get('app_planner')
        self.assertIn('/Notechondria/planner/', body)
        self.assertNotIn('/Notechondria/editor/', body)

    def test_portal_suffix_routes_to_portal(self):
        body = self._get('github_portal')
        self.assertIn('/Notechondria/portal/', body)

    def test_legacy_state_defaults_to_editor(self):
        body = self._get('github')
        self.assertIn('/Notechondria/editor/', body)

    def test_editor_suffix_routes_to_editor(self):
        body = self._get('app_editor')
        self.assertIn('/Notechondria/editor/', body)
