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


class CourseRepoAdapterTests(TestCase):
    """The course-repo adapter maps a docs repo onto a course structure
    without restructuring it (courses/course_repo.py)."""

    def _vitepress_files(self):
        return {
            "docs/.vitepress/config.mts": "export default {}",  # framework code
            "docs/.vitepress/sidebars/cv.ts": "export default []",
            ".github/workflows/deploy.yml": "jobs: {}",  # CI
            "README.md": "# Repo readme",  # outside content root
            "docs/cv/index.md": "---\ntitle: Computer Vision\nsidebar_position: 1\n---\n# CV\nintro",
            "docs/cv/foundations/features.md": "# Feature Detection\nbody",
            "docs/cv/foundations/filters.md": "---\nsidebar_position: 2\n---\n# Filters\nb",
            "docs/dnn/basics/mlp.md": "# MLP\nbody",
            "docs/about.md": "# About\ntop-level",
            "docs/guide.mdx": "# MDX guide",  # skipped in v1
        }

    def test_infers_vitepress_and_ignores_framework_files(self):
        from courses.course_repo import load_course_config, parse_course_repo

        files = self._vitepress_files()
        config = load_course_config(
            None, repo_name="colorful-numbers/Veronica-7", paths=list(files)
        )
        self.assertEqual(config["preset"], "vitepress")
        self.assertEqual(config["content"]["root"], "docs")
        self.assertEqual(config["course"]["slug"], "veronica-7")
        result = parse_course_repo(files, config)
        seen = {n["path"] for m in result["modules"] for n in m["notes"]}
        # Content markdown is picked up; framework/CI/out-of-root files are not.
        self.assertIn("docs/cv/index.md", seen)
        self.assertNotIn("docs/.vitepress/config.mts", seen)
        self.assertNotIn(".github/workflows/deploy.yml", seen)
        self.assertNotIn("README.md", seen)
        # MDX is skipped with a warning (deferred to a later version).
        self.assertNotIn("docs/guide.mdx", seen)
        self.assertTrue(any("MDX" in w for w in result["warnings"]))

    def test_groups_modules_and_titles_and_orders(self):
        from courses.course_repo import load_course_config, parse_course_repo

        files = self._vitepress_files()
        config = load_course_config(None, repo_name="Veronica-7", paths=list(files))
        result = parse_course_repo(files, config)
        modules = {m["key"]: m for m in result["modules"]}
        # cv module titled from its index note's frontmatter.
        self.assertEqual(modules["cv"]["title"], "Computer Vision")
        # Within cv: index first, then sidebar_position 2, then unordered.
        cv_titles = [n["title"] for n in modules["cv"]["notes"]]
        self.assertEqual(cv_titles[0], "Computer Vision")
        self.assertEqual(cv_titles[1], "Filters")
        self.assertEqual(cv_titles[2], "Feature Detection")
        self.assertEqual(result["note_count"], 5)

    def test_explicit_config_overrides_preset(self):
        from courses.course_repo import load_course_config, parse_course_repo

        files = {
            "content/intro.md": "# Intro",
            "content/unit1/lesson.md": "# Lesson",
            "src/app.ts": "code",
        }
        cfg_text = (
            "version: 1\n"
            "preset: custom\n"
            "course:\n  title: My Class\n"
            "content:\n  root: content\n  module_depth: 1\n"
        )
        config = load_course_config(cfg_text, repo_name="x/y", paths=list(files))
        self.assertEqual(config["course"]["title"], "My Class")
        result = parse_course_repo(files, config)
        seen = {n["path"] for m in result["modules"] for n in m["notes"]}
        self.assertEqual(seen, {"content/intro.md", "content/unit1/lesson.md"})
