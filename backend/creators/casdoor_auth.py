"""Casdoor JWT authentication for DRF.

Phase 2 of the Casdoor migration plan documented in
``docs/integrations/casdoor-migration.md``. Sits alongside
``creators.authentication.MultiSessionAuthentication`` in
``DEFAULT_AUTHENTICATION_CLASSES`` so existing legacy-token requests
keep working unchanged. The class is a no-op when ``CASDOOR_*``
settings are unset — fail open, return ``None``, let the next class
in the list decide.

Wire shape:

- Header: ``Authorization: Bearer <casdoor-jwt>``.
- The JWT is verified against ``settings.CASDOOR_CERTIFICATE`` (RS256)
  and the ``aud`` claim must match ``settings.CASDOOR_CLIENT_ID``.
- On first successful verification, the matching Django ``User`` is
  found by Casdoor's ``id`` (stored on ``Creator.casdoor_sub``);
  if no Creator carries the sub yet, fall back to the e-mail claim
  to let an existing legacy account adopt the link automatically.
- A new user is auto-provisioned when neither path finds a match,
  mirroring the OAuth login behaviour in ``_get_or_create_oauth_user``.

Errors keep the AGENTS.md §1.8 shape (consequence + module/process +
cause) so the auth-failure SnackBar copy stays diagnosable.
"""

from __future__ import annotations

import logging
from typing import Optional

from django.conf import settings
from django.contrib.auth.models import User
from django.utils.timezone import now
from rest_framework.authentication import BaseAuthentication
from rest_framework.exceptions import AuthenticationFailed

from .models import Creator
from .utils import ensure_creator

logger = logging.getLogger("django")


def _normalize_pem(pem: str) -> str:
    """Convert single-line escaped PEMs (``\\n`` literal) back to
    multi-line form. Idempotent — already-multi-line input is returned
    unchanged. Same shape as the helper in ``services/github_sync.py``."""
    if "\\n" in pem and "\n" not in pem:
        return pem.replace("\\n", "\n")
    return pem


def _build_sdk():
    """Return a configured ``casdoor.CasdoorSDK`` or ``None`` when env
    vars aren't populated. Cached on the module — Casdoor SDK objects
    are stateless config wrappers, safe to share across requests."""
    global _cached_sdk, _cached_sdk_signature
    sig = (
        settings.CASDOOR_ENDPOINT,
        settings.CASDOOR_CLIENT_ID,
        settings.CASDOOR_ORG_NAME,
        settings.CASDOOR_APP_NAME,
    )
    if not all(sig):
        return None
    if _cached_sdk is not None and _cached_sdk_signature == sig:
        return _cached_sdk
    try:
        from casdoor import CasdoorSDK  # local import keeps Django boot tolerant
        sdk = CasdoorSDK(
            endpoint=settings.CASDOOR_ENDPOINT,
            client_id=settings.CASDOOR_CLIENT_ID,
            client_secret=settings.CASDOOR_CLIENT_SECRET,
            certificate=_normalize_pem(settings.CASDOOR_CERTIFICATE),
            org_name=settings.CASDOOR_ORG_NAME,
            application_name=settings.CASDOOR_APP_NAME,
        )
    except Exception as exc:  # noqa: BLE001
        logger.warning(
            "Casdoor SDK unavailable: "
            "Backend.Creators.CasdoorAuth/build_sdk — %s.",
            exc,
        )
        return None
    _cached_sdk = sdk
    _cached_sdk_signature = sig
    return sdk


_cached_sdk = None
_cached_sdk_signature: tuple = ()


def verify_token(token: str) -> Optional[dict]:
    """Verify a Casdoor JWT and return its claims dict, or ``None``
    when verification fails or the SDK isn't configured. Never raises;
    the caller decides what to do with ``None``."""
    sdk = _build_sdk()
    if sdk is None:
        return None
    try:
        claims = sdk.parse_jwt_token(token)
    except Exception as exc:  # noqa: BLE001
        # parse_jwt_token raises for bad signature, expiry, audience
        # mismatch, etc. We log at INFO (a malformed/expired token is
        # an expected event) and let the caller fall through.
        logger.info(
            "Casdoor JWT rejected: "
            "Backend.Creators.CasdoorAuth/verify_token — %s.",
            exc,
        )
        return None
    if not isinstance(claims, dict):
        return None
    return claims


def _resolve_user(claims: dict) -> Optional[User]:
    """Find or create the Django ``User`` matching this Casdoor JWT.

    Resolution order:
      1. ``Creator.casdoor_sub == claims['id' | 'sub']`` — the
         post-cutover hot path; one DB hit when the link is already
         persisted.
      2. ``User.email iexact claims['email']`` — first-time link for
         an existing legacy account; on success we backfill
         ``Creator.casdoor_sub`` so subsequent requests take path 1.
      3. Auto-provision a new ``User`` + ``Creator`` and stamp the sub.
         Mirrors ``_get_or_create_oauth_user`` in ``creators.api``.
    """
    sub = (claims.get("id") or claims.get("sub") or "").strip()
    if not sub:
        return None

    creator = Creator.objects.filter(casdoor_sub=sub).select_related("user_id").first()
    if creator is not None:
        return creator.user_id

    email = (claims.get("email") or "").strip().lower()
    if email:
        existing = User.objects.filter(email__iexact=email).first()
        if existing is not None:
            ensure_creator(existing)
            existing.creator_set.update(casdoor_sub=sub)
            return existing

    # Auto-provision. Casdoor's `name` field is its username; fall
    # back to the email local-part when missing.
    raw_username = (claims.get("name") or claims.get("preferred_username") or "").strip()
    if not raw_username and email:
        raw_username = email.split("@", 1)[0]
    if not raw_username:
        raw_username = f"casdoor_{sub[:12]}"
    candidate = raw_username[:150]
    suffix = 0
    while User.objects.filter(username__iexact=candidate).exists():
        suffix += 1
        candidate = f"{raw_username[:145]}_{suffix}"
    user = User.objects.create(
        username=candidate,
        email=email or "",
        first_name=(claims.get("firstName") or claims.get("given_name") or "")[:30],
        last_name=(claims.get("lastName") or claims.get("family_name") or "")[:150],
        is_active=True,
    )
    user.set_unusable_password()
    user.save()
    creator = ensure_creator(user)
    creator.casdoor_sub = sub
    creator.save(update_fields=["casdoor_sub"])
    logger.info(
        "Auto-provisioned user from Casdoor JWT: "
        "Backend.Creators.CasdoorAuth/auto_provision — username=%s sub=%s.",
        candidate,
        sub[:12],
    )
    return user


class CasdoorJWTAuthentication(BaseAuthentication):
    """Validate a ``Bearer <casdoor-jwt>`` Authorization header against
    the configured Casdoor instance. Returns ``None`` (silently)
    when:

    - the SDK isn't configured (no env vars set), so the next
      authentication class in DRF's chain can try the same header;
    - the header isn't ``Bearer ...`` shape;
    - the token is missing or empty.

    Raises ``AuthenticationFailed`` only when the Bearer token is
    *present and structurally valid* but Casdoor explicitly rejects
    it (signature, audience, or expiry mismatch). That mirrors DRF's
    "don't silently downgrade a bad token" convention from
    ``rest_framework.authentication.TokenAuthentication``.
    """

    keyword = "Bearer"

    def authenticate(self, request):
        sdk = _build_sdk()
        if sdk is None:
            return None  # shadow mode disabled

        auth_header = request.META.get("HTTP_AUTHORIZATION", "") or ""
        parts = auth_header.split(None, 1)
        if len(parts) != 2 or parts[0].lower() != self.keyword.lower():
            return None
        token = parts[1].strip()
        if not token:
            return None
        # Defensive: MCP API keys also use the Bearer scheme but start
        # with `ntc_`. Hand them off to ApiKeyAuthentication unchanged.
        if token.startswith("ntc_"):
            return None

        claims = verify_token(token)
        if claims is None:
            raise AuthenticationFailed(
                "Cannot sign in: "
                "Backend.Creators.CasdoorAuth/authenticate — "
                "JWT verification failed (signature, audience, or "
                "expiry mismatch). Sign in again to refresh the token."
            )

        user = _resolve_user(claims)
        if user is None:
            raise AuthenticationFailed(
                "Cannot sign in: "
                "Backend.Creators.CasdoorAuth/authenticate — "
                "JWT is valid but does not carry an `id` / `sub` "
                "claim, so no Notechondria account can be located."
            )
        if not user.is_active:
            raise AuthenticationFailed(
                "Cannot sign in: "
                "Backend.Creators.CasdoorAuth/authenticate — "
                "the resolved Notechondria account is inactive."
            )
        # Stamp last_login so legacy 'who signed in recently' UIs keep
        # working. Cheap; one UPDATE per authenticated request.
        try:
            User.objects.filter(pk=user.pk).update(last_login=now())
        except Exception:  # noqa: BLE001
            pass
        request.casdoor_claims = claims  # downstream views can read it
        return (user, token)

    def authenticate_header(self, request):  # noqa: D401
        return self.keyword


__all__ = [
    "CasdoorJWTAuthentication",
    "verify_token",
]
