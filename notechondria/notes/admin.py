# Register your models here.
from django.contrib import admin

# Register your models here.
from .models import Note,NoteIndex,NoteBlock,Tag,ValidationRecord

class NoteBlockInline(admin.StackedInline):
    """Line per message in admin view and one extra for convenience"""
    model=NoteBlock
    fields=["block_type","image","file","is_AI_generated","text","args"]
    # ordering=["created"]
    readonly_fields=["date_created","last_edit"]
    extra=1

class NoteAdmin(admin.ModelAdmin):
    """ in admin view and one extra for convenience"""
    model=Note
    readonly_fields=["date_created","last_edit"]
    inlines = [
        NoteBlockInline
    ]
    extra=1


# Add model to admin view
admin.site.register(Note,NoteAdmin)
admin.site.register(NoteBlock)
admin.site.register(Tag)
admin.site.register(ValidationRecord)