from django.contrib import admin

# Register your models here.
from .models import Conversation,Message

class MessageInline(admin.StackedInline):
    """Line per message in admin view and one extra for convenience"""
    model=Message
    fields=["role","text","image","file"]
    # ordering=["created"]
    extra=1

class ConversationAdmin(admin.ModelAdmin):
    """ in admin view and one extra for convenience"""
    model=Conversation
    readonly_fields=["date_created","last_use"]
    inlines = [
        MessageInline
    ]
    extra=1


# Add model to admin view
admin.site.register(Conversation,ConversationAdmin)
admin.site.register(Message)