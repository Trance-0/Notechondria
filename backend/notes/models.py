import os
from django.db import models
from django.db.models import Q
from django.utils import timezone

from django.utils.translation import gettext_lazy as _
from creators.models import Creator

# Create your models here.


def course_media_path(instance, filename):
    return f"course_media/course_{instance.course_id_id}/{filename}"


def course_cover_path(instance, filename):
    return f"course_media/course_{instance.id or 'new'}/{filename}"


class Course(models.Model):
    creator_id = models.ForeignKey(
        Creator,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
    )
    client_course_id = models.CharField(max_length=64, blank=True, null=True)
    slug = models.SlugField(max_length=120, unique=True)
    title = models.CharField(max_length=120, null=False)
    description = models.TextField(blank=True, null=True)
    cover_image = models.ImageField(upload_to=course_cover_path, blank=True, null=True)
    is_default = models.BooleanField(default=False, null=False)
    # Explicit sort order for sidebar rendering. Defaults to 0; the reorder
    # endpoint rewrites this to match the client-supplied ordering so users
    # can drag categories into their preferred arrangement.
    sort_order = models.IntegerField(default=0, null=False)
    date_created = models.DateTimeField(auto_now_add=True, null=False)
    last_edit = models.DateTimeField(auto_now=True, null=False)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["creator_id", "client_course_id"],
                condition=Q(client_course_id__isnull=False),
                name="unique_course_client_id_per_creator",
            )
        ]
        ordering = ["sort_order", "title"]

    def __str__(self) -> str:
        return self.title


class CourseMedia(models.Model):
    course_id = models.ForeignKey(
        Course,
        related_name="media_items",
        on_delete=models.CASCADE,
        null=False,
    )
    title = models.CharField(max_length=120, null=False)
    description = models.CharField(max_length=255, blank=True, null=True)
    image = models.ImageField(upload_to=course_media_path, blank=True, null=True)
    source = models.CharField(max_length=255, blank=True, null=True)
    date_created = models.DateTimeField(auto_now_add=True, null=False)

    class Meta:
        ordering = ["date_created", "id"]

    def __str__(self) -> str:
        return f"{self.course_id.title}: {self.title}"


class CourseSubscription(models.Model):
    creator_id = models.ForeignKey(
        Creator,
        related_name="course_subscriptions",
        on_delete=models.CASCADE,
        null=False,
    )
    course_id = models.ForeignKey(
        Course,
        related_name="subscriptions",
        on_delete=models.CASCADE,
        null=False,
    )
    is_active = models.BooleanField(default=True, null=False)
    subscribed_at = models.DateTimeField(default=timezone.now, null=False)
    last_opened_at = models.DateTimeField(blank=True, null=True)
    date_created = models.DateTimeField(auto_now_add=True, null=False)
    last_edit = models.DateTimeField(auto_now=True, null=False)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["creator_id", "course_id"],
                name="unique_course_subscription_per_creator",
            )
        ]
        ordering = ["-last_opened_at", "-subscribed_at", "-id"]

    def __str__(self) -> str:
        return f"{self.creator_id.user_id.username}:{self.course_id.title}"


class CourseOperationTypeChoices(models.TextChoices):
    SUBSCRIBE = "subscribe", _("Subscribe")
    UNSUBSCRIBE = "unsubscribe", _("Unsubscribe")
    OPEN = "open", _("Open")


class CourseOperationLog(models.Model):
    creator_id = models.ForeignKey(
        Creator,
        related_name="course_operation_logs",
        on_delete=models.CASCADE,
        null=False,
    )
    course_id = models.ForeignKey(
        Course,
        related_name="operation_logs",
        on_delete=models.CASCADE,
        null=False,
    )
    operation_type = models.CharField(
        max_length=16,
        choices=CourseOperationTypeChoices.choices,
        null=False,
    )
    metadata_json = models.TextField(blank=True, default="")
    occurred_at = models.DateTimeField(default=timezone.now, null=False)
    date_created = models.DateTimeField(auto_now_add=True, null=False)

    class Meta:
        ordering = ["-occurred_at", "-id"]

    def __str__(self) -> str:
        return f"{self.creator_id.user_id.username}:{self.course_id.title}:{self.operation_type}"


class PlannerEvent(models.Model):
    creator_id = models.ForeignKey(
        Creator,
        related_name="planner_events",
        on_delete=models.CASCADE,
        null=False,
    )
    course_id = models.ForeignKey(
        Course,
        related_name="planner_events",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
    )
    title = models.CharField(max_length=120, null=False)
    event_date = models.DateField(null=False, default=timezone.localdate)
    starts_at = models.DateTimeField(blank=True, null=True)
    ends_at = models.DateTimeField(blank=True, null=True)
    difficulty_weight = models.PositiveIntegerField(default=1, null=False)
    description = models.CharField(max_length=255, blank=True, null=True)
    is_completed = models.BooleanField(default=False, null=False)
    completed_at = models.DateTimeField(blank=True, null=True)
    date_created = models.DateTimeField(auto_now_add=True, null=False)
    last_edit = models.DateTimeField(auto_now=True, null=False)

    class Meta:
        ordering = ["event_date", "title", "id"]

    def __str__(self) -> str:
        return f"{self.title}@{self.event_date}"


class HeatmapActivityTypeChoices(models.TextChoices):
    CREATED = "C", _("Created")
    EDITED = "E", _("Edited")


class HeatmapActivity(models.Model):
    creator_id = models.ForeignKey(
        Creator,
        related_name="heatmap_activities",
        on_delete=models.CASCADE,
        null=False,
    )
    course_id = models.ForeignKey(
        Course,
        related_name="heatmap_activities",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
    )
    note_id = models.ForeignKey(
        "Note",
        related_name="heatmap_activities",
        on_delete=models.CASCADE,
        null=False,
    )
    activity_type = models.CharField(
        max_length=1,
        choices=HeatmapActivityTypeChoices.choices,
        default=HeatmapActivityTypeChoices.EDITED,
        null=False,
    )
    activity_date = models.DateField(default=timezone.localdate, null=False)
    word_count = models.PositiveIntegerField(default=0, null=False)
    date_created = models.DateTimeField(auto_now_add=True, null=False)

    class Meta:
        ordering = ["activity_date", "id"]

    def __str__(self) -> str:
        return f"{self.note_id.title}:{self.activity_date}:{self.word_count}"

class Note(models.Model):
    """
    Note is a collection of Note blocks, default order maintained by Note index. 

    Sharing will be implemented in future version.
    """
    # This objects contains the username, password, first_name, last_name, and email of member.
    creator_id = models.ForeignKey(
        Creator,
        # when conversation is deleted, whether the creator should also be deleted
        on_delete=models.CASCADE,
        null=False,
    )
    course_id = models.ForeignKey(
        Course,
        related_name="notes",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
    )
    sharing_id = models.CharField(max_length=36,unique=True,null=False)
    title = models.CharField(max_length=100, default="Untitled Ep", null=False)
    description=models.CharField(max_length=600, blank=True,null=True)
    is_public = models.BooleanField(default=False, null=False)
    content = models.TextField(blank=True, default="")
    metadata_json = models.TextField(blank=True, default="")
    client_draft_id = models.CharField(max_length=64, blank=True, null=True)
    deleted_at = models.DateTimeField(blank=True, null=True)
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
    # last_use and date_created automatically created, for these field, create one time value to timezone.now()
    date_created=models.DateTimeField(auto_now_add=True,null=False)
    last_edit=models.DateTimeField(auto_now=True,null=False)

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


class CalendarFeed(models.Model):
    creator_id = models.ForeignKey(
        Creator,
        related_name="calendar_feeds",
        on_delete=models.CASCADE,
        null=False,
    )
    course_id = models.ForeignKey(
        Course,
        related_name="calendar_feeds",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
    )
    title = models.CharField(max_length=120, null=False)
    source_kind = models.CharField(
        max_length=1,
        choices=(
            ("I", _("Imported iCal")),
            ("S", _("Subscribed iCal")),
        ),
        default="I",
        null=False,
    )
    source_url = models.URLField(blank=True, null=True)
    raw_ical = models.TextField(blank=True, default="")
    is_enabled = models.BooleanField(default=True, null=False)
    last_sync = models.DateTimeField(blank=True, null=True)
    date_created = models.DateTimeField(auto_now_add=True, null=False)
    last_edit = models.DateTimeField(auto_now=True, null=False)

    class Meta:
        ordering = ["title", "id"]

    def __str__(self) -> str:
        return self.title


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
    # math
    EXAMPLE = "E", _("Example")
    PROOF = "P", _("Proof")
    # cs
    CODE = "C", _("Code")
    # humanities
    QUOTE = "Q", _("Quote")
    IMAGES = "I", _("Images")
    # FILES = "F", _("Files")
    LIST = "L", _("List")
    # embedded elements
    HTML = "H", _("HTML")
    
def note_file_path(instance, filename):
    """ 
    file will be uploaded to MEDIA_ROOT/user_<id>/<filename>
    https://docs.djangoproject.com/en/dev/ref/models/fields/#django.db.models.FileField.upload_to

    A note block can only have one file or image, you need to validate that in form
    """
    return "user_upload/user_{0}/notes/noteblock_{1}/{2}".format(instance.creator_id.user_id.id, instance.id, filename)


class NoteBlock(models.Model):
    creator_id = models.ForeignKey(
        Creator,
        # when conversation is deleted, whether the creator should also be deleted
        on_delete=models.CASCADE,
        null=False,
    )
    # the note_id should only be assigned once to reference the first note the note block is in.
    note_id=models.ForeignKey(
        Note,
        on_delete=models.CASCADE,
        null=True,
    )
    # tag feature moved to tag model.
    # tags=models.ManyToManyField(Tag)
    block_type=models.CharField(
        max_length=1,
        choices=NoteBlockTypeChoices.choices,
        default=NoteBlockTypeChoices.TEXT,
        null=False
    )
    image = models.ImageField(upload_to=note_file_path, blank=True, null=True)
    # file field is currently unsupported
    file = models.FileField(upload_to=note_file_path, blank=True, null=True)

    is_AI_generated=models.BooleanField(null=False)
    # unlimited size for PostgreSQL, the max_length value have to be set for other databases.
    text = models.TextField(blank=True, null=True)

    # extra arguments for rendering special features like feature image or coding language
    args=models.CharField(max_length=256,null=True)

    # last_use and date_created automatically created, for these field, create one time value to timezone.now()
    date_created=models.DateTimeField(auto_now_add=True,null=False)
    last_edit=models.DateTimeField(auto_now=True,null=False)

    def __str__(self) -> str:
        return f'{self.text[:100] if self.text else ""}:{self.date_created}'
    
    def get_md_str(self) ->str:
        type=self.block_type
        if type==NoteBlockTypeChoices.TEXT:
            return self.text
        elif type==NoteBlockTypeChoices.URL:
            return f'[{self.text}]({self.args})'
        elif type==NoteBlockTypeChoices.TITLE:
            return f'# {self.text}'
        elif type==NoteBlockTypeChoices.SUBTITLE:
            return f'{self.args} {self.text}'
        elif type==NoteBlockTypeChoices.EXAMPLE:
            return f'Example:     \n{self.text}'
        elif type==NoteBlockTypeChoices.PROOF:
            return f'Proof:     \n{self.text}'
        elif type==NoteBlockTypeChoices.CODE:
            return f'```{self.args}\n{self.text}\n```'
        elif type==NoteBlockTypeChoices.QUOTE:
            quote_token=[ f'> {i}\n' for i in self.text.split('\n')]
            quote_str="".join(quote_token)
            if self.args:
                return f'{quote_str}> -- cited from: {self.args}'
            return quote_str.rstrip('\n')
        elif type==NoteBlockTypeChoices.IMAGES:
            if self.image.url!="/media/False":
                return f'![{self.text}]({self.image.url})'
            else:
                return f'![{self.text}]()'
        # elif type==NoteBlockTypeChoices.FILES:
        #     return f'[{self.text}]({self.file.url})'
        elif type==NoteBlockTypeChoices.LIST:
            return "* ".join(self.text.split('\n'))
        elif type==NoteBlockTypeChoices.HTML:
            return self.text
        else:
            return f'<-- Unsupported type: {type}--> {self.text}'

class NoteIndex(models.Model):
    note_id = models.ForeignKey(
        Note,
        # when conversation is deleted, whether the creator should also be deleted
        on_delete=models.CASCADE,
        null=False,
    )
    index=models.IntegerField(null=False)
    noteblock_id = models.ForeignKey(
        NoteBlock,
        # when conversation is deleted, whether the creator should also be deleted
        on_delete=models.CASCADE,
        null=False,
    )
    
    def get_noteblocks(self):
        return self.objects.filter(note_id=self.note_id).order_by("index")

    def get_image(self):
        """ we will implement get image for feature image only in later versions."""
        noteblocks=self.get_noteblocks()
        for block in noteblocks:
            if block.block_tye==NoteBlockTypeChoices.IMAGES:
                return block
        return None
    
    def is_root_handle(self):
        """ return if the noteIndex is the index the source of noteblock in note"""
        return self.noteblock_id.note_id==self.note_id
    
    def __str__(self)->str:
        return f"{self.note_id.title}[{self.noteblock_id}],on page {self.index}"

class Tag(models.Model):
    name=models.CharField(max_length=36,unique=True,null=False)
    is_AI_generated=models.BooleanField(null=False)    
    # last_use and date_created automatically created, for these field, create one time value to timezone.now()
    date_created=models.DateTimeField(auto_now_add=True,null=False)
    noteblock_id = models.ForeignKey(
        NoteBlock,
        # when conversation is deleted, whether the creator should also be deleted
        on_delete=models.CASCADE,
        null=False,
    )

class ValidationRecord(models.Model):
    noteblock_id= models.ForeignKey(
        NoteBlock,
        # when conversation is deleted, whether the creator should also be deleted
        on_delete=models.CASCADE,
        null=False,
    )    
    # last_use and date_created automatically created, for these field, create one time value to timezone.now()
    date_created=models.DateTimeField(auto_now_add=True,null=False)
    creator_id = models.ForeignKey(
        Creator,
        # when conversation is deleted, whether the creator should also be deleted
        on_delete=models.CASCADE,
        null=False,
    )
