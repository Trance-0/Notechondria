"""Contract recorder for the local folder backend (design 8.4, Q14).

The frontend's in-page `/api/v1` backend (local folder mode) answers with
the shapes of the hand-written fixtures in
`frontend/notechondria_shared/test/fixtures/api_v1/`. This test sends each
fixture's request to the real views and fails when a key or a JSON type
differs from the fixture. It also writes every live answer under
`backend/build/contract_responses/`, which the backend-tests workflow
uploads, so a fixture can be refreshed from CI without a local backend.

Keys starting with `_` are fixture metadata. `_setup` names the seed data,
`_backend_route: false` marks a route the backend does not have (Q17), and
`{course_id}`, `{note_id}`, `{note_uuid}` in a request are replaced with
the seeded ids (plus `{attachment_id}`, `{version_id}`, `{session_id}` for
the setups that add one). A request with `files` (field -> filename,
content_type, base64) is sent as multipart together with its `fields`.
"""

import base64
import json
from pathlib import Path

from django.conf import settings
from django.contrib.auth.models import User
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

from courses.models import Course
from creators.models import Creator
from notes.models import Note

BACKEND_DIR = Path(settings.BASE_DIR)
FIXTURE_DIR = (
    BACKEND_DIR.parent / "frontend" / "notechondria_shared" / "test" / "fixtures" / "api_v1"
)
RESPONSE_DIR = BACKEND_DIR / "build" / "contract_responses"


def _substitute(value, ids):
    if isinstance(value, str):
        for key, replacement in ids.items():
            if value == "{%s}" % key:
                return replacement
            value = value.replace("{%s}" % key, str(replacement))
        return value
    if isinstance(value, list):
        return [_substitute(item, ids) for item in value]
    if isinstance(value, dict):
        return {key: _substitute(item, ids) for key, item in value.items()}
    return value


# A 1x1 PNG, so image fields (avatar, cover) accept the upload.
PNG_1X1 = (
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
)


def _upload(spec):
    return SimpleUploadedFile(
        spec["filename"],
        base64.b64decode(spec["base64"]),
        content_type=spec.get("content_type") or "application/octet-stream",
    )


def shape_errors(live, fixture, at):
    """Key and JSON-type differences; null on either side is compatible,
    and list elements are compared when both lists are non-empty."""
    if fixture is None or live is None:
        return []
    if isinstance(fixture, dict):
        if not isinstance(live, dict):
            return [f"{at}: expected an object, got {type(live).__name__}"]
        keys = {key for key in fixture if not key.startswith("_")}
        errors = []
        if set(live) != keys:
            errors.append(
                f"{at}: keys differ, missing {sorted(keys - set(live))}, "
                f"extra {sorted(set(live) - keys)}"
            )
        for key in sorted(keys & set(live)):
            errors += shape_errors(live[key], fixture[key], f"{at}.{key}")
        return errors
    if isinstance(fixture, list):
        if not isinstance(live, list):
            return [f"{at}: expected a list, got {type(live).__name__}"]
        if fixture and live:
            return shape_errors(live[0], fixture[0], f"{at}[0]")
        return []
    if isinstance(fixture, bool):
        return [] if isinstance(live, bool) else [f"{at}: expected a boolean"]
    if isinstance(fixture, int):
        ok = isinstance(live, int) and not isinstance(live, bool)
        return [] if ok else [f"{at}: expected an integer"]
    if isinstance(fixture, str):
        return [] if isinstance(live, str) else [f"{at}: expected a string"]
    return []


class ApiContractFixtureTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username="contract", email="contract@example.com", password="pw"
        )
        Creator.objects.create(user_id=self.user)
        token = Token.objects.create(user=self.user)
        self.api = APIClient()
        self.api.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def _seed(self, setup):
        if setup == "empty":
            return {}
        course = self.api.post(
            "/api/v1/courses/", {"title": "Contract course"}, format="json"
        ).json()
        note = self.api.post(
            "/api/v1/notes/",
            {
                "title": "Contract note",
                "content": "# Contract note\n\nBody",
                "course_id": course["id"],
            },
            format="json",
        ).json()
        if setup == "trashed_note":
            self.api.delete(f"/api/v1/notes/{note['id']}/")
        ids = {"course_id": course["id"], "note_id": note["id"], "note_uuid": note["uuid"]}
        if setup == "note_with_attachment":
            attachment = self.api.post(
                f"/api/v1/notes/{note['id']}/attachments/",
                {"file": _upload({"filename": "contract.png", "content_type": "image/png",
                                  "base64": PNG_1X1})},
                format="multipart",
            ).json()
            ids["attachment_id"] = attachment["id"]
        elif setup == "note_with_snapshot":
            version = self.api.post(
                f"/api/v1/notes/{note['id']}/snapshot/", {"reason": "manual"}, format="json"
            ).json()
            ids["version_id"] = version["id"]
        elif setup == "note_with_session":
            session = self.api.post(
                "/api/v1/note-sessions/", {"note_id": note["id"]}, format="json"
            ).json()
            ids["session_id"] = session["id"]
        return ids

    def test_fixtures_match_live_responses(self):
        fixtures = sorted(FIXTURE_DIR.glob("*.json"))
        self.assertTrue(fixtures, f"no fixtures in {FIXTURE_DIR}")
        RESPONSE_DIR.mkdir(parents=True, exist_ok=True)
        for path in fixtures:
            fixture = json.loads(path.read_text(encoding="utf-8"))
            if fixture.get("_backend_route") is False:
                continue
            with self.subTest(fixture=path.name):
                ids = self._seed(fixture.get("_setup", "empty"))
                request = fixture["request"]
                method = request["method"].lower()
                url = _substitute(request["path"], ids)
                body = _substitute(request.get("body"), ids)
                call = getattr(self.api, method)
                if request.get("files"):
                    data = dict(_substitute(request.get("fields") or {}, ids))
                    for field, spec in request["files"].items():
                        data[field] = _upload(spec)
                    response = call(url, data, format="multipart")
                elif body is not None:
                    response = call(url, body, format="json")
                else:
                    response = call(url)
                live = response.json() if response.content else None
                (RESPONSE_DIR / path.name).write_text(
                    json.dumps(
                        {"status": response.status_code, "body": live},
                        indent=2,
                        sort_keys=True,
                    ),
                    encoding="utf-8",
                )
                self.assertEqual(response.status_code, fixture["status"], response.content[:500])
                errors = shape_errors(live, fixture["body"], path.name)
                self.assertEqual(errors, [], "\n".join(errors))
            # Each fixture starts without courses or notes.
            Note.objects.all().delete()
            Course.objects.all().delete()
