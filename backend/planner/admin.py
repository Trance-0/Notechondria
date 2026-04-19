from django.contrib import admin

from .models import CalendarFeed, HeatmapActivity, PlannerEvent


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


@admin.register(CalendarFeed)
class CalendarFeedAdmin(admin.ModelAdmin):
    list_display = ("title", "owner_name", "course_title", "is_enabled", "last_sync", "date_created")
    list_filter = ("is_enabled", "source_kind")
    search_fields = ("title", "creator_id__user_id__username")
    readonly_fields = ("date_created", "last_edit")

    @admin.display(description="Owner")
    def owner_name(self, obj):
        if not obj.creator_id:
            return "-"
        name = obj.creator_id.user_id.get_full_name()
        return name if name.strip() else obj.creator_id.user_id.username

    @admin.display(description="Course", ordering="course_id__title")
    def course_title(self, obj):
        return obj.course_id.title if obj.course_id else "-"
