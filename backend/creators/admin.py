"""
Admin view registration for the creators app.
"""
from django.contrib import admin

from .models import Creator, InvitationCode, SocialAccount, VerificationCode


class MemberInline(admin.TabularInline):
    model = Creator
    extra = 1


class ActivationCodeInline(admin.StackedInline):
    model = VerificationCode
    extra = 1


@admin.register(Creator)
class CreatorAdmin(admin.ModelAdmin):
    list_display = ("owner_name", "username", "email", "editor_mode", "reputation", "exp", "date_joined")
    list_filter = ("editor_mode", "theme_mode")
    search_fields = ("user_id__username", "user_id__first_name", "user_id__last_name", "user_id__email")
    readonly_fields = ("date_joined", "last_login")

    @admin.display(description="Owner", ordering="user_id__first_name")
    def owner_name(self, obj):
        name = obj.user_id.get_full_name()
        return name if name.strip() else obj.user_id.username

    @admin.display(description="Username", ordering="user_id__username")
    def username(self, obj):
        return obj.user_id.username

    @admin.display(description="Email", ordering="user_id__email")
    def email(self, obj):
        return obj.user_id.email


@admin.register(SocialAccount)
class SocialAccountAdmin(admin.ModelAdmin):
    list_display = ("owner_name", "provider", "provider_uid", "email", "created_at")
    list_filter = ("provider",)
    search_fields = ("user__username", "user__first_name", "user__last_name", "email", "provider_uid")
    readonly_fields = ("created_at",)

    @admin.display(description="Owner", ordering="user__first_name")
    def owner_name(self, obj):
        name = obj.user.get_full_name()
        return name if name.strip() else obj.user.username


@admin.register(InvitationCode)
class InvitationCodeAdmin(admin.ModelAdmin):
    list_display = ("label", "code_hash_short", "times_used", "max_uses", "expire_date", "created_at")
    list_filter = ("expire_date",)
    search_fields = ("label",)
    readonly_fields = ("times_used", "created_at")

    @admin.display(description="Hash (prefix)")
    def code_hash_short(self, obj):
        return obj.code_hash[:12] + "..." if obj.code_hash else ""


@admin.register(VerificationCode)
class VerificationCodeAdmin(admin.ModelAdmin):
    list_display = ("code_short", "usage", "function", "expire_date", "max_use")
    list_filter = ("usage",)
    search_fields = ("function",)

    @admin.display(description="Code (prefix)")
    def code_short(self, obj):
        return obj.code[:12] + "..." if obj.code else ""


admin.site.site_header = "Notechondria Admin"
admin.site.site_title = "Notechondria Admin"
admin.site.index_title = "Platform management"
