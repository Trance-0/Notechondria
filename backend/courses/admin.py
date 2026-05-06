from django.contrib import admin

from .models import (
    Course,
    CourseMedia,
    CourseOperationLog,
    CourseSubscription,
)


class CourseMediaInline(admin.TabularInline):
    model = CourseMedia
    fields = ("title", "description", "image", "source", "date_created")
    readonly_fields = ("date_created",)
    extra = 0


@admin.register(Course)
class CourseAdmin(admin.ModelAdmin):
    list_display = ("title", "owner_name", "sort_order", "last_edit", "date_created")
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
