# Legacy "Inbox" category cleanup

Removes pre-0.1.120 "Inbox" `Course` rows that older builds
auto-created. The uncategorized bucket (notes with `course_id IS NULL`,
labelled by `Creator.uncategorized_folder_name`) is a client-side
render with no backing row; a real "Inbox" category is always a
leftover and shows as a duplicate "Inbox" in the editor sidebar.

See [`versions/0.1.131.md`](../versions/0.1.131.md) for the full
root-cause writeup.

## What the command does

`backend/courses/management/commands/cleanup_inbox_courses.py`:

- Targets every `Course` titled "Inbox" (case-insensitive) with a
  non-null `creator_id`. Ownerless / public-catalog rows are never
  touched.
- Re-parents each course's notes to `course_id = NULL` (so they land
  in the uncategorized bucket — no note is lost; `Note.course_id` is
  `on_delete=SET_NULL`), then deletes the course.
- Cascade: deleting a `Course` also removes its `CourseMedia`,
  `CourseSubscription`, and `CourseOperationLog` rows. For a legacy
  placeholder Inbox these are normally empty — audit with `--dry-run`
  first if unsure.
- Idempotent: a second run finds nothing.

## Usage

```bash
# From backend/ with the Django env active (DJANGO_SETTINGS_MODULE set):
python manage.py cleanup_inbox_courses --dry-run    # report only, no changes
python manage.py cleanup_inbox_courses --limit 100  # process at most 100
python manage.py cleanup_inbox_courses              # full sweep
```

Output reports the number of notes re-parented and courses removed.

## When to run

- Once per deployment that predates 0.1.120, after deploying >= 0.1.131.
- Safe to re-run anytime; it is a no-op once the rows are gone.

## Relationship to the frontend

The editor also auto-merges a signed-in user's own legacy Inbox on
next load (`_autoMigrateLegacyInbox`), but that only covers users who
sign in. This command is the authoritative server-side sweep and the
recommended way to clean the whole database in one pass.
