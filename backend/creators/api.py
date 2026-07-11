import json
from django.conf import settings
from django.contrib.auth import authenticate
from django.contrib.auth.models import User
from django.utils.timezone import now
from urllib.parse import urlparse

from rest_framework import permissions, serializers, status
from rest_framework.authtoken.models import Token
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

import logging

from .utils import (
    ensure_creator,
    ensure_creator_avatar,
)


def absolute_media_url(request, raw_url: str) -> str:
    if not raw_url:
        return ""
    if raw_url.startswith("http://") or raw_url.startswith("https://"):
        return raw_url
    if request is None:
        return raw_url
    host = (
        request.META.get("HTTP_X_FORWARDED_HOST")
        or request.META.get("HTTP_HOST")
        or request.get_host()
    )
    scheme = request.META.get("HTTP_X_FORWARDED_PROTO") or request.scheme
    normalized = raw_url if raw_url.startswith("/") else f"/{raw_url}"
    if host:
        return f"{scheme}://{host}{normalized}"
    return request.build_absolute_uri(normalized)


def avatar_cache_bust(url: str, creator) -> str:
    """Append ``?v=<sync_ts>`` (or ``&v=...``) to an avatar URL so a
    Casdoor-side picture change paints immediately even when the underlying
    URL is byte-stable.

    The Casdoor avatar claim typically points at a stable path like
    ``https://auth.example.com/avatar/<sub>.png`` whose content rotates
    in place. Without a query param, browsers and CDNs hold the old bytes
    indefinitely. ``casdoor_profile_synced_at`` advances every time the
    JWT-driven sync notices a fresh claim value, so it's a natural
    cache-key. Returns the original URL unchanged when no sync timestamp
    is available (no harm — it's the same shape as before this fix).
    """
    if not url:
        return url
    synced = getattr(creator, "casdoor_profile_synced_at", None)
    if synced is None:
        return url
    sep = "&" if "?" in url else "?"
    return f"{url}{sep}v={int(synced.timestamp())}"


def creator_app_settings_payload(creator):
    payload = {
        "theme_preset": creator.theme_preset,
        "theme_mode": creator.theme_mode,
        "api_base_url": creator.api_base_url,
    }
    if creator.app_settings_json:
        try:
            decoded = json.loads(creator.app_settings_json)
        except json.JSONDecodeError:
            decoded = {}
        if isinstance(decoded, dict):
            payload.update(decoded)
    return payload


def auth_payload(user: User, *, token: str, request=None):
    """Return the response body the frontend expects after a successful
    Casdoor sign-in / bind.

    Post-Casdoor cutover, Notechondria no longer mints its own
    per-device session rows. The wire-shape ``token`` field carries
    the Casdoor JWT (`access_token`) that the SPA stores and resends
    as ``Authorization: Bearer <jwt>`` for every subsequent call —
    `CasdoorJWTAuthentication` validates it. Session lifecycle (idle,
    absolute timeout, multi-device list, revoke) is owned by Casdoor's
    own user portal at `auth.trance-0.com`.
    """
    creator = ensure_creator_avatar(ensure_creator(user))
    # Display name resolution (since 0.1.119): the operator-visible
    # label preferred on public surfaces (note bylines, comment
    # headers, sidebar header). Priority chain:
    #   1. `Creator.display_name` — refreshed from Casdoor's
    #      `displayName` claim every login (see
    #      `_sync_creator_from_claims`); user can also edit it from
    #      the settings page (next sync re-overwrites).
    #   2. `User.first_name + last_name` — historical fallback that
    #      the SPA already used; preserved for accounts where
    #      Casdoor doesn't supply a `displayName`.
    #   3. `User.username` — last-resort. Username is stable and
    #      never changed after account creation, so this is always
    #      a valid identifier.
    fallback_name = f"{user.first_name} {user.last_name}".strip()
    display_name = creator.display_name or fallback_name or user.username
    # Avatar URL resolution: prefer the remote Casdoor avatar
    # (`Creator.avatar_url`, refreshed each login) over the locally-
    # uploaded `Creator.image`. Empty `avatar_url` falls back to the
    # local file's media URL (or "" when no upload exists). This way
    # a Casdoor profile-picture change propagates to every
    # Notechondria surface on next login without re-uploading.
    # Append `?v=<sync_ts>` so a Casdoor-side avatar change paints
    # immediately even when the underlying URL string is unchanged.
    avatar_url = avatar_cache_bust(creator.avatar_url, creator)
    # Always expose the locally-uploaded avatar separately so the SPA
    # can fall back to it when the Casdoor `avatar_url` fails to load
    # (auth server offline / 404). `image_url` stays the "effective"
    # avatar (Casdoor first, then local) for backward compatibility.
    image_upload_url = absolute_media_url(
        request, creator.image.url if creator.image else "",
    )
    image_url = avatar_url or image_upload_url
    return {
        "token": token,
        "user": {
            "id": user.id,
            "email": user.email,
            "username": user.username,
            "first_name": user.first_name,
            "last_name": user.last_name,
            "display_name": display_name,
            "is_staff": user.is_staff,
            "is_superuser": user.is_superuser,
            "motto": creator.motto or "",
            "social_link": creator.social_link or "",
            "image_url": image_url,
            "avatar_url": avatar_url,
            "image_upload_url": image_upload_url,
            "editor_mode": creator.editor_mode,
            "theme_preset": creator.theme_preset,
            "theme_mode": creator.theme_mode,
            "api_base_url": creator.api_base_url,
            "uncategorized_folder_name": creator.uncategorized_folder_name or "Inbox",
            "app_settings": creator_app_settings_payload(creator),
            "app_settings_updated_at": creator.app_settings_updated_at.isoformat()
            if creator.app_settings_updated_at
            else None,
            "casdoor_profile_synced_at":
                creator.casdoor_profile_synced_at.isoformat()
                if creator.casdoor_profile_synced_at
                else None,
            "last_seen_versions": creator.last_seen_versions or {},
        },
    }


# ---------------------------------------------------------------------------
# Legacy email/username + password login. Restored in 0.1.111 as the
# fallback path so existing accounts can still sign in when Casdoor is
# down or misconfigured. Register / password reset / email verification
# stay deleted (Casdoor owns those flows post-0.1.106) — this view only
# authenticates an existing user against their stored Django password
# hash and mints a DRF stock `authtoken_token` row. The SPA resends it
# as `Authorization: Token <hex>` for every subsequent call;
# `rest_framework.authentication.TokenAuthentication` validates it.
# ---------------------------------------------------------------------------


class LoginSerializer(serializers.Serializer):
    """Accepts ``{email|identifier|username, password}``. ``email`` is
    the historical field name the SPA still posts; ``identifier`` and
    ``username`` are aliases so a future refactor can rename without
    breaking the wire shape. Whichever one is non-empty is matched
    case-insensitively against ``User.email`` first, then
    ``User.username``."""

    email = serializers.CharField(required=False, allow_blank=True)
    identifier = serializers.CharField(required=False, allow_blank=True)
    username = serializers.CharField(required=False, allow_blank=True)
    password = serializers.CharField(write_only=True)

    def validate(self, attrs):
        identifier = (
            attrs.get("email")
            or attrs.get("identifier")
            or attrs.get("username")
            or ""
        ).strip()
        if not identifier:
            raise serializers.ValidationError(
                "Sign-in rejected: "
                "Backend.Creators.Auth/login — "
                "either email or username is required in the login payload."
            )
        # Email-first match, fall back to username for legacy accounts
        # that never had an email on file.
        matched = User.objects.filter(email__iexact=identifier).first()
        if matched is None:
            matched = User.objects.filter(username__iexact=identifier).first()
        if matched is None:
            raise serializers.ValidationError(
                "Sign-in rejected: "
                "Backend.Creators.Auth/login — "
                "no account found for the supplied email/username."
            )
        user = authenticate(username=matched.username, password=attrs["password"])
        if user is None:
            # The local hash may be stale: the account's source of
            # truth for credentials is Casdoor (the user may have
            # changed the password there since the last sync). Ask
            # Casdoor directly via the ROPC grant; on success the
            # verified plaintext is stored locally so the next outage
            # can be served from the local hash alone.
            user = self._casdoor_password_sync(
                matched, identifier, attrs["password"]
            )
        if user is None:
            raise serializers.ValidationError(
                "Sign-in rejected: "
                "Backend.Creators.Auth/login — "
                "email/username and password do not match any active account."
            )
        if not user.is_active:
            raise serializers.ValidationError(
                "Sign-in rejected: "
                "Backend.Creators.Auth/login — "
                "this account is inactive; ask the Notechondria admin to "
                "reactivate it."
            )
        attrs["user"] = user
        return attrs

    @staticmethod
    def _casdoor_password_sync(matched, identifier, password):
        """Validate the submitted credentials against Casdoor (ROPC
        grant) and, on success, store the verified plaintext locally
        via ``set_password`` so the fallback keeps working offline.

        Only runs for accounts already linked to a Casdoor identity
        (``Creator.casdoor_sub`` set) and only accepts the grant when
        the returned JWT's ``sub`` matches that link — no auto-bind,
        consistent with the 0.1.118 link-challenge policy. Returns
        the authenticated ``User`` or ``None``.
        """
        from .casdoor_auth import _claim_str
        from .casdoor_password import GRANT_OK, GRANT_REJECTED, password_grant
        from .models import Creator

        creator = Creator.objects.filter(user_id=matched).first()
        if creator is None or not creator.casdoor_sub:
            return None
        status_, claims = password_grant(identifier, password)
        if (
            status_ == GRANT_REJECTED
            and matched.username
            and matched.username.lower() != identifier.lower()
        ):
            # The user may sign in to Casdoor under a different name
            # than the local username (or typed their email). One
            # retry with the linked account's username.
            status_, claims = password_grant(matched.username, password)
        if status_ != GRANT_OK or not isinstance(claims, dict):
            return None
        sub = _claim_str(claims, "CASDOOR_CLAIM_SUB")
        if not sub or sub != creator.casdoor_sub:
            logger.info(
                "Password fallback not synced: "
                "Backend.Creators.Auth/login.casdoor_sync — Casdoor "
                "accepted the credentials but the token sub does not "
                "match the linked account (username=%s).",
                matched.username,
            )
            return None
        if not matched.is_active:
            return None
        matched.set_password(password)
        matched.save(update_fields=["password"])
        logger.info(
            "Password fallback synced from Casdoor ROPC grant: "
            "Backend.Creators.Auth/login.casdoor_sync — username=%s.",
            matched.username,
        )
        return matched


class LoginApiView(APIView):
    """POST ``/auth/login/`` — username/password fallback so existing
    users can still sign in when Casdoor is unreachable. Issues a DRF
    stock ``authtoken_token`` row (idempotent: returns the existing
    token if one already exists for the user). No registration, no
    password reset, no email verification — those live in Casdoor.
    """

    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data["user"]
        token, _created = Token.objects.get_or_create(user=user)
        try:
            User.objects.filter(pk=user.pk).update(last_login=now())
        except Exception:  # noqa: BLE001
            pass
        return Response(auth_payload(user, token=token.key, request=request))


class SettingsSerializer(serializers.Serializer):
    username = serializers.CharField(required=False, max_length=150)
    first_name = serializers.CharField(required=False, allow_blank=True, max_length=150)
    last_name = serializers.CharField(required=False, allow_blank=True, max_length=150)
    email = serializers.EmailField(required=False)
    motto = serializers.CharField(allow_blank=True, required=False, max_length=100)
    social_link = serializers.URLField(allow_blank=True, required=False)
    # 0.1.119: optional user-facing label preferred over username on
    # public surfaces. Refreshed every login from the Casdoor JWT —
    # editing it from the SPA will be re-overwritten by the next
    # sign-in unless the operator also updates Casdoor's user record.
    display_name = serializers.CharField(allow_blank=True, required=False, max_length=255)
    image_url = serializers.CharField(read_only=True)
    avatar_url = serializers.CharField(read_only=True)
    image_upload_url = serializers.CharField(read_only=True)
    avatar = serializers.ImageField(write_only=True, required=False)
    theme_preset = serializers.CharField(required=False, allow_blank=False, max_length=32)
    theme_mode = serializers.ChoiceField(
        choices=[
            ("S", "system"),
            ("L", "light"),
            ("D", "dark"),
        ],
        required=False,
    )
    api_base_url = serializers.CharField(required=False, allow_blank=False, max_length=255)
    mcp_skill_md = serializers.CharField(required=False, allow_blank=True)
    # 0.1.120: user-chosen display label for the synthetic 'no category'
    # bucket (notes whose `course_id IS NULL`). Persisted on Creator;
    # the SPA renders the bucket itself client-side.
    uncategorized_folder_name = serializers.CharField(
        required=False, allow_blank=False, max_length=120,
    )
    app_settings = serializers.JSONField(required=False)
    app_settings_updated_at = serializers.DateTimeField(required=False, allow_null=True)
    # 0.1.127: per-app What's-New tracking. Map of app id -> newest
    # app version whose feature-update overlay the user has seen or
    # skipped. PATCHing merges keys instead of replacing the map so
    # the editor stamping "editor" can't erase planner's entry.
    last_seen_versions = serializers.JSONField(required=False)
    editor_mode = serializers.ChoiceField(
        choices=[
            ("G", "gfm"),
            ("B", "blocks"),
            ("P", "plain_text"),
        ],
        required=False,
    )

    def to_representation(self, instance):
        request = self.context.get("request") if self.context else None
        # Same priority chain as auth_payload: prefer the explicit
        # `Creator.display_name` (refreshed from Casdoor each login),
        # fall back to first+last name, then username. Mirrors the
        # SPA's expectation so settings page + auth payload show the
        # same label.
        fallback_name = (
            f"{instance.user_id.first_name} {instance.user_id.last_name}".strip()
        )
        display_name = (
            instance.display_name
            or fallback_name
            or instance.user_id.username
        )
        # Avatar: prefer remote (Casdoor) over local file. See
        # auth_payload for the rationale. ``avatar_cache_bust`` appends
        # a sync-timestamp query param so a Casdoor-side picture
        # change paints immediately even when the URL is byte-stable.
        avatar_url = avatar_cache_bust(instance.avatar_url, instance)
        # See auth_payload: expose the local upload separately so the
        # SPA can fall back when the Casdoor avatar fails to load.
        image_upload_url = absolute_media_url(
            request,
            instance.image.url if instance.image else "",
        )
        image_url = avatar_url or image_upload_url
        return {
            "username": instance.user_id.username,
            "first_name": instance.user_id.first_name,
            "last_name": instance.user_id.last_name,
            "email": instance.user_id.email,
            "is_staff": instance.user_id.is_staff,
            "is_superuser": instance.user_id.is_superuser,
            "motto": instance.motto or "",
            "social_link": instance.social_link or "",
            "display_name": display_name,
            "image_url": image_url,
            "avatar_url": avatar_url,
            "image_upload_url": image_upload_url,
            "editor_mode": instance.editor_mode,
            "theme_preset": instance.theme_preset,
            "theme_mode": instance.theme_mode,
            "api_key_prefix": instance.api_key_prefix or "",
            "api_base_url": instance.api_base_url,
            "mcp_skill_md": instance.mcp_skill_md or "",
            "uncategorized_folder_name": instance.uncategorized_folder_name or "Inbox",
            "casdoor_linked": bool(instance.casdoor_sub),
            "casdoor_profile_synced_at":
                instance.casdoor_profile_synced_at.isoformat()
                if instance.casdoor_profile_synced_at
                else None,
            "app_settings": creator_app_settings_payload(instance),
            "app_settings_updated_at": instance.app_settings_updated_at.isoformat()
            if instance.app_settings_updated_at
            else None,
            "last_seen_versions": instance.last_seen_versions or {},
        }

    def validate_username(self, value):
        user = self.instance.user_id if self.instance is not None else None
        existing = User.objects.filter(username__iexact=value).exclude(pk=user.pk if user else None).first()
        if existing is not None:
            raise serializers.ValidationError(
                "Settings not saved: "
                "Backend.Creators.Settings/update.validate_username — "
                "this username is already in use by another account."
            )
        return value

    def validate_email(self, value):
        user = self.instance.user_id if self.instance is not None else None
        if user is not None and user.email.lower() == value.lower():
            return user.email
        existing = User.objects.filter(email__iexact=value).exclude(pk=user.pk if user else None).first()
        if existing is not None:
            raise serializers.ValidationError(
                "Settings not saved: "
                "Backend.Creators.Settings/update.validate_email — "
                "this email is already in use by another account."
            )
        return value.lower()

    def validate_last_seen_versions(self, value):
        if not isinstance(value, dict):
            raise serializers.ValidationError(
                "Settings not saved: "
                "Backend.Creators.Settings/update.validate_last_seen_versions"
                " — value must be a JSON object mapping app id to version "
                "string."
            )
        cleaned = {}
        for key, version in value.items():
            if (
                not isinstance(key, str)
                or not isinstance(version, str)
                or not key.strip()
                or not version.strip()
                or len(key) > 32
                or len(version) > 32
            ):
                raise serializers.ValidationError(
                    "Settings not saved: "
                    "Backend.Creators.Settings/update."
                    "validate_last_seen_versions — each entry must map a "
                    "non-empty app id (<=32 chars) to a non-empty version "
                    "string (<=32 chars)."
                )
            cleaned[key.strip()] = version.strip()
        if len(cleaned) > 16:
            raise serializers.ValidationError(
                "Settings not saved: "
                "Backend.Creators.Settings/update.validate_last_seen_versions"
                " — at most 16 app entries are accepted."
            )
        return cleaned

    def validate_api_base_url(self, value):
        normalized = value.strip()
        parsed = urlparse(normalized)
        if parsed.scheme not in {"http", "https"} or not parsed.netloc:
            raise serializers.ValidationError(
                "Settings not saved: "
                "Backend.Creators.Settings/update.validate_api_base_url — "
                "value must be a full http:// or https:// URL with a host."
            )
        return normalized

    def update(self, instance, validated_data):
        user = instance.user_id
        user_dirty = False
        if "username" in validated_data:
            user.username = validated_data["username"]
            user_dirty = True
        if "email" in validated_data:
            user.email = validated_data["email"]
            user_dirty = True
        if "first_name" in validated_data:
            user.first_name = validated_data["first_name"]
            user_dirty = True
        if "last_name" in validated_data:
            user.last_name = validated_data["last_name"]
            user_dirty = True
        if user_dirty:
            user.save(update_fields=["username", "email", "first_name", "last_name"])
        instance.motto = validated_data.get("motto", instance.motto)
        instance.social_link = validated_data.get("social_link", instance.social_link)
        # 0.1.119: editable display_name. The next Casdoor sign-in
        # re-overwrites this from the IdP's `displayName` claim, so
        # operator-side edits are best-effort overrides for sessions
        # in flight rather than a permanent record. The user-facing
        # text in the SPA settings card calls this out.
        if "display_name" in validated_data:
            instance.display_name = validated_data["display_name"][:255]
        instance.editor_mode = validated_data.get("editor_mode", instance.editor_mode)
        if "mcp_skill_md" in validated_data:
            instance.mcp_skill_md = validated_data["mcp_skill_md"]
        # 0.1.120: editable display label for the uncategorized bucket.
        # Trimmed to 120 chars and falls back to "Inbox" when blank so a
        # user clearing the field doesn't end up with an unlabelled
        # bucket.
        if "uncategorized_folder_name" in validated_data:
            label = (validated_data["uncategorized_folder_name"] or "").strip()
            instance.uncategorized_folder_name = (label or "Inbox")[:120]
        if "avatar" in validated_data:
            instance.image = validated_data["avatar"]
        if "last_seen_versions" in validated_data:
            merged = dict(instance.last_seen_versions or {})
            merged.update(validated_data["last_seen_versions"])
            instance.last_seen_versions = merged
        app_settings = creator_app_settings_payload(instance)
        if "app_settings" in validated_data and isinstance(validated_data["app_settings"], dict):
            app_settings.update(validated_data["app_settings"])
        if "theme_preset" in validated_data:
            app_settings["theme_preset"] = validated_data["theme_preset"]
        if "theme_mode" in validated_data:
            app_settings["theme_mode"] = validated_data["theme_mode"]
        if "api_base_url" in validated_data:
            app_settings["api_base_url"] = validated_data["api_base_url"]
        instance.theme_preset = app_settings.get("theme_preset", instance.theme_preset)
        instance.theme_mode = app_settings.get("theme_mode", instance.theme_mode)
        instance.api_base_url = app_settings.get("api_base_url", instance.api_base_url)
        if (
            "app_settings" in validated_data
            or "theme_preset" in validated_data
            or "theme_mode" in validated_data
            or "api_base_url" in validated_data
        ):
            instance.app_settings_json = json.dumps(app_settings, sort_keys=True)
            instance.app_settings_updated_at = validated_data.get("app_settings_updated_at") or now()
        instance.save()
        return instance


class SettingsApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser, JSONParser]

    def get(self, request):
        creator = ensure_creator_avatar(ensure_creator(request.user))
        return Response(SettingsSerializer(creator, context={"request": request}).data)

    def patch(self, request):
        creator = ensure_creator_avatar(ensure_creator(request.user))
        serializer = SettingsSerializer(
            instance=creator,
            data=request.data,
            partial=True,
            context={"request": request},
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(SettingsSerializer(creator, context={"request": request}).data)


class RotateApiKeyApiView(APIView):
    """Generate a new MCP API key for the authenticated user.

    POST /api/v1/auth/rotate-api-key/
    Returns the plaintext key ONCE.  Only the SHA-256 hash is stored.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        import hashlib
        import secrets
        creator = ensure_creator(request.user)
        plaintext = f"ntc_{secrets.token_hex(16)}"  # 32 hex chars after prefix
        creator.api_key_hash = hashlib.sha256(plaintext.encode()).hexdigest()
        creator.api_key_prefix = plaintext[:8]
        creator.save(update_fields=["api_key_hash", "api_key_prefix"])
        return Response({
            "api_key": plaintext,
            "api_key_prefix": creator.api_key_prefix,
        })


logger = logging.getLogger("django")


# ---------------------------------------------------------------------------
# Experimental: GitHub data-sync integration
# ---------------------------------------------------------------------------


class GithubSyncStatusApiView(APIView):
    """GET the current install/status for the authenticated user."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        from .models import GithubIntegration

        creator = ensure_creator(request.user)
        integration = GithubIntegration.objects.filter(creator=creator).first()
        install_url = settings.GITHUB_DATA_SYNC_APP_INSTALL_URL or ""
        if not integration:
            return Response({
                "connected": False,
                "install_url": install_url,
                "app_name": settings.GITHUB_DATA_SYNC_APP_NAME or "",
            })
        return Response({
            "connected": True,
            "install_url": install_url,
            "app_name": settings.GITHUB_DATA_SYNC_APP_NAME or "",
            "account_login": integration.account_login,
            "repo_full_name": integration.repo_full_name,
            "repo_default_branch": integration.repo_default_branch,
            "last_push_at": integration.last_push_at.isoformat()
            if integration.last_push_at
            else None,
            "last_push_sha": integration.last_push_sha,
            "last_error": integration.last_error or "",
        })

    def delete(self, request):
        """Disconnect the App installation. Does NOT uninstall the App
        on GitHub's side — the user must do that from their GitHub
        settings; we just drop our record so the local UI shows
        disconnected."""
        from .models import GithubIntegration

        creator = ensure_creator(request.user)
        GithubIntegration.objects.filter(creator=creator).delete()
        return Response({"connected": False})


class GithubSyncCallbackSerializer(serializers.Serializer):
    installation_id = serializers.CharField(max_length=64)
    account_login = serializers.CharField(
        max_length=80, required=False, allow_blank=True, default=""
    )
    repo_full_name = serializers.CharField(
        max_length=160, required=False, allow_blank=True, default=""
    )
    repo_default_branch = serializers.CharField(
        max_length=80, required=False, allow_blank=True, default="main"
    )


class GithubSyncCallbackApiView(APIView):
    """Persist (or update) the install id after the user completes the
    GitHub App install flow.

    The frontend sends the install id from the GitHub redirect query
    string (`?installation_id=...`) along with the user's chosen repo.
    """

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        from .models import GithubIntegration

        # 0.1.120: structured entry log for the GH-link round trip.
        # The earlier "no logs on backend" symptom came from this view
        # being silent on success — when the SPA cold-boots after the
        # GitHub redirect with an expired Casdoor JWT, DRF rejects the
        # request as 401 before reaching the view, so the install is
        # silently dropped on the floor. Logging entry + exit here
        # plus DRF's authentication-failed line gives a clear trace.
        logger.info(
            "GitHub sync install callback received: "
            "Backend.Creators.GithubSync/install_callback — "
            "user=%s installation_id=%r repo=%r.",
            request.user.username,
            request.data.get("installation_id"),
            request.data.get("repo_full_name") or "",
        )
        serializer = GithubSyncCallbackSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        creator = ensure_creator(request.user)
        integration, _created = GithubIntegration.objects.update_or_create(
            creator=creator,
            defaults={
                "installation_id": serializer.validated_data["installation_id"],
                "account_login": serializer.validated_data.get(
                    "account_login", ""
                ),
                "repo_full_name": serializer.validated_data.get(
                    "repo_full_name", ""
                ),
                "repo_default_branch": serializer.validated_data.get(
                    "repo_default_branch", "main"
                ) or "main",
                "last_error": "",
            },
        )
        logger.info(
            "GitHub sync install persisted: "
            "Backend.Creators.GithubSync/install_callback — "
            "user=%s installation_id=%s repo=%s created=%s.",
            request.user.username,
            integration.installation_id,
            integration.repo_full_name or "<unset>",
            _created,
        )
        return Response({
            "connected": True,
            "installation_id": integration.installation_id,
            "repo_full_name": integration.repo_full_name,
        })


class GithubSyncPushApiView(APIView):
    """Push the authenticated user's full server-side data to their
    linked GitHub repo. Returns the resulting commit SHA.

    Accepts an optional ``include_assets`` query string flag (or JSON
    body field) — when truthy, avatar / cover / attachment bytes are
    inlined under ``assets/`` in the export so the resulting clone is
    self-contained. Subject to the per-file and per-push size caps in
    `creators.services.github_sync`.
    """

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        from .services.github_sync import GithubSyncError, push_user_data

        creator = ensure_creator(request.user)
        # Accept the flag from either the query string (for the
        # frontend's GET-style toggle) or the JSON body (for scripted
        # callers that prefer to keep everything in one payload).
        raw = (
            request.query_params.get("include_assets")
            or request.data.get("include_assets")
            if hasattr(request, "data") else None
        )
        include_assets = str(raw).lower() in ("1", "true", "yes", "on")
        try:
            sha = push_user_data(creator, include_assets=include_assets)
        except GithubSyncError as exc:
            return Response(
                {"detail": str(exc)},
                status=status.HTTP_400_BAD_REQUEST,
            )
        return Response({"commit_sha": sha, "include_assets": include_assets})


class GithubSyncReposApiView(APIView):
    """List the repositories accessible to the user's GitHub App
    installation. Used by the frontend repo-picker dropdown.

    Returns ``{"repositories": [{"full_name", "default_branch",
    "private"}]}`` paginated through ``per_page=100`` until GitHub
    runs out of results. Errors map to a 400 with the structured
    `GithubSyncError` message so the UI can surface a useful hint.
    """

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        import requests as http_requests

        from .models import GithubIntegration
        from .services.github_sync import (
            GithubSyncError,
            _ensure_token,
            _github_headers,
        )

        creator = ensure_creator(request.user)
        integration = GithubIntegration.objects.filter(creator=creator).first()
        if integration is None:
            return Response(
                {"detail": (
                    "Cannot list repositories: "
                    "Backend.Creators.GithubSync/list_repos — "
                    "no GitHub App installation linked to this account. "
                    "Click “Install Notechondria GitHub App” first."
                )},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            token = _ensure_token(integration)
        except GithubSyncError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        headers = _github_headers(token)
        repos = []
        page = 1
        while True:
            try:
                resp = http_requests.get(
                    "https://api.github.com/installation/repositories",
                    headers=headers,
                    params={"per_page": 100, "page": page},
                    timeout=15,
                )
            except http_requests.RequestException as exc:
                return Response(
                    {"detail": (
                        "Cannot list repositories: "
                        "Backend.Creators.GithubSync/list_repos — "
                        f"network error contacting GitHub: {exc}."
                    )},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            if resp.status_code >= 400:
                return Response(
                    {"detail": (
                        "Cannot list repositories: "
                        "Backend.Creators.GithubSync/list_repos — "
                        f"GitHub returned {resp.status_code}."
                    )},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            payload = resp.json() or {}
            chunk = payload.get("repositories") or []
            for repo in chunk:
                repos.append({
                    "full_name": repo.get("full_name", ""),
                    "default_branch": repo.get("default_branch", "main"),
                    "private": bool(repo.get("private", False)),
                })
            # GitHub paginates via Link header; falling out when a page
            # returns fewer than per_page entries is the simpler invariant
            # and matches the contract of /installation/repositories.
            if len(chunk) < 100:
                break
            page += 1
            if page > 50:
                # Defensive cap: 5,000 repos. Anything past that is a
                # mis-installed App, not a real personal account.
                break
        return Response({"repositories": repos})


# ---------------------------------------------------------------------------
# Casdoor: the only auth surface as of 0.1.106. All session lifecycle,
# password reset, and signup happen on `auth.trance-0.com`.
# ---------------------------------------------------------------------------


class CasdoorConfigApiView(APIView):
    """Public OIDC endpoints + client id for the frontend Casdoor
    SDK. Returns ``configured: false`` plus an empty payload when the
    backend doesn't have ``CASDOOR_*`` env vars set."""

    permission_classes = [permissions.AllowAny]

    def get(self, request):
        endpoint = (settings.CASDOOR_ENDPOINT or "").rstrip("/")
        configured = bool(
            endpoint
            and settings.CASDOOR_CLIENT_ID
            and settings.CASDOOR_ORG_NAME
            and settings.CASDOOR_APP_NAME
        )
        if not configured:
            return Response({"configured": False})
        # signin_url is the org-themed Casdoor login page
        # (`<endpoint>/login/<CASDOOR_ORG_NAME>`). Both the URL
        # base and the org segment come from env vars
        # (`CASDOOR_ENDPOINT`, `CASDOOR_ORG_NAME`) — the deploy
        # operator can switch Casdoor instances or rename the org
        # without touching code. Per the user's directive in
        # 0.1.116: keep the org-themed surface, env-driven.
        #
        # 0.1.116 reverts the 0.1.112 switch to `CASDOOR_APP_NAME`.
        # The brief flip happened because at the time the user
        # had renamed the org to `trance-0` and asked for
        # `/login/notechondria`; subsequently they confirmed the
        # final URL should land at `/login/trance-0` (org-themed)
        # so the org name is the right segment.
        return Response({
            "configured": True,
            "endpoint": endpoint,
            "client_id": settings.CASDOOR_CLIENT_ID,
            "organization": settings.CASDOOR_ORG_NAME,
            "application": settings.CASDOOR_APP_NAME,
            "signin_url": f"{endpoint}/login/{settings.CASDOOR_ORG_NAME}",
        })


class CasdoorExchangeSerializer(serializers.Serializer):
    code = serializers.CharField(required=True, allow_blank=False)
    state = serializers.CharField(required=False, allow_blank=True, default="")


class CasdoorUnlinkApiView(APIView):
    """Drop the Casdoor link on the current user's Creator. Idempotent
    — returns success even if the link wasn't set."""

    permission_classes = [permissions.IsAuthenticated]

    def delete(self, request):
        creator = ensure_creator(request.user)
        had_link = bool(creator.casdoor_sub)
        if had_link:
            creator.casdoor_sub = ""
            creator.save(update_fields=["casdoor_sub"])
            logger.info(
                "Unlinked Casdoor account: "
                "Backend.Creators.CasdoorAuth/unlink — user=%s.",
                request.user.username,
            )
        return Response({"casdoor_linked": False, "was_linked": had_link})


class CasdoorBindApiView(APIView):
    """Link a Casdoor identity to the *currently* signed-in user.

    The exchange flow on `/auth/casdoor/exchange/` resolves identity
    via `Creator.casdoor_sub` → email-iexact → auto-provision; this
    endpoint is the manual override for users who want to link a
    Casdoor account *to their existing account* without going through
    the email match (e.g. when the Casdoor email differs).

    Wire shape:

    - Auth: standard ``Authorization: Bearer <casdoor-jwt>``.
    - Body: ``{"code": "<casdoor-authz-code>"}``.
    - Returns the standard ``auth_payload`` shape on success.
    - 409 when the Casdoor `sub` is already linked to a different
      Creator. The user must unlink that side first.
    """

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        from .casdoor_auth import _build_sdk, verify_token

        sdk = _build_sdk()
        if sdk is None:
            return Response(
                {"detail": (
                    "Casdoor account linking unavailable: "
                    "Backend.Creators.CasdoorAuth/bind — "
                    "backend is in shadow mode (CASDOOR_* env vars "
                    "not configured)."
                )},
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )
        code = (request.data.get("code") or "").strip()
        if not code:
            return Response(
                {"detail": (
                    "Casdoor account linking aborted: "
                    "Backend.Creators.CasdoorAuth/bind — "
                    "request body is missing required field `code`."
                )},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            tokens = sdk.get_oauth_token(code=code)
        except Exception as exc:  # noqa: BLE001
            return Response(
                {"detail": (
                    "Casdoor account linking aborted: "
                    "Backend.Creators.CasdoorAuth/bind — "
                    f"Casdoor rejected the authorization code: {exc}."
                )},
                status=status.HTTP_400_BAD_REQUEST,
            )
        access_token = (
            tokens.get("access_token") if isinstance(tokens, dict) else None
        )
        claims = verify_token(access_token) if access_token else None
        if claims is None:
            return Response(
                {"detail": (
                    "Casdoor account linking aborted: "
                    "Backend.Creators.CasdoorAuth/bind — "
                    "Casdoor returned a token whose JWT signature "
                    "could not be verified."
                )},
                status=status.HTTP_400_BAD_REQUEST,
            )
        sub = (claims.get("id") or claims.get("sub") or "").strip()
        if not sub:
            return Response(
                {"detail": (
                    "Casdoor account linking aborted: "
                    "Backend.Creators.CasdoorAuth/bind — "
                    "JWT does not carry an `id` / `sub` claim."
                )},
                status=status.HTTP_400_BAD_REQUEST,
            )
        creator = ensure_creator(request.user)
        # Conflict: the Casdoor sub is already on a different
        # Creator. We refuse to silently transfer the link.
        from .models import Creator
        existing = (
            Creator.objects.filter(casdoor_sub=sub)
            .exclude(user_id=request.user)
            .first()
        )
        if existing is not None:
            return Response(
                {"detail": (
                    "Casdoor account linking aborted: "
                    "Backend.Creators.CasdoorAuth/bind — "
                    "this Casdoor identity is already linked to "
                    "another Notechondria account. Unlink that side "
                    "first or sign in with it directly."
                )},
                status=status.HTTP_409_CONFLICT,
            )
        creator.casdoor_sub = sub
        creator.save(update_fields=["casdoor_sub"])
        logger.info(
            "Linked Casdoor account: "
            "Backend.Creators.CasdoorAuth/bind — "
            "user=%s sub=%s.",
            request.user.username, sub[:12],
        )
        return Response(auth_payload(request.user, token=access_token, request=request))


class CasdoorExchangeApiView(APIView):
    """Exchange a Casdoor authorization code for either:

    - the standard ``auth_payload`` (when the Casdoor `sub` is
      already linked to a Notechondria account), or
    - a ``link_challenge`` (a one-time-use ticket the SPA shows
      the user as a "bind existing account or create new"
      dialog).

    The SPA then POSTs the chosen path's credentials to
    ``/auth/casdoor/link/bind/`` (legacy username + password) or
    ``/auth/casdoor/link/create/`` (new password) along with the
    challenge nonce; both completion endpoints return the
    standard ``auth_payload``.

    0.1.118 reshaped this view: prior versions auto-linked by
    email and auto-provisioned by sub, which made it impossible
    to know which Notechondria account a fresh Casdoor identity
    would land on. The gitea-style choice flow is safer for
    migrating accounts and gives the user explicit control.

    Returns 503 when the Casdoor SDK isn't configured.
    """

    permission_classes = [permissions.AllowAny]

    def post(self, request):
        from .casdoor_auth import (
            _build_sdk,
            _check_group_access,
            _claim_groups,
            _claim_str,
            _resolve_existing_user,
            _sync_creator_from_claims,
            verify_token,
        )

        sdk = _build_sdk()
        if sdk is None:
            return Response(
                {"detail": (
                    "Casdoor sign-in unavailable: "
                    "Backend.Creators.CasdoorAuth/exchange — "
                    "backend is in shadow mode (CASDOOR_* env vars "
                    "not configured)."
                )},
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )
        serializer = CasdoorExchangeSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        code = serializer.validated_data["code"]
        try:
            tokens = sdk.get_oauth_token(code=code)
        except Exception as exc:  # noqa: BLE001
            return Response(
                {"detail": (
                    "Cannot sign in: "
                    "Backend.Creators.CasdoorAuth/exchange — "
                    f"Casdoor rejected the authorization code: {exc}."
                )},
                status=status.HTTP_400_BAD_REQUEST,
            )
        access_token = (
            tokens.get("access_token") if isinstance(tokens, dict) else None
        )
        if not access_token:
            return Response(
                {"detail": (
                    "Cannot sign in: "
                    "Backend.Creators.CasdoorAuth/exchange — "
                    "Casdoor token response did not include an "
                    "`access_token` field."
                )},
                status=status.HTTP_400_BAD_REQUEST,
            )
        claims = verify_token(access_token)
        if claims is None:
            return Response(
                {"detail": (
                    "Cannot sign in: "
                    "Backend.Creators.CasdoorAuth/exchange — "
                    "Casdoor returned a token whose JWT signature "
                    "could not be verified against the configured "
                    "certificate."
                )},
                status=status.HTTP_400_BAD_REQUEST,
            )
        # Group-based ACL gate (since 0.1.110): if
        # CASDOOR_REQUIRED_GROUPS is set, the JWT's `groups` claim
        # must overlap. Empty setting = no gating.
        denied_reason = _check_group_access(claims)
        if denied_reason is not None:
            return Response(
                {"detail": (
                    "Cannot sign in: "
                    "Backend.Creators.CasdoorAuth/exchange — "
                    f"{denied_reason}. Ask the Notechondria admin "
                    "to add your account to an allowed group on "
                    "the Casdoor side."
                )},
                status=status.HTTP_403_FORBIDDEN,
            )
        sub = _claim_str(claims, "CASDOOR_CLAIM_SUB")
        if not sub:
            return Response(
                {"detail": (
                    "Cannot sign in: "
                    "Backend.Creators.CasdoorAuth/exchange — "
                    "JWT does not carry an `id`/`sub` claim, so no "
                    "Notechondria account can be located."
                )},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Fast path: the Casdoor identity is already linked.
        user = _resolve_existing_user(claims)
        if user is not None:
            if not user.is_active:
                return Response(
                    {"detail": (
                        "Cannot sign in: "
                        "Backend.Creators.CasdoorAuth/exchange — "
                        "the linked Notechondria account is "
                        "inactive."
                    )},
                    status=status.HTTP_403_FORBIDDEN,
                )
            try:
                User.objects.filter(pk=user.pk).update(last_login=now())
            except Exception:  # noqa: BLE001
                pass
            # Refresh profile fields from the freshly-verified JWT
            # so the user's auth_payload reflects the latest Casdoor
            # state (avatar, displayName, first/last name, email).
            creator = ensure_creator(user)
            _sync_creator_from_claims(creator, claims)
            return Response(
                auth_payload(user, token=access_token, request=request)
            )

        # Slow path: the Casdoor identity is not linked yet — mint
        # a LinkChallenge and let the SPA prompt the user. Garbage-
        # collect any prior expired rows for the same sub so the
        # table doesn't grow unbounded if the user retries.
        from datetime import timedelta
        from django.utils import timezone
        from django.utils.crypto import get_random_string
        from .models import LinkChallenge

        LinkChallenge.objects.filter(
            sub=sub, expires_at__lt=timezone.now()
        ).delete()
        challenge = LinkChallenge.objects.create(
            nonce=get_random_string(48),
            sub=sub,
            casdoor_username=_claim_str(claims, "CASDOOR_CLAIM_USERNAME")[:150],
            casdoor_email=_claim_str(claims, "CASDOOR_CLAIM_EMAIL").lower()[:254],
            casdoor_display_name=_claim_str(
                claims, "CASDOOR_CLAIM_DISPLAY_NAME",
            )[:255],
            casdoor_groups=_claim_groups(claims),
            access_token=access_token,
            expires_at=timezone.now() + timedelta(minutes=10),
        )
        # Suggest a username candidate so the SPA can pre-fill the
        # bind dialog's username field. Fall back to the email's
        # local-part when the JWT didn't carry a usable username.
        suggested_username = challenge.casdoor_username
        if not suggested_username and challenge.casdoor_email:
            suggested_username = challenge.casdoor_email.split("@", 1)[0]
        return Response(
            {
                "link_challenge": challenge.nonce,
                "expires_at": challenge.expires_at.isoformat(),
                "casdoor_identity": {
                    "username": challenge.casdoor_username,
                    "email": challenge.casdoor_email,
                    "display_name": challenge.casdoor_display_name,
                },
                "suggested_username": suggested_username,
            }
        )


class CasdoorLinkBindApiView(APIView):
    """Complete a Casdoor link by binding the verified Casdoor `sub`
    to an existing Notechondria account. The user proves ownership
    of the legacy account by supplying its username (or email) +
    password; we authenticate via Django's standard hasher and, on
    success, stamp ``Creator.casdoor_sub = challenge.sub``.

    Errors keep the AGENTS.md §1.7 shape (consequence + module/
    process + cause) so the SPA dialog can surface a precise
    message without re-formulating.
    """

    permission_classes = [permissions.AllowAny]

    def post(self, request):
        from .models import Creator, LinkChallenge

        nonce = (request.data.get("nonce") or "").strip()
        identifier = (
            request.data.get("username")
            or request.data.get("email")
            or request.data.get("identifier")
            or ""
        ).strip()
        password = request.data.get("password") or ""
        if not nonce or not identifier or not password:
            return Response(
                {"detail": (
                    "Casdoor account binding aborted: "
                    "Backend.Creators.CasdoorAuth/link.bind — "
                    "nonce, username, and password are all required."
                )},
                status=status.HTTP_400_BAD_REQUEST,
            )
        challenge = LinkChallenge.objects.filter(nonce=nonce).first()
        if challenge is None or challenge.is_expired():
            if challenge is not None:
                challenge.delete()
            return Response(
                {"detail": (
                    "Casdoor account binding aborted: "
                    "Backend.Creators.CasdoorAuth/link.bind — "
                    "link challenge expired or unknown. Restart the "
                    "Casdoor sign-in flow to get a fresh ticket."
                )},
                status=status.HTTP_400_BAD_REQUEST,
            )
        # Refuse to bind if another Notechondria account already
        # carries this Casdoor sub (race between two parallel
        # exchanges, or a stale challenge whose target user
        # completed the link via a different surface).
        if Creator.objects.filter(casdoor_sub=challenge.sub).exists():
            challenge.delete()
            return Response(
                {"detail": (
                    "Casdoor account binding aborted: "
                    "Backend.Creators.CasdoorAuth/link.bind — "
                    "this Casdoor identity is already linked to "
                    "another Notechondria account. Sign in with "
                    "that account directly, or have an admin unlink "
                    "it first."
                )},
                status=status.HTTP_409_CONFLICT,
            )
        # Look up the legacy user case-insensitively by email then
        # username (matches the LoginSerializer pattern from 0.1.111).
        matched = User.objects.filter(email__iexact=identifier).first()
        if matched is None:
            matched = User.objects.filter(username__iexact=identifier).first()
        if matched is None:
            return Response(
                {"detail": (
                    "Casdoor account binding aborted: "
                    "Backend.Creators.CasdoorAuth/link.bind — "
                    "no Notechondria account found for the supplied "
                    "username/email."
                )},
                status=status.HTTP_401_UNAUTHORIZED,
            )
        user = authenticate(username=matched.username, password=password)
        if user is None or not user.is_active:
            return Response(
                {"detail": (
                    "Casdoor account binding aborted: "
                    "Backend.Creators.CasdoorAuth/link.bind — "
                    "username/email and password do not match an "
                    "active Notechondria account."
                )},
                status=status.HTTP_401_UNAUTHORIZED,
            )
        creator = ensure_creator(user)
        creator.casdoor_sub = challenge.sub
        creator.save(update_fields=["casdoor_sub"])
        # 0.1.119: refresh profile (display_name, avatar_url, first/
        # last name, email) from the captured JWT now that the link
        # is established. The token stored on the challenge is still
        # valid (<10 min old); re-verifying it gives us the full
        # claims dict without re-running the OAuth code exchange.
        from .casdoor_auth import _sync_creator_from_claims, verify_token
        link_claims = verify_token(challenge.access_token) or {}
        if link_claims:
            _sync_creator_from_claims(creator, link_claims)
        access_token = challenge.access_token
        challenge.delete()
        try:
            User.objects.filter(pk=user.pk).update(last_login=now())
        except Exception:  # noqa: BLE001
            pass
        logger.info(
            "Linked Casdoor identity to existing account: "
            "Backend.Creators.CasdoorAuth/link.bind — "
            "username=%s sub=%s.",
            user.username,
            challenge.sub[:12],
        )
        return Response(auth_payload(user, token=access_token, request=request))


class CasdoorLinkCreateApiView(APIView):
    """Complete a Casdoor link by creating a fresh Notechondria
    account using the user-chosen password. Username and email are
    drawn from the JWT claims captured on the LinkChallenge — the
    SPA cannot override them, so a malicious client can't pick an
    arbitrary email.

    Refuses (409) when a legacy account already exists for the
    Casdoor email/username; the SPA should redirect the user to
    the bind path instead.
    """

    permission_classes = [permissions.AllowAny]

    def post(self, request):
        from notes.services import seed_welcome_note
        from .models import Creator, LinkChallenge

        nonce = (request.data.get("nonce") or "").strip()
        password = request.data.get("password") or ""
        if not nonce or not password:
            return Response(
                {"detail": (
                    "Casdoor account creation aborted: "
                    "Backend.Creators.CasdoorAuth/link.create — "
                    "nonce and password are both required."
                )},
                status=status.HTTP_400_BAD_REQUEST,
            )
        challenge = LinkChallenge.objects.filter(nonce=nonce).first()
        if challenge is None or challenge.is_expired():
            if challenge is not None:
                challenge.delete()
            return Response(
                {"detail": (
                    "Casdoor account creation aborted: "
                    "Backend.Creators.CasdoorAuth/link.create — "
                    "link challenge expired or unknown. Restart the "
                    "Casdoor sign-in flow to get a fresh ticket."
                )},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if Creator.objects.filter(casdoor_sub=challenge.sub).exists():
            challenge.delete()
            return Response(
                {"detail": (
                    "Casdoor account creation aborted: "
                    "Backend.Creators.CasdoorAuth/link.create — "
                    "this Casdoor identity is already linked. Sign "
                    "in with the existing account instead."
                )},
                status=status.HTTP_409_CONFLICT,
            )
        # Block clobbering an existing legacy account by email — the
        # bind path is the right answer in that case.
        email = challenge.casdoor_email
        if email and User.objects.filter(email__iexact=email).exists():
            return Response(
                {"detail": (
                    "Casdoor account creation aborted: "
                    "Backend.Creators.CasdoorAuth/link.create — "
                    "a Notechondria account already exists for "
                    "this email. Use the bind option instead and "
                    "supply the legacy password."
                )},
                status=status.HTTP_409_CONFLICT,
            )
        # Pick a unique username. Prefer the Casdoor username claim
        # so the new account matches what the user sees on the
        # auth.trance-0.com side; fall back to the email's
        # local-part, then to a synthetic `casdoor_<sub>` so a
        # claim-less JWT doesn't blow up the create.
        raw_username = challenge.casdoor_username or (
            email.split("@", 1)[0] if email else ""
        ) or f"casdoor_{challenge.sub[:12]}"
        candidate = raw_username[:150]
        suffix = 0
        while User.objects.filter(username__iexact=candidate).exists():
            suffix += 1
            candidate = f"{raw_username[:145]}_{suffix}"

        # Display-name fields are best-effort — the create payload
        # doesn't carry them, and the JWT claims may or may not.
        display_name = challenge.casdoor_display_name
        first_name, _, last_name = display_name.partition(" ")

        user = User.objects.create(
            username=candidate,
            email=email or "",
            first_name=first_name[:30],
            last_name=last_name[:150],
            is_active=True,
        )
        user.set_password(password)
        user.save()
        creator = ensure_creator(user)
        creator.casdoor_sub = challenge.sub
        creator.save(update_fields=["casdoor_sub"])
        seed_welcome_note(creator)
        # 0.1.119: stamp display_name + avatar_url from the captured
        # JWT so the freshly-created account already shows the
        # Casdoor avatar / display-name on first paint instead of
        # waiting for the next refresh.
        from .casdoor_auth import _sync_creator_from_claims, verify_token
        link_claims = verify_token(challenge.access_token) or {}
        if link_claims:
            _sync_creator_from_claims(creator, link_claims)
        access_token = challenge.access_token
        challenge.delete()
        try:
            User.objects.filter(pk=user.pk).update(last_login=now())
        except Exception:  # noqa: BLE001
            pass
        logger.info(
            "Created Notechondria account from Casdoor link: "
            "Backend.Creators.CasdoorAuth/link.create — "
            "username=%s sub=%s.",
            candidate,
            challenge.sub[:12],
        )
        return Response(auth_payload(user, token=access_token, request=request))
