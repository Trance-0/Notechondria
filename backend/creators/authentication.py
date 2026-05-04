"""Custom DRF authentication backends.

``ApiKeyAuthentication``
    Long-lived per-creator API keys used by the MCP server:
    ``Authorization: Bearer ntc_<32-hex>``. Lookup hashes the key
    and matches ``Creator.api_key_hash``.

The legacy ``MultiSessionAuthentication`` was removed in 0.1.106 along
with the ``creators.Session`` model — Casdoor JWTs are now the only
user-facing credential, validated by
``creators.casdoor_auth.CasdoorJWTAuthentication``.
"""

import hashlib

from rest_framework.authentication import BaseAuthentication
from rest_framework.exceptions import AuthenticationFailed

from .models import Creator

API_KEY_PREFIX = "ntc_"


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
