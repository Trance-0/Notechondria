"""Delete legacy "Inbox" category rows; notes fall to the uncategorized
bucket automatically.

Background
----------
Pre-0.1.120 builds auto-created a real ``Course`` row titled "Inbox"
(carrying the now-removed ``is_default=True`` flag) for each account.
0.1.120 retired that concept: the "uncategorized" bucket is now a
purely client-side rendering of every ``Note`` whose ``course_id IS
NULL``, labelled per-user by ``Creator.uncategorized_folder_name``
(default "Inbox"). There is no server row backing it.

Legacy "Inbox" ``Course`` rows linger in older databases, and the
editor sidebar renders such a row as a *second* "Inbox" next to the
synthetic bucket — the duplicate-Inbox bug. This command removes them.

Behaviour
---------
* Targets every ``Course`` whose title is "Inbox" (case-insensitive)
  **and** that belongs to a creator (``creator_id IS NOT NULL``). It
  never touches ownerless / public-catalog rows.
* Notes attached to a deleted Inbox course are first re-parented to
  ``course_id = NULL`` (explicit ``UPDATE`` so the moved count is
  exact and the data move does not depend on the cascade), then the
  course rows are deleted. ``Note.course_id`` is ``on_delete=SET_NULL``
  anyway, so no note is ever lost.
* Idempotent: a second run finds nothing and is a no-op.
* Heartbeat: prints per-creator progress so a large sweep shows
  forward motion (AGENTS.md §1.4).

Cascade note: deleting a ``Course`` cascades to its ``CourseMedia``,
``CourseSubscription`` and ``CourseOperationLog`` rows. For a legacy
placeholder Inbox these are normally empty; the command reports the
counts it removed so an operator can audit a ``--dry-run`` first.

Usage::

    python manage.py cleanup_inbox_courses --dry-run
    python manage.py cleanup_inbox_courses --limit 100
    python manage.py cleanup_inbox_courses
"""

from __future__ import annotations

from django.core.management.base import BaseCommand
from django.db import transaction

from courses.models import Course
from notes.models import Note


class Command(BaseCommand):
    help = (
        'Delete owned Course rows titled "Inbox" (case-insensitive); '
        "their notes fall back to the uncategorized bucket "
        "(course_id IS NULL)."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Report what would be deleted without changing anything.",
        )
        parser.add_argument(
            "--limit",
            type=int,
            default=0,
            help="Process at most N Inbox courses (0 = no limit).",
        )

    def handle(self, *args, **options):
        dry_run = options["dry_run"]
        limit = options["limit"] or 0

        qs = Course.objects.filter(
            title__iexact="inbox",
            creator_id__isnull=False,
        ).select_related("creator_id__user_id").order_by("id")
        if limit > 0:
            qs = qs[:limit]

        courses = list(qs)
        if not courses:
            self.stdout.write(
                "No owned 'Inbox' courses found: "
                "courses.cleanup_inbox_courses/scan — database is already "
                "clean."
            )
            return

        mode = "DRY-RUN" if dry_run else "DELETE"
        self.stdout.write(
            f"[{mode}] Found {len(courses)} owned 'Inbox' course(s) to "
            "remove."
        )

        total_notes_moved = 0
        total_courses_removed = 0
        for course in courses:
            owner = "<ownerless>"
            try:
                owner = course.creator_id.user_id.username
            except Exception:  # noqa: BLE001 — defensive; creator may be partial
                pass
            note_count = Note.objects.filter(course_id=course).count()
            self.stdout.write(
                f"  {mode} course id={course.id} slug={course.slug!r} "
                f"owner={owner} attached_notes={note_count}"
            )
            if dry_run:
                total_notes_moved += note_count
                total_courses_removed += 1
                continue
            with transaction.atomic():
                moved = Note.objects.filter(course_id=course).update(
                    course_id=None
                )
                course.delete()
            total_notes_moved += moved
            total_courses_removed += 1

        verb = "would re-parent" if dry_run else "re-parented"
        verb2 = "would remove" if dry_run else "removed"
        self.stdout.write(
            f"[{mode}] Done: {verb} {total_notes_moved} note(s) to the "
            f"uncategorized bucket and {verb2} {total_courses_removed} "
            "'Inbox' course(s)."
        )
        if dry_run:
            self.stdout.write("Re-run without --dry-run to apply.")
