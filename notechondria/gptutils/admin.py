from django.contrib import admin

# Register your models here.
from .models import Conversation,Message


class ConversationInline(admin.TabularInline):
    """Line per creator in admin view and one extra for convinience"""
    model=Conversation
    extra=1

class MessageInline(admin.StackedInline):
    """Line per creator in admin view and one extra for convinience"""
    model=Message
    extra=1

# Add model to admin view
admin.site.register(Conversation)
admin.site.register(Message)