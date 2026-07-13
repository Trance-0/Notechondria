import posixpath
from collections import defaultdict

from django.db import migrations, models
from django.db.models import Q
from django.utils.text import slugify


def _base_for(note):
    """Slug base for a note: git_path basename (index/readme → folder) or
    the title."""
    git_path = note.git_path
    if git_path:
        stem = posixpath.splitext(posixpath.basename(git_path))[0]
        if stem.lower() in ("index", "readme"):
            parent = posixpath.basename(posixpath.dirname(git_path))
            stem = parent or stem
        base = slugify(stem)
        if base:
            return base[:150]
    return (slugify(note.title) or "note")[:150]


def backfill_names(apps, schema_editor):
    Note = apps.get_model("notes", "Note")
    used = defaultdict(set)  # course id -> {names already taken}
    # Seed with any names that somehow already exist.
    for note in (
        Note.objects.filter(course_id__isnull=False)
        .exclude(name="")
        .only("id", "course_id", "name")
        .iterator()
    ):
        used[note.course_id_id].add(note.name)
    # Assign names deterministically (by id) so re-runs are stable.
    for note in (
        Note.objects.filter(course_id__isnull=False, name="")
        .order_by("course_id_id", "id")
        .iterator()
    ):
        base = _base_for(note)
        taken = used[note.course_id_id]
        candidate = base
        counter = 2
        while candidate in taken:
            suffix = f"-{counter}"
            candidate = f"{base[:150 - len(suffix)]}{suffix}"
            counter += 1
        note.name = candidate
        taken.add(candidate)
        note.save(update_fields=["name"])


def noop_reverse(apps, schema_editor):
    pass


class Migration(migrations.Migration):

    dependencies = [
        ("notes", "0019_note_git_path"),
    ]

    operations = [
        migrations.AddField(
            model_name="note",
            name="name",
            field=models.SlugField(blank=True, default="", max_length=160),
        ),
        migrations.RunPython(backfill_names, noop_reverse),
        migrations.AddConstraint(
            model_name="note",
            constraint=models.UniqueConstraint(
                fields=["course_id", "name"],
                condition=Q(course_id__isnull=False) & ~Q(name=""),
                name="unique_note_name_per_course",
            ),
        ),
    ]
