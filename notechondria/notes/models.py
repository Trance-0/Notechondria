import os
from django.db import models

from django.utils.translation import gettext_lazy as _
from creators.models import Creator

# Create your models here.

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
    sharing_id = models.CharField(max_length=36,unique=True,null=False)
    title = models.CharField(max_length=100, default="Untitled Ep", null=False)
    description=models.CharField(max_length=600, blank=True,null=True)
    # last_use and date_created automatically created, for these field, create one time value to timezone.now()
    date_created=models.DateTimeField(auto_now_add=True,null=False)
    last_edit=models.DateTimeField(auto_now=True,null=False)

    def __str__(self) -> str:
        return f"{self.title}, created by {self.creator_id}"

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
