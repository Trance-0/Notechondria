import os
from django.db import models

from django.utils.translation import gettext_lazy as _
from creators.models import Creator

# Create your models here.

class Note(models.Model):
     # This objects contains the username, password, first_name, last_name, and email of member.
    creator_id = models.ForeignKey(
        Creator,
        # when conversation is deleted, whether the creator should also be deleted
        on_delete=models.CASCADE,
        null=False,
    )
    sharing_id = models.CharField(max_length=36,unique=True,null=False)
    title = models.CharField(max_length=100, default="Untitled Ep", null=False)
    description=models.CharField(max_length=600,unique=True,null=False)
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
    SUBTITLE = "S", _("Sub-title")
    # math
    EXAMPLE = "E", _("Example")
    PROOF = "P", _("Proof")
    # cs
    CODE = "C", _("Code")
    # humanities
    QUOTE = "Q", _("Quote")
    IMAGES = "I", _("IMAGES")
    FILES = "F", _("FILES")
    LIST = "L", _("List")
    # embedded elements
    HTML = "H", _("HTML")
    
def note_file_path(instance, filename):
    """ 
    file will be uploaded to MEDIA_ROOT/user_<id>/<filename>
    https://docs.djangoproject.com/en/dev/ref/models/fields/#django.db.models.FileField.upload_to

    A note block can only have one file or image, you need to validate that in form
    """
    return "user_upload/user_{0}/note/note_{1}/block_{2}/{3}".format(instance.conversation_id.creator_id.user_id.id, instance.conversation_id.id, instance.id, filename)


class NoteBlock(models.Model):
    creator_id = models.ForeignKey(
        Creator,
        # when conversation is deleted, whether the creator should also be deleted
        on_delete=models.CASCADE,
        null=False,
    )
    note_id=models.ForeignKey(
        Note,
        on_delete=models.CASCADE,
        null=True,
    )
    tags=models.ManyToManyField(Tag)
    block_type=models.CharField(
        null=False,
        max_length=1,
        choices=NoteBlockTypeChoices.choices,
        default=NoteBlockTypeChoices.TEXT,
    )
    image = models.ImageField(upload_to=note_file_path,blank=True, null=True)
    # file field is currently unsupported
    file = models.FileField(upload_to=note_file_path,blank=True, null=True)

    # validation count for this note block, plus one for each human verification.
    validation = models.IntegerField(default=0, null=False)

    is_AI_generated=models.BooleanField(null=False)
    # unlimited size for PostgreSQL, the max_length value have to be set for other databases.
    text = models.TextField(blank=True, null=True)

    # extra arguments for rendering special features
    args=models.CharField(max_length=256,unique=True,null=False)

    # last_use and date_created automatically created, for these field, create one time value to timezone.now()
    date_created=models.DateTimeField(auto_now_add=True,null=False)
    last_edit=models.DateTimeField(auto_now=True,null=False)
