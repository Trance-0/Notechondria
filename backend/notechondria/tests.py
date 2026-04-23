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
