from django.contrib import admin

from .models import (
    Course,
    CourseMedia,
    CourseOperationLog,
    CourseSubscription,
    HeatmapActivity,
    Note,
    NoteBlock,
    NoteIndex,
    NoteVersion,
    NoteActivitySession,
    PlannerEvent,
    RecycleBinEntry,
    Tag,
    ValidationRecord,
)


# ---- Inlines ----------------------------------------------------------------

class NoteBlockInline(admin.StackedInline):
    model = NoteBlock
    fields = ("creator_id", "block_type", "image", "file", "is_AI_generated", "text", "args")
    readonly_fields = ("date_created", "last_edit")
    extra = 0


class NoteVersionInline(admin.TabularInline):
    model = NoteVersion
    fields = ("title", "reason", "editor_mode", "date_created")
    readonly_fields = ("title", "reason", "editor_mode", "date_created")
    extra = 0
    show_change_link = True


class CourseMediaInline(admin.TabularInline):
    model = CourseMedia
    fields = ("title", "description", "image", "source", "date_created")
    readonly_fields = ("date_created",)
    extra = 0


# ---- Notes -------------------------------------------------------------------

@admin.register(Note)
class NoteAdmin(admin.ModelAdmin):
    list_display = ("title", "owner_name", "course_title", "note_type", "is_public", "parent_note", "last_edit", "date_created")
    list_filter = ("note_type", "is_public", "editor_mode")
    search_fields = ("title", "description", "creator_id__user_id__username", "creator_id__user_id__first_name")
    readonly_fields = ("date_created", "last_edit", "uuid", "sharing_id")
    inlines = [NoteBlockInline, NoteVersionInline]

    @admin.display(description="Owner", ordering="creator_id__user_id__first_name")
    def owner_name(self, obj):
        if not obj.creator_id:
            return "-"
        name = obj.creator_id.user_id.get_full_name()
        return name if name.strip() else obj.creator_id.user_id.username

    @admin.display(description="Course", ordering="course_id__title")
    def course_title(self, obj):
        return obj.course_id.title if obj.course_id else "-"

    @admin.display(description="Parent note")
    def parent_note(self, obj):
        return obj.source_note.title if obj.source_note else "-"


@admin.register(NoteBlock)
class NoteBlockAdmin(admin.ModelAdmin):
    list_display = ("text_short", "owner_name", "note_title", "block_type", "is_AI_generated", "date_created")
    list_filter = ("block_type", "is_AI_generated")
    search_fields = ("text", "note_id__title", "creator_id__user_id__username")
    readonly_fields = ("date_created", "last_edit")

    @admin.display(description="Text (preview)")
    def text_short(self, obj):
        return (obj.text[:80] + "...") if obj.text and len(obj.text) > 80 else (obj.text or "-")

    @admin.display(description="Owner")
    def owner_name(self, obj):
        if not obj.creator_id:
            return "-"
        name = obj.creator_id.user_id.get_full_name()
        return name if name.strip() else obj.creator_id.user_id.username

    @admin.display(description="Note", ordering="note_id__title")
    def note_title(self, obj):
        return obj.note_id.title if obj.note_id else "-"


@admin.register(NoteVersion)
class NoteVersionAdmin(admin.ModelAdmin):
    list_display = ("title", "owner_name", "note_title", "reason", "editor_mode", "date_created")
    search_fields = ("title", "note_id__title", "creator_id__user_id__username")
    readonly_fields = ("date_created",)

    @admin.display(description="Owner")
    def owner_name(self, obj):
        if not obj.creator_id:
            return "-"
        name = obj.creator_id.user_id.get_full_name()
        return name if name.strip() else obj.creator_id.user_id.username

    @admin.display(description="Note", ordering="note_id__title")
    def note_title(self, obj):
        return obj.note_id.title if obj.note_id else "-"


@admin.register(NoteIndex)
class NoteIndexAdmin(admin.ModelAdmin):
    list_display = ("note_title", "index", "noteblock_id")
    search_fields = ("note_id__title",)

    @admin.display(description="Note", ordering="note_id__title")
    def note_title(self, obj):
        return obj.note_id.title if obj.note_id else "-"


@admin.register(NoteActivitySession)
class NoteActivitySessionAdmin(admin.ModelAdmin):
    list_display = ("title", "owner_name", "note_title", "started_at", "ended_at")
    search_fields = ("title", "note_id__title", "creator_id__user_id__username")
    readonly_fields = ("date_created", "last_edit")

    @admin.display(description="Owner")
    def owner_name(self, obj):
        if not obj.creator_id:
            return "-"
        name = obj.creator_id.user_id.get_full_name()
        return name if name.strip() else obj.creator_id.user_id.username

    @admin.display(description="Note", ordering="note_id__title")
    def note_title(self, obj):
        return obj.note_id.title if obj.note_id else "-"


# ---- Courses -----------------------------------------------------------------

@admin.register(Course)
class CourseAdmin(admin.ModelAdmin):
    list_display = ("title", "owner_name", "is_default", "sort_order", "last_edit", "date_created")
    list_filter = ("is_default",)
    search_fields = ("title", "description", "creator_id__user_id__username", "creator_id__user_id__first_name")
    readonly_fields = ("date_created", "last_edit")
    inlines = [CourseMediaInline]

    @admin.display(description="Owner", ordering="creator_id__user_id__first_name")
    def owner_name(self, obj):
        if not obj.creator_id:
            return "-"
        name = obj.creator_id.user_id.get_full_name()
        return name if name.strip() else obj.creator_id.user_id.username


@admin.register(CourseMedia)
class CourseMediaAdmin(admin.ModelAdmin):
    list_display = ("title", "course_title", "description", "date_created")
    search_fields = ("title", "course_id__title")
    readonly_fields = ("date_created",)

    @admin.display(description="Course", ordering="course_id__title")
    def course_title(self, obj):
        return obj.course_id.title if obj.course_id else "-"


@admin.register(CourseSubscription)
class CourseSubscriptionAdmin(admin.ModelAdmin):
    list_display = ("owner_name", "course_title", "is_active", "subscribed_at", "last_opened_at")
    list_filter = ("is_active",)
    search_fields = ("creator_id__user_id__username", "course_id__title")
    readonly_fields = ("date_created", "last_edit")

    @admin.display(description="Owner", ordering="creator_id__user_id__first_name")
    def owner_name(self, obj):
        if not obj.creator_id:
            return "-"
        name = obj.creator_id.user_id.get_full_name()
        return name if name.strip() else obj.creator_id.user_id.username

    @admin.display(description="Course", ordering="course_id__title")
    def course_title(self, obj):
        return obj.course_id.title if obj.course_id else "-"


@admin.register(CourseOperationLog)
class CourseOperationLogAdmin(admin.ModelAdmin):
    list_display = ("owner_name", "course_title", "operation_type", "occurred_at")
    list_filter = ("operation_type",)
    search_fields = ("creator_id__user_id__username", "course_id__title")
    readonly_fields = ("date_created",)

    @admin.display(description="Owner")
    def owner_name(self, obj):
        if not obj.creator_id:
            return "-"
        name = obj.creator_id.user_id.get_full_name()
        return name if name.strip() else obj.creator_id.user_id.username

    @admin.display(description="Course", ordering="course_id__title")
    def course_title(self, obj):
        return obj.course_id.title if obj.course_id else "-"


# ---- Planner / Activity -----------------------------------------------------

@admin.register(PlannerEvent)
class PlannerEventAdmin(admin.ModelAdmin):
    list_display = ("title", "owner_name", "course_title", "event_date", "is_completed", "completed_at", "date_created")
    list_filter = ("is_completed", "event_date")
    search_fields = ("title", "description", "creator_id__user_id__username")
    readonly_fields = ("date_created", "last_edit")

    @admin.display(description="Owner", ordering="creator_id__user_id__first_name")
    def owner_name(self, obj):
        if not obj.creator_id:
            return "-"
        name = obj.creator_id.user_id.get_full_name()
        return name if name.strip() else obj.creator_id.user_id.username

    @admin.display(description="Course", ordering="course_id__title")
    def course_title(self, obj):
        return obj.course_id.title if obj.course_id else "-"


@admin.register(HeatmapActivity)
class HeatmapActivityAdmin(admin.ModelAdmin):
    list_display = ("owner_name", "note_title", "course_title", "activity_type", "activity_date", "word_count")
    list_filter = ("activity_type", "activity_date")
    search_fields = ("note_id__title", "creator_id__user_id__username")
    readonly_fields = ("date_created",)

    @admin.display(description="Owner")
    def owner_name(self, obj):
        if not obj.creator_id:
            return "-"
        name = obj.creator_id.user_id.get_full_name()
        return name if name.strip() else obj.creator_id.user_id.username

    @admin.display(description="Note", ordering="note_id__title")
    def note_title(self, obj):
        return obj.note_id.title if obj.note_id else "-"

    @admin.display(description="Course", ordering="course_id__title")
    def course_title(self, obj):
        return obj.course_id.title if obj.course_id else "-"


@admin.register(RecycleBinEntry)
class RecycleBinEntryAdmin(admin.ModelAdmin):
    list_display = ("owner_name", "note_title", "item_type", "deleted_at", "date_created")
    search_fields = ("creator_id__user_id__username", "note_id__title")
    readonly_fields = ("date_created", "last_edit")

    @admin.display(description="Owner")
    def owner_name(self, obj):
        if not obj.creator_id:
            return "-"
        name = obj.creator_id.user_id.get_full_name()
        return name if name.strip() else obj.creator_id.user_id.username

    @admin.display(description="Note", ordering="note_id__title")
    def note_title(self, obj):
        return obj.note_id.title if obj.note_id else "-"


@admin.register(Tag)
class TagAdmin(admin.ModelAdmin):
    list_display = ("name", "is_AI_generated", "noteblock_id", "date_created")
    list_filter = ("is_AI_generated",)
    search_fields = ("name",)
    readonly_fields = ("date_created",)


@admin.register(ValidationRecord)
class ValidationRecordAdmin(admin.ModelAdmin):
    list_display = ("owner_name", "noteblock_id", "date_created")
    readonly_fields = ("date_created",)

    @admin.display(description="Owner")
    def owner_name(self, obj):
        if not obj.creator_id:
            return "-"
        name = obj.creator_id.user_id.get_full_name()
        return name if name.strip() else obj.creator_id.user_id.username
