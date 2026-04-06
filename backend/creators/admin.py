"""
Admin view registration

After you modify the class, don't forget to register the models or 
they will not be avaliable in admin site.
"""
from django.contrib import admin

# Register your models here.

from .models import Creator, InvitationCode, VerificationCode


class MemberInline(admin.TabularInline):
    """Line per creator in admin view and one extra for convenience"""
    model = Creator
    extra = 1

class ActivationCodeInline(admin.StackedInline):
    """Line per creator in admin view and one extra for convenience"""
    model = VerificationCode
    extra = 1


@admin.register(InvitationCode)
class InvitationCodeAdmin(admin.ModelAdmin):
    list_display = ("label", "code_hash_short", "times_used", "max_uses", "expire_date", "created_at")
    list_filter = ("expire_date",)
    search_fields = ("label",)
    readonly_fields = ("times_used", "created_at")

    @admin.display(description="Hash (prefix)")
    def code_hash_short(self, obj):
        return obj.code_hash[:12] + "..." if obj.code_hash else ""


# Add model to admin view
admin.site.site_header = "Notechondria Admin"
admin.site.site_title = "Notechondria Admin"
admin.site.index_title = "Platform management"
admin.site.register(Creator)
admin.site.register(VerificationCode)
