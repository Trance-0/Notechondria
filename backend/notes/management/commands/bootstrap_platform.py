import json
import logging

from django.conf import settings
from django.contrib.auth.models import User
from django.core.files.base import File
from django.core.management.base import BaseCommand
from django.utils.crypto import get_random_string

from creators.utils import ensure_creator
from notes.api import split_markdown_sections
from notes.models import Course, CourseMedia, Note, NoteBlock, NoteBlockTypeChoices, NoteIndex
from notechondria.utils import generate_unique_id


logger = logging.getLogger("django")


class Command(BaseCommand):
    help = "Create env-driven admin user and seed the default sample course when the database is empty."

    def handle(self, *args, **options):
        self.bootstrap_admin()
        self.bootstrap_sample_content()

    def bootstrap_admin(self):
        username = self.getenv("DJANGO_SUPERUSER_USERNAME", "admin")
        password = self.getenv("DJANGO_SUPERUSER_PASSWORD")
        email = self.getenv("DJANGO_SUPERUSER_EMAIL", f"{username}@localhost")
        if not password:
            self.stdout.write("Skipping admin bootstrap because DJANGO_SUPERUSER_PASSWORD is not set.")
            return
        user, created = User.objects.get_or_create(
            username=username,
            defaults={"email": email, "is_staff": True, "is_superuser": True, "is_active": True},
        )
        user.email = email
        user.is_staff = True
        user.is_superuser = True
        user.is_active = True
        user.set_password(password)
        user.save()
        ensure_creator(user)
        self.stdout.write(f"{'Created' if created else 'Updated'} admin user '{username}'.")

    def bootstrap_sample_content(self):
        if Course.objects.exists() or Note.objects.exists():
            self.stdout.write("Skipping sample bootstrap because course or note data already exists.")
            return

        sample_root = self.resolve_sample_root()
        course_payload = json.loads((sample_root / "course.json").read_text(encoding="utf-8"))
        cover_path = sample_root / course_payload["cover_image"]
        code_source = self.resolve_codex_path().read_text(encoding="utf-8")
        owner = User.objects.filter(is_superuser=True).order_by("id").first()
        if owner is None:
            owner, _ = User.objects.get_or_create(
                username="sample-course-owner",
                defaults={
                    "email": "sample-course-owner@localhost",
                    "is_staff": False,
                    "is_superuser": False,
                    "is_active": True,
                },
            )
        creator = ensure_creator(owner) if owner else None
        demo_email = f"codex-{get_random_string(8).lower()}@notechondria.local"
        demo_password = get_random_string(18)
        demo_user = User.objects.create_user(
            username="CodeX",
            email=demo_email,
            password=demo_password,
            is_active=True,
        )
        demo_creator = ensure_creator(demo_user)
        self.stdout.write(
            f"Seeded demo user 'CodeX' with email '{demo_email}' and password '{demo_password}'."
        )
        logger.warning(
            "Seeded demo user CodeX credentials email=%s password=%s",
            demo_email,
            demo_password,
        )

        course_definitions = [
            {
                "creator": creator,
                "slug": course_payload["slug"],
                "title": course_payload["title"],
                "description": course_payload["description"],
                "is_default": True,
                "notes": [
                    {
                        "title": section["title"],
                        "body": section["body"],
                    }
                    for section in split_markdown_sections(code_source, fallback_title=course_payload["title"])[:5]
                ],
            },
            {
                "creator": demo_creator,
                "slug": "meaning-of-work-in-age-of-ai",
                "title": "Meaning of Work in Age of AI",
                "description": "A sample seminar course about labor, purpose, and changing human contribution in AI-shaped economies.",
                "is_default": False,
                "notes": [
                    {
                        "title": "Why work still matters",
                        "body": "Work is not only compensation. It is also rhythm, social proof, contribution, and a way to test values in public.",
                    },
                    {
                        "title": "Automation and dignity",
                        "body": "When systems automate repetitive work, the social contract has to preserve dignity, authorship, and room for meaningful choice.",
                    },
                ],
            },
            {
                "creator": demo_creator,
                "slug": "self-identity-and-expression-in-modern-arts",
                "title": "Self-identity and Expression in Modern Arts",
                "description": "A sample humanities course about identity, performance, memory, and medium in modern artistic practice.",
                "is_default": False,
                "notes": [
                    {
                        "title": "Identity as medium",
                        "body": "Modern art often turns the self into material. Biography, gesture, and costume become part of the work rather than background context.",
                    },
                    {
                        "title": "Expression and audience",
                        "body": "Expression is shaped by audience expectations. The same image can read as confession, performance, or critique depending on the frame around it.",
                    },
                ],
            },
        ]

        for definition in course_definitions:
            course = Course.objects.create(
                creator_id=definition["creator"],
                slug=definition["slug"],
                title=definition["title"],
                description=definition["description"],
                is_default=definition["is_default"],
            )
            self.attach_course_cover(course, cover_path)
            media = CourseMedia.objects.create(
                course_id=course,
                title=f"{course.title} cover",
                description=f"Preview image for {course.title}.",
                source="Seeded sample media",
            )
            if cover_path.exists():
                with cover_path.open("rb") as media_file:
                    media.image.save(cover_path.name, File(media_file), save=True)
            for note_payload in definition["notes"]:
                self.create_seed_note(
                    creator=definition["creator"],
                    course=course,
                    title=note_payload["title"],
                    body=note_payload["body"],
                )
            self.stdout.write(
                f"Seeded sample course '{course.title}' with {course.notes.count()} note(s)."
            )

    @staticmethod
    def getenv(name: str, default=None):
        import os

        return os.getenv(name, default)

    @staticmethod
    def resolve_sample_root():
        candidates = [
            settings.BASE_DIR.parent / "sample" / "vibe-coding-101",
            settings.BASE_DIR / "sample" / "vibe-coding-101",
            settings.BASE_DIR.parent.parent / "sample" / "vibe-coding-101",
        ]
        for candidate in candidates:
            if (candidate / "course.json").exists():
                return candidate
        raise FileNotFoundError(
            "Could not find sample/vibe-coding-101/course.json in expected runtime locations."
        )

    @staticmethod
    def resolve_codex_path():
        candidates = [
            settings.BASE_DIR.parent / "CODEX.md",
            settings.BASE_DIR / "CODEX.md",
            settings.BASE_DIR.parent.parent / "CODEX.md",
            settings.BASE_DIR.parent / "codex.md",
            settings.BASE_DIR / "codex.md",
            settings.BASE_DIR.parent.parent / "codex.md",
        ]
        for candidate in candidates:
            if candidate.exists():
                return candidate
        raise FileNotFoundError("Could not find CODEX.md in expected runtime locations.")

    def attach_course_cover(self, course: Course, cover_path):
        if cover_path.exists():
            with cover_path.open("rb") as cover_file:
                course.cover_image.save(cover_path.name, File(cover_file), save=True)
        else:
            logger.warning("Sample course cover not found at %s. Continuing without cover image.", cover_path)

    def create_seed_note(self, creator, course: Course, title: str, body: str):
        markdown_body = f"# {title}\n\n{body}".strip()
        note = Note.objects.create(
            creator_id=creator,
            course_id=course,
            sharing_id=generate_unique_id(Note, "sharing_id"),
            title=title,
            description=body[:240],
            content=markdown_body,
            is_public=True,
            editor_mode="G",
        )
        title_block = NoteBlock.objects.create(
            creator_id=creator,
            note_id=note,
            block_type=NoteBlockTypeChoices.TITLE,
            text=title,
            is_AI_generated=False,
        )
        body_block = NoteBlock.objects.create(
            creator_id=creator,
            note_id=note,
            block_type=NoteBlockTypeChoices.TEXT,
            text=body,
            is_AI_generated=False,
        )
        NoteIndex.objects.create(note_id=note, index=0, noteblock_id=title_block)
        NoteIndex.objects.create(note_id=note, index=1, noteblock_id=body_block)
