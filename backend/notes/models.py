import uuid

from django.db import models
from django.db.models import Q
from django.utils import timezone
from django.utils.translation import gettext_lazy as _

from creators.models import Creator

# Historic migrations (notes/migrations/0005, 0006, 0007, 0009) reference
# `notes.models.course_cover_path` / `course_media_path`. The callables
# themselves now live in `courses.models`; we re-export them here so
# those old migration files keep loading without rewriting them.
from courses.models import course_cover_path, course_media_path  # noqa: F401


class Note(models.Model):
    """
    Note is a collection of Note blocks, default order maintained by Note index.

    Sharing will be implemented in future version.
    """
    creator_id = models.ForeignKey(
        Creator,
        on_delete=models.CASCADE,
        null=False,
    )
    course_id = models.ForeignKey(
        "courses.Course",
        related_name="notes",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
    )
    uuid = models.UUIDField(default=uuid.uuid4, unique=True, editable=False)
    sharing_id = models.CharField(max_length=36, unique=True, null=False)
    title = models.CharField(max_length=100, default="Untitled Ep", null=False)
    description = models.CharField(max_length=600, blank=True, null=True)
    is_public = models.BooleanField(default=False, null=False)
    content = models.TextField(blank=True, default="")
    metadata_json = models.TextField(blank=True, default="")
    client_draft_id = models.CharField(max_length=64, blank=True, null=True)
    deleted_at = models.DateTimeField(blank=True, null=True)
    note_type = models.CharField(
        max_length=1,
        choices=(
            ("N", _("Normal")),
            ("C", _("Comment")),
        ),
        default="N",
        null=False,
    )
    source_note = models.ForeignKey(
        "self",
        related_name="comments",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        help_text="For comment notes, the note being commented on.",
    )
    editor_mode = models.CharField(
        max_length=1,
        choices=(
            ("G", _("GFM")),
            ("B", _("Blocks")),
            ("P", _("Plain Text")),
        ),
        default="P",
        null=False,
    )
    cover_image = models.ImageField(
        upload_to="user_upload/note_covers/",
        blank=True,
        null=True,
        help_text=(
            "Optional user-uploaded cover image. Shown in note view but "
            "not in the editor; the frontend renders a UUID-derived "
            "barcode placeholder when this is empty."
        ),
    )
    date_created = models.DateTimeField(auto_now_add=True, null=False)
    last_edit = models.DateTimeField(auto_now=True, null=False)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["creator_id", "client_draft_id"],
                condition=Q(client_draft_id__isnull=False),
                name="unique_note_client_draft_per_creator",
            )
        ]

    def __str__(self) -> str:
        return f"{self.title}, created by {self.creator_id}"


class RecycleBinItemTypeChoices(models.TextChoices):
    NOTE = "note", _("Note")


class RecycleBinEntry(models.Model):
    creator_id = models.ForeignKey(
        Creator,
        related_name="recycle_bin_entries",
        on_delete=models.CASCADE,
        null=False,
    )
    note_id = models.ForeignKey(
        Note,
        related_name="recycle_bin_entries",
        on_delete=models.CASCADE,
        null=False,
    )
    item_type = models.CharField(
        max_length=16,
        choices=RecycleBinItemTypeChoices.choices,
        default=RecycleBinItemTypeChoices.NOTE,
        null=False,
    )
    deleted_at = models.DateTimeField(default=timezone.now, null=False)
    metadata_json = models.TextField(blank=True, default="")
    date_created = models.DateTimeField(auto_now_add=True, null=False)
    last_edit = models.DateTimeField(auto_now=True, null=False)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["creator_id", "note_id"],
                name="unique_recycle_bin_note_per_creator",
            )
        ]
        ordering = ["-deleted_at", "-id"]

    def __str__(self) -> str:
        return f"{self.creator_id.user_id.username}:{self.item_type}:{self.note_id.title}"


class NoteVersion(models.Model):
    note_id = models.ForeignKey(
        Note,
        related_name="versions",
        on_delete=models.CASCADE,
        null=False,
    )
    creator_id = models.ForeignKey(
        Creator,
        related_name="note_versions",
        on_delete=models.CASCADE,
        null=False,
    )
    title = models.CharField(max_length=100, null=False)
    description = models.CharField(max_length=600, blank=True, null=True)
    content = models.TextField(blank=True, default="")
    metadata_json = models.TextField(blank=True, default="")
    editor_mode = models.CharField(max_length=1, default="P", null=False)
    reason = models.CharField(max_length=32, default="manual", null=False)
    date_created = models.DateTimeField(auto_now_add=True, null=False)

    class Meta:
        ordering = ["-date_created", "-id"]

    def __str__(self) -> str:
        return f"{self.note_id.title}@{self.date_created}"


class NoteActivitySession(models.Model):
    creator_id = models.ForeignKey(
        Creator,
        related_name="note_activity_sessions",
        on_delete=models.CASCADE,
        null=False,
    )
    note_id = models.ForeignKey(
        Note,
        related_name="activity_sessions",
        on_delete=models.CASCADE,
        null=False,
    )
    title = models.CharField(max_length=120, null=False)
    summary = models.CharField(max_length=255, blank=True, default="")
    started_at = models.DateTimeField(default=timezone.now, null=False)
    ended_at = models.DateTimeField(blank=True, null=True)
    date_created = models.DateTimeField(auto_now_add=True, null=False)
    last_edit = models.DateTimeField(auto_now=True, null=False)

    class Meta:
        ordering = ["-started_at", "-id"]

    def __str__(self) -> str:
        return f"{self.title}@{self.started_at}"


class NoteBlockTypeChoices(models.TextChoices):
    """NoteBlockTypeChoices, need a parser for rendering"""

    TEXT = "N", _("Normal Text")
    URL = "U", _("URL")
    TITLE = "T", _("Title")
    SUBTITLE = "S", _("Sub-title")
    EXAMPLE = "E", _("Example")
    PROOF = "P", _("Proof")
    CODE = "C", _("Code")
    QUOTE = "Q", _("Quote")
    IMAGES = "I", _("Images")
    LIST = "L", _("List")
    HTML = "H", _("HTML")


def note_file_path(instance, filename):
    """
    file will be uploaded to MEDIA_ROOT/user_<id>/<filename>
    """
    return "user_upload/user_{0}/notes/noteblock_{1}/{2}".format(instance.creator_id.user_id.id, instance.id, filename)


def note_cover_path(instance, filename):
    """Note cover image upload path. Mirrors note_attachment_path so all
    per-note media land under the same `notes/note_<id>/` folder; the
    `cover_` filename prefix keeps it distinguishable from attachments
    in storage browsers."""
    return "user_upload/user_{0}/notes/note_{1}/cover_{2}".format(
        instance.creator_id.user_id.id, instance.id, filename
    )


class NoteBlock(models.Model):
    creator_id = models.ForeignKey(
        Creator,
        on_delete=models.CASCADE,
        null=False,
    )
    note_id = models.ForeignKey(
        Note,
        on_delete=models.CASCADE,
        null=True,
    )
    block_type = models.CharField(
        max_length=1,
        choices=NoteBlockTypeChoices.choices,
        default=NoteBlockTypeChoices.TEXT,
        null=False,
    )
    image = models.ImageField(upload_to=note_file_path, blank=True, null=True)
    file = models.FileField(upload_to=note_file_path, blank=True, null=True)
    is_AI_generated = models.BooleanField(null=False)
    text = models.TextField(blank=True, null=True)
    args = models.CharField(max_length=256, null=True)
    date_created = models.DateTimeField(auto_now_add=True, null=False)
    last_edit = models.DateTimeField(auto_now=True, null=False)

    def __str__(self) -> str:
        return f'{self.text[:100] if self.text else ""}:{self.date_created}'

    def get_md_str(self) -> str:
        type = self.block_type
        if type == NoteBlockTypeChoices.TEXT:
            return self.text
        elif type == NoteBlockTypeChoices.URL:
            return f'[{self.text}]({self.args})'
        elif type == NoteBlockTypeChoices.TITLE:
            return f'# {self.text}'
        elif type == NoteBlockTypeChoices.SUBTITLE:
            return f'{self.args} {self.text}'
        elif type == NoteBlockTypeChoices.EXAMPLE:
            return f'Example:     \n{self.text}'
        elif type == NoteBlockTypeChoices.PROOF:
            return f'Proof:     \n{self.text}'
        elif type == NoteBlockTypeChoices.CODE:
            return f'```{self.args}\n{self.text}\n```'
        elif type == NoteBlockTypeChoices.QUOTE:
            quote_token = [f'> {i}\n' for i in self.text.split('\n')]
            quote_str = "".join(quote_token)
            if self.args:
                return f'{quote_str}> -- cited from: {self.args}'
            return quote_str.rstrip('\n')
        elif type == NoteBlockTypeChoices.IMAGES:
            if self.image.url != "/media/False":
                return f'![{self.text}]({self.image.url})'
            else:
                return f'![{self.text}]()'
        elif type == NoteBlockTypeChoices.LIST:
            return "* ".join(self.text.split('\n'))
        elif type == NoteBlockTypeChoices.HTML:
            return self.text
        else:
            return f'<-- Unsupported type: {type}--> {self.text}'


def note_attachment_path(instance, filename):
    return "user_upload/user_{0}/notes/note_{1}/{2}".format(
        instance.note_id.creator_id.user_id.id, instance.note_id.id, filename
    )


class NoteAttachment(models.Model):
    note_id = models.ForeignKey(
        Note,
        related_name="attachments",
        on_delete=models.CASCADE,
        null=False,
    )
    file = models.FileField(upload_to=note_attachment_path, null=False)
    original_filename = models.CharField(max_length=255, null=False)
    file_size = models.PositiveBigIntegerField(null=False)
    content_type = models.CharField(max_length=128, blank=True, default="")
    date_created = models.DateTimeField(auto_now_add=True, null=False)

    class Meta:
        ordering = ["-date_created", "-id"]

    def __str__(self) -> str:
        return f"{self.original_filename} ({self.note_id.title})"


class NoteIndex(models.Model):
    note_id = models.ForeignKey(
        Note,
        on_delete=models.CASCADE,
        null=False,
    )
    index = models.IntegerField(null=False)
    noteblock_id = models.ForeignKey(
        NoteBlock,
        on_delete=models.CASCADE,
        null=False,
    )

    def get_noteblocks(self):
        return self.objects.filter(note_id=self.note_id).order_by("index")

    def get_image(self):
        """we will implement get image for feature image only in later versions."""
        noteblocks = self.get_noteblocks()
        for block in noteblocks:
            if block.block_tye == NoteBlockTypeChoices.IMAGES:
                return block
        return None

    def is_root_handle(self):
        """return if the noteIndex is the index the source of noteblock in note"""
        return self.noteblock_id.note_id == self.note_id

    def __str__(self) -> str:
        return f"{self.note_id.title}[{self.noteblock_id}],on page {self.index}"


class Tag(models.Model):
    name = models.CharField(max_length=36, unique=True, null=False)
    is_AI_generated = models.BooleanField(null=False)
    date_created = models.DateTimeField(auto_now_add=True, null=False)
    noteblock_id = models.ForeignKey(
        NoteBlock,
        on_delete=models.CASCADE,
        null=False,
    )


class ValidationRecord(models.Model):
    noteblock_id = models.ForeignKey(
        NoteBlock,
        on_delete=models.CASCADE,
        null=False,
    )
    date_created = models.DateTimeField(auto_now_add=True, null=False)
    creator_id = models.ForeignKey(
        Creator,
        on_delete=models.CASCADE,
        null=False,
    )
