"""Custom DRF authentication backends.

Two classes live here:

``MultiSessionAuthentication``
    The default session-based auth: ``Authorization: Token <40-hex>``.
    Replaces ``rest_framework.authtoken.TokenAuthentication`` so a user
    can have many concurrent sessions (one per device) with explicit
    idle + absolute timeouts. See ``creators.models.Session``.

``ApiKeyAuthentication``
    Long-lived per-creator API keys used by the MCP server:
    ``Authorization: Bearer ntc_<32-hex>``. Unchanged from the
    earlier revision — lookup hashes the key and matches
    ``Creator.api_key_hash``.
"""

import hashlib

from rest_framework.authentication import BaseAuthentication
from rest_framework.exceptions import AuthenticationFailed

from .models import Creator, Session

API_KEY_PREFIX = "ntc_"


class MultiSessionAuthentication(BaseAuthentication):
    """Token-based auth backed by ``creators.Session`` (multi-device).

    Wire shape is the same as DRF's built-in TokenAuthentication:
    ``Authorization: Token <40-hex-chars>``. The difference is on the
    server side — we look up a ``Session`` row, enforce idle +
    absolute timeouts, and update ``last_seen_at`` on every valid
    request so the idle window rolls forward.

    This class returns ``None`` (instead of raising) when the
    header is missing or not a ``Token`` header, so downstream
    auth classes (e.g. ApiKeyAuthentication) can still match. It
    only raises ``AuthenticationFailed`` when a ``Token`` header
    IS present but the key is unknown, expired, or revoked —
    mirroring DRF's opinionated "don't silently downgrade" default.
    """

    keyword = "Token"

    def authenticate(self, request):
        auth_header = request.META.get("HTTP_AUTHORIZATION", "") or ""
        parts = auth_header.split(None, 1)
        if len(parts) != 2 or parts[0].lower() != self.keyword.lower():
            return None  # Not a Token request — let other backends try.

        key = parts[1].strip()
        if not key:
            raise AuthenticationFailed("Invalid token header. No credentials provided.")
        if len(key) > 40:
            # A too-long key can't match our 40-char column, and
            # `Session.objects.get(key=...)` would just DoesNotExist
            # anyway. Raise a clean error instead of letting the ORM
            # do a pointless query.
            raise AuthenticationFailed("Invalid token.")

        try:
            session = Session.objects.select_related("user").get(key=key)
        except Session.DoesNotExist:
            raise AuthenticationFailed("Invalid token.")

        if not session.is_active():
            # Either revoked or timed out. Don't leak which one in the
            # error body — both are "please log in again" from the
            # client's perspective.
            raise AuthenticationFailed("Invalid token.")

        user = session.user
        if not user.is_active:
            raise AuthenticationFailed("User account is disabled.")

        # Roll the idle window forward. One UPDATE per request; cheap.
        session.touch()

        # Attach the session for downstream views (e.g. LogoutApiView
        # wants to revoke THIS session, not all of the user's).
        request.auth_session = session
        return (user, session)

    def authenticate_header(self, request):
        return self.keyword


class ApiKeyAuthentication(BaseAuthentication):
    """Authenticate requests using a Notechondria API key (``ntc_...``)."""

    keyword = "Bearer"

    def authenticate(self, request):
        auth_header = request.META.get("HTTP_AUTHORIZATION", "")
        if not auth_header.startswith(f"{self.keyword} {API_KEY_PREFIX}"):
            return None  # Not an API-key request — let other backends try.

        raw_key = auth_header[len(self.keyword) + 1 :]  # everything after "Bearer "
        if not raw_key.startswith(API_KEY_PREFIX):
            return None

        key_hash = hashlib.sha256(raw_key.encode()).hexdigest()
        try:
            creator = Creator.objects.select_related("user_id").get(
                api_key_hash=key_hash,
            )
        except Creator.DoesNotExist:
            raise AuthenticationFailed("Invalid API key.")

        user = creator.user_id
        if not user.is_active:
            raise AuthenticationFailed("User account is disabled.")

        # Attach the creator for downstream views.
        request.creator = creator
        return (user, raw_key)

    def authenticate_header(self, request):
        return f'{self.keyword} realm="api"'
