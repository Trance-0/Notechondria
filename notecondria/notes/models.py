from django.db import models

from django.utils.translation import gettext_lazy as _
from creators.models import Creator

# Create your models here.

class Note(models.Model):
     # This objects contains the username, password, first_name, last_name, and email of member.
    creator_id = models.ForeignKey(
        Creator,
        # when conversation is deleteted, wheather the creator should also be deleted
        on_delete=models.CASCADE,
        null=False,
    )
    sharing_id = models.CharField(max_length=36,unique=True,null=False)
    title = models.CharField(max_length=100, null=True)

    # last_use and date_created automatically created, for these field, create one time value to timezone.now()
    date_created=models.DateTimeField(auto_now_add=True,null=False)
    last_edit=models.DateTimeField(auto_now=True,null=False)

class Tag(models.Model):
    name=models.CharField(max_length=36,unique=True,null=False)
    is_AI_generated=models.BooleanField(null=False)

class NoteBlockTypeChoices(models.TextChoices):
    """NoteBlockTypeChoices, need a parser for rendering"""

    TEXT = "N", _("Normal Text")
    URL = "U", _("URL")
    TITLE = "T", _("Title")
    SUBTITLE = "S", _("Sub title")
    CODE = "C", _("Code")
    QUOTE = "Q", _("Quote")
    PICTURE = "P", _("Picture")
    LIST = "L", _("List")
    HTML = "H", _("HTML")

class NoteBlock(models.Model):
    creator_id = models.ForeignKey(
        Creator,
        # when conversation is deleteted, wheather the creator should also be deleted
        on_delete=models.CASCADE,
        null=False,
    )
    note_id=models.ForeignKey(
        Note,
        on_delete=models.CASCADE,
    )
    tags=models.ManyToManyField(Tag)
    block_type=models.CharField(
        null=False,
        max_length=1,
        choices=NoteBlockTypeChoices.choices,
        default=NoteBlockTypeChoices.TEXT,
    )

    is_AI_generated=models.BooleanField(null=False)
    content=models.CharField(max_length=2048,unique=True,null=False)
    # extra arguments for rendering spectial features
    args=models.CharField(max_length=256,unique=True,null=False)

    # last_use and date_created automatically created, for these field, create one time value to timezone.now()
    date_created=models.DateTimeField(auto_now_add=True,null=False)
    last_edit=models.DateTimeField(auto_now=True,null=False)
