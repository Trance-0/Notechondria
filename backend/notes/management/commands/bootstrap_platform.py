import json
import logging
from pathlib import Path

from django.conf import settings
from django.contrib.auth.models import User
from django.core.files.base import File
from django.core.management.base import BaseCommand
from django.utils.crypto import get_random_string

from creators.utils import ensure_creator
from courses.models import Course, CourseMedia
from notes.api import split_markdown_sections
from notes.models import Note, NoteBlock, NoteBlockTypeChoices, NoteIndex
from notechondria.utils import generate_unique_id


logger = logging.getLogger("django")


class Command(BaseCommand):
    help = "Create env-driven admin user and seed the sample course catalog when the database is empty."

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
        sample_root = self.resolve_sample_base_root()
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
        demo_user, demo_created = User.objects.get_or_create(
            username="CodeX",
            defaults={
                "email": demo_email,
                "is_active": True,
            },
        )
        if demo_created:
            demo_user.set_password(demo_password)
            demo_user.save(update_fields=["password"])
            self.stdout.write(
                f"Seeded demo user 'CodeX' with email '{demo_email}' and password '{demo_password}'."
            )
            logger.warning(
                "Seeded demo user CodeX credentials email=%s password=%s",
                demo_email,
                demo_password,
            )
        else:
            if not demo_user.is_active:
                demo_user.is_active = True
                demo_user.save(update_fields=["is_active"])
            if not demo_user.email:
                demo_user.email = demo_email
                demo_user.save(update_fields=["email"])
            self.stdout.write(
                f"Reused existing demo user 'CodeX' with email '{demo_user.email}'."
            )
        demo_creator = ensure_creator(demo_user)

        course_definitions = [
            {
                "creator": creator,
                "payload": self.load_course_payload(sample_root, "vibe-coding-101"),
                "is_default": False,
                "notes": [
                    {
                        "title": section["title"],
                        "body": section["body"],
                    }
                    for section in split_markdown_sections(
                        code_source,
                        fallback_title="Vibe Coding 101",
                    )[:5]
                ],
            },
            {
                "creator": demo_creator,
                "payload": self.load_course_payload(sample_root, "meaning-of-work-in-age-of-ai"),
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
                "payload": self.load_course_payload(
                    sample_root,
                    "self-identity-and-expression-in-modern-arts",
                ),
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
            payload = definition["payload"]
            course_root = sample_root / payload["slug"]
            course, created = Course.objects.get_or_create(
                slug=payload["slug"],
                defaults={
                    "creator_id": definition["creator"],
                    "title": payload["title"],
                    "description": payload.get("description"),
                    "is_default": definition["is_default"],
                },
            )
            course.creator_id = course.creator_id or definition["creator"]
            course.title = payload["title"]
            course.description = payload.get("description")
            course.is_default = definition["is_default"]
            course.save()
            cover_image = payload.get("cover_image")
            if not course.cover_image:
                self.attach_course_cover(course, course_root / cover_image if cover_image else None)
            self.attach_course_media(course, course_root, payload)
            for note_payload in definition["notes"]:
                if not course.notes.filter(title=note_payload["title"]).exists():
                    self.create_seed_note(
                        creator=definition["creator"],
                        course=course,
                        title=note_payload["title"],
                        body=note_payload["body"],
                    )
            self.stdout.write(
                f"{'Created' if created else 'Updated'} sample course '{course.title}' with {course.notes.count()} note(s)."
            )

    @staticmethod
    def getenv(name: str, default=None):
        import os

        return os.getenv(name, default)

    @staticmethod
    def resolve_sample_base_root():
        explicit_root = Command.getenv("SAMPLE_ROOT")
        candidates = [
            Path(explicit_root) if explicit_root else None,
            Path("/home/sample"),
            settings.BASE_DIR.parent / "sample",
            settings.BASE_DIR / "sample",
            settings.BASE_DIR.parent.parent / "sample",
        ]
        for candidate in candidates:
            if candidate is None:
                continue
            if (candidate / "vibe-coding-101" / "course.json").exists():
                return candidate
        raise FileNotFoundError(
            "Could not find sample/vibe-coding-101/course.json in expected runtime locations."
        )

    @staticmethod
    def load_course_payload(sample_root, slug: str):
        course_path = sample_root / slug / "course.json"
        if not course_path.exists():
            raise FileNotFoundError(f"Could not find {course_path}.")
        return json.loads(course_path.read_text(encoding="utf-8"))

    @staticmethod
    def resolve_codex_path():
        # Candidate paths for the seed file that bootstrap_platform reads to
        # populate a starter note. Use is_file() (not exists()) because the
        # submodule now lives at `<repo>/AGENTS.md/` (a directory, same name
        # as the old file), so `<repo>/AGENTS.md` exists-as-directory but is
        # not readable with read_text(). In the Docker image the Dockerfile
        # copies `docs/index.md` to `/home/AGENTS.md` (a file), so the
        # `BASE_DIR.parent / "AGENTS.md"` candidate still resolves inside
        # containers.
        candidates = [
            settings.BASE_DIR.parent / "AGENTS.md",
            settings.BASE_DIR.parent / "CODEX.md",
            settings.BASE_DIR / "AGENTS.md",
            settings.BASE_DIR / "CODEX.md",
            settings.BASE_DIR.parent.parent / "AGENTS.md",
            settings.BASE_DIR.parent.parent / "CODEX.md",
            settings.BASE_DIR.parent.parent / "docs" / "index.md",
            settings.BASE_DIR.parent / "docs" / "index.md",
            settings.BASE_DIR.parent.parent / "AGENTS.md" / "AGENTS.md",
            settings.BASE_DIR.parent / "AGENTS.md" / "AGENTS.md",
            settings.BASE_DIR.parent / "agents.md",
            settings.BASE_DIR.parent / "codex.md",
            settings.BASE_DIR / "agents.md",
            settings.BASE_DIR / "codex.md",
            settings.BASE_DIR.parent.parent / "agents.md",
            settings.BASE_DIR.parent.parent / "codex.md",
        ]
        for candidate in candidates:
            if candidate.is_file():
                return candidate
        raise FileNotFoundError(
            "Could not find AGENTS.md, docs/index.md, AGENTS.md/AGENTS.md, "
            "or CODEX.md in expected runtime locations."
        )

    def attach_course_cover(self, course: Course, cover_path):
        resolved_cover_path = self.resolve_course_asset_path(course.slug, cover_path)
        if resolved_cover_path and resolved_cover_path.is_file():
            with resolved_cover_path.open("rb") as cover_file:
                course.cover_image.save(resolved_cover_path.name, File(cover_file), save=True)
        else:
            logger.warning(
                "Sample course cover not found at %s. Continuing without cover image.",
                cover_path,
            )

    def attach_course_media(self, course: Course, course_root, payload: dict):
        media_items = payload.get("media") or []
        if not media_items and payload.get("cover_image"):
            media_items = [
                {
                    "title": f"{course.title} cover",
                    "description": f"Preview image for {course.title}.",
                    "path": payload["cover_image"],
                    "source": "Seeded sample media",
                }
            ]

        for media_payload in media_items:
            title = media_payload.get("title") or f"{course.title} media"
            source = media_payload.get("source")
            if CourseMedia.objects.filter(course_id=course, title=title, source=source).exists():
                continue
            media = CourseMedia.objects.create(
                course_id=course,
                title=title,
                description=media_payload.get("description"),
                source=source,
            )
            media_ref = media_payload.get("path")
            media_path = course_root / media_ref if media_ref else None
            resolved_media_path = self.resolve_course_asset_path(course.slug, media_path)
            if resolved_media_path and resolved_media_path.is_file():
                with resolved_media_path.open("rb") as media_file:
                    media.image.save(resolved_media_path.name, File(media_file), save=True)
            else:
                logger.warning(
                    "Sample course media not found at %s. Continuing without image for '%s'.",
                    media_path,
                    media.title,
                )

    @staticmethod
    def resolve_course_asset_path(slug: str, candidate_path):
        if not candidate_path:
            return None
        candidate = Path(candidate_path)
        if candidate.is_file():
            return candidate

        file_name = candidate.name
        alternatives = [
            Path("/home/sample") / slug / file_name,
            Path("/home/sample") / slug / "media" / file_name,
            settings.BASE_DIR.parent / "sample" / slug / file_name,
            settings.BASE_DIR.parent / "sample" / slug / "media" / file_name,
            settings.BASE_DIR / "sample" / slug / file_name,
            settings.BASE_DIR / "sample" / slug / "media" / file_name,
            settings.BASE_DIR.parent.parent / "sample" / slug / file_name,
            settings.BASE_DIR.parent.parent / "sample" / slug / "media" / file_name,
        ]
        for alternative in alternatives:
            if alternative.is_file():
                return alternative
        return candidate

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
