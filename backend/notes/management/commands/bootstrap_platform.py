import json

from django.conf import settings
from django.contrib.auth.models import User
from django.core.files.base import File
from django.core.management.base import BaseCommand

from creators.utils import ensure_creator
from notes.api import split_markdown_sections
from notes.models import Course, CourseMedia, Note, NoteBlock, NoteBlockTypeChoices, NoteIndex
from notechondria.utils import generate_unique_id


class Command(BaseCommand):
    help = "Create env-driven admin user and seed the default sample course when the database is empty."

    def handle(self, *args, **options):
        self.bootstrap_admin()
        self.bootstrap_sample_course()

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

    def bootstrap_sample_course(self):
        if Course.objects.exists() or Note.objects.exists():
            self.stdout.write("Skipping sample bootstrap because course or note data already exists.")
            return

        sample_root = settings.BASE_DIR.parent / "sample" / "vibe-coding-101"
        course_payload = json.loads((sample_root / "course.json").read_text(encoding="utf-8"))
        code_source = (settings.BASE_DIR.parent / "CODEX.md").read_text(encoding="utf-8")
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

        course = Course.objects.create(
            creator_id=creator,
            slug=course_payload["slug"],
            title=course_payload["title"],
            description=course_payload["description"],
            is_default=True,
        )

        cover_path = sample_root / course_payload["cover_image"]
        with cover_path.open("rb") as cover_file:
            course.cover_image.save(cover_path.name, File(cover_file), save=True)

        for media_payload in course_payload.get("media", []):
            media = CourseMedia.objects.create(
                course_id=course,
                title=media_payload["title"],
                description=media_payload.get("description", ""),
                source=media_payload.get("source", ""),
            )
            media_path = sample_root / media_payload["path"]
            with media_path.open("rb") as media_file:
                media.image.save(media_path.name, File(media_file), save=True)

        for section in split_markdown_sections(code_source, fallback_title=course.title):
            note = Note.objects.create(
                creator_id=creator,
                course_id=course,
                sharing_id=generate_unique_id(Note, "sharing_id"),
                title=section["title"],
                description=section["body"][:240],
            )
            title_block = NoteBlock.objects.create(
                creator_id=creator,
                note_id=note,
                block_type=NoteBlockTypeChoices.TITLE,
                text=section["title"],
                is_AI_generated=False,
            )
            body_block = NoteBlock.objects.create(
                creator_id=creator,
                note_id=note,
                block_type=NoteBlockTypeChoices.TEXT,
                text=section["body"],
                is_AI_generated=False,
            )
            NoteIndex.objects.create(note_id=note, index=0, noteblock_id=title_block)
            NoteIndex.objects.create(note_id=note, index=1, noteblock_id=body_block)

        self.stdout.write(f"Seeded sample course '{course.title}' with {course.notes.count()} note(s).")

    @staticmethod
    def getenv(name: str, default=None):
        import os

        return os.getenv(name, default)
