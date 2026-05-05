"""
Admin view registration for the creators app.
"""
from django.contrib import admin

from .models import Creator


class MemberInline(admin.TabularInline):
    model = Creator
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


# 0.1.119: SocialAccountAdmin removed alongside the SocialAccount
# model — Casdoor handles the per-provider linkage now via its own
# `Providers` tab on the Application, and Notechondria stores only
# the `Creator.casdoor_sub` foreign reference. See migration
# 0033_drop_socialaccount.

admin.site.site_header = "Notechondria Admin"
admin.site.site_title = "Notechondria Admin"
admin.site.index_title = "Platform management"
