from django.contrib import admin

from .models import Conversation, Message


class MessageInline(admin.StackedInline):
    model = Message
    fields = ("role", "text", "image", "file")
    readonly_fields = ("created",)
    extra = 0


@admin.register(Conversation)
class ConversationAdmin(admin.ModelAdmin):
    list_display = ("title", "owner_name", "model", "total_prompt_tokens", "total_completion_tokens", "last_use", "date_created")
    list_filter = ("model",)
    search_fields = ("title", "creator_id__user_id__username", "creator_id__user_id__first_name")
    readonly_fields = ("date_created", "last_use")
    inlines = [MessageInline]

    @admin.display(description="Owner", ordering="creator_id__user_id__first_name")
    def owner_name(self, obj):
        if not obj.creator_id:
            return "-"
        name = obj.creator_id.user_id.get_full_name()
        return name if name.strip() else obj.creator_id.user_id.username


@admin.register(Message)
class MessageAdmin(admin.ModelAdmin):
    list_display = ("text_short", "conversation_title", "role", "created")
    list_filter = ("role",)
    search_fields = ("text", "conversation_id__title")
    readonly_fields = ("created",)

    @admin.display(description="Text (preview)")
    def text_short(self, obj):
        return (obj.text[:80] + "...") if obj.text and len(obj.text) > 80 else (obj.text or "-")

    @admin.display(description="Conversation", ordering="conversation_id__title")
    def conversation_title(self, obj):
        return obj.conversation_id.title if obj.conversation_id else "-"
