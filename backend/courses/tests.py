import uuid

from django.contrib.auth.models import User
from django.core.management import call_command
from django.test import TestCase

from creators.models import Creator
from courses.models import Course
from notes.models import Note


def _sid():
    return uuid.uuid4().hex[:36]


class CleanupInboxCoursesCommandTests(TestCase):
    """Coverage for the `cleanup_inbox_courses` management command — it
    removes legacy owned 'Inbox' Course rows and re-parents their notes
    to the uncategorized bucket (course_id IS NULL)."""

    def setUp(self):
        self.user = User.objects.create_user(username="alice", password="pw")
        self.creator = Creator.objects.create(user_id=self.user)

    def _course(self, title, slug):
        return Course.objects.create(
            creator_id=self.creator, slug=slug, title=title,
        )

    def test_deletes_inbox_course_and_reparents_notes(self):
        inbox = self._course("Inbox", "alice-inbox")
        keep = self._course("Biology", "alice-bio")
        n1 = Note.objects.create(
            creator_id=self.creator, course_id=inbox,
            sharing_id=_sid(), title="In inbox",
        )
        n2 = Note.objects.create(
            creator_id=self.creator, course_id=keep,
            sharing_id=_sid(), title="In biology",
        )

        call_command("cleanup_inbox_courses")

        self.assertFalse(Course.objects.filter(pk=inbox.pk).exists())
        self.assertTrue(Course.objects.filter(pk=keep.pk).exists())
        n1.refresh_from_db()
        n2.refresh_from_db()
        # The inbox note fell to uncategorized; the biology note is intact.
        self.assertIsNone(n1.course_id)
        self.assertEqual(n2.course_id_id, keep.pk)

    def test_case_insensitive_match(self):
        for title, slug in (("inbox", "a-1"), ("INBOX", "a-2"),
                            ("InBox", "a-3")):
            self._course(title, slug)
        call_command("cleanup_inbox_courses")
        self.assertEqual(
            Course.objects.filter(title__iexact="inbox").count(), 0)

    def test_dry_run_changes_nothing(self):
        inbox = self._course("Inbox", "alice-inbox")
        note = Note.objects.create(
            creator_id=self.creator, course_id=inbox,
            sharing_id=_sid(), title="In inbox",
        )
        call_command("cleanup_inbox_courses", "--dry-run")
        self.assertTrue(Course.objects.filter(pk=inbox.pk).exists())
        note.refresh_from_db()
        self.assertEqual(note.course_id_id, inbox.pk)

    def test_idempotent(self):
        self._course("Inbox", "alice-inbox")
        call_command("cleanup_inbox_courses")
        # Second run finds nothing and does not raise.
        call_command("cleanup_inbox_courses")
        self.assertEqual(
            Course.objects.filter(title__iexact="inbox").count(), 0)

    def test_ignores_ownerless_inbox_by_default(self):
        # A row with no creator must be left alone unless opted in.
        ownerless = Course.objects.create(
            creator_id=None, slug="public-inbox", title="Inbox",
        )
        call_command("cleanup_inbox_courses")
        self.assertTrue(Course.objects.filter(pk=ownerless.pk).exists())

    def test_include_ownerless_removes_orphan_inbox(self):
        ownerless = Course.objects.create(
            creator_id=None, slug="orphan-inbox", title="Inbox",
        )
        owned = self._course("Inbox", "alice-inbox")
        call_command("cleanup_inbox_courses", "--include-ownerless")
        self.assertFalse(Course.objects.filter(pk=ownerless.pk).exists())
        self.assertFalse(Course.objects.filter(pk=owned.pk).exists())

    def test_limit_caps_deletions(self):
        for i in range(3):
            self._course("Inbox", f"alice-inbox-{i}")
        call_command("cleanup_inbox_courses", "--limit", "1")
        self.assertEqual(
            Course.objects.filter(title__iexact="inbox").count(), 2)
