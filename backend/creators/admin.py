"""
Admin view registration

After you modify the class, don't forget to register the models or 
they will not be avaliable in admin site.
"""
from django.conf import settings
from django.contrib import admin

# Register your models here.

from .models import Creator,VerificationCode


class MemberInline(admin.TabularInline):
    """Line per creator in admin view and one extra for convenience"""
    model=Creator
    extra=1

class ActivationCodeInline(admin.StackedInline):
    """Line per creator in admin view and one extra for convenience"""
    model=VerificationCode
    extra=1

# Add model to admin view
admin.site.site_header = settings.DJANGO_ADMIN_SITE_HEADER
admin.site.site_title = settings.DJANGO_ADMIN_SITE_TITLE
admin.site.index_title = settings.DJANGO_ADMIN_INDEX_TITLE
admin.site.register(Creator)
admin.site.register(VerificationCode)
