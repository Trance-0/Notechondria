# Register your models here.
from django.contrib import admin

# Register your models here.
from .models import (
    Course,
    CourseMedia,
    CourseOperationLog,
    CourseSubscription,
    HeatmapActivity,
    Note,
    NoteBlock,
    NoteIndex,
    PlannerEvent,
    Tag,
    ValidationRecord,
)

class NoteBlockInline(admin.StackedInline):
    """Line per message in admin view and one extra for convenience"""
    model=NoteBlock
    fields=["creator_id","block_type","image","file","is_AI_generated","text","args"]
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
admin.site.register(Course)
admin.site.register(CourseMedia)
admin.site.register(CourseSubscription)
admin.site.register(CourseOperationLog)
admin.site.register(PlannerEvent)
admin.site.register(HeatmapActivity)
admin.site.register(NoteBlock)
admin.site.register(NoteIndex)
admin.site.register(Tag)
admin.site.register(ValidationRecord)
