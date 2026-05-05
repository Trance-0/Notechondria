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
  mirroring the email-verify seeding flow in ``creators.api``.

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


def _split_csv(raw: str) -> list[str]:
    """Parse a comma-separated env-var value into a list, trimming
    whitespace and dropping empties. Idempotent for already-clean input."""
    return [piece.strip() for piece in (raw or "").split(",") if piece.strip()]


def _claim_str(claims: dict, setting_name: str) -> str:
    """Read the first non-empty string claim listed in
    ``settings.<setting_name>``. Lets the operator remap the JWT
    Token Format tab in Casdoor (preferred_username vs name vs uid)
    without code changes — see ``CASDOOR_CLAIM_*`` in settings.py."""
    keys = _split_csv(getattr(settings, setting_name, ""))
    for key in keys:
        value = claims.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def _claim_groups(claims: dict) -> list[str]:
    """Read the JWT array claim listed in ``CASDOOR_CLAIM_GROUPS`` and
    return it as a list of strings. Tolerant of three Casdoor shapes:
    a single string, a list of strings, or a list of `{name: ...}`
    objects. Returns ``[]`` for any other shape so the caller's group
    check fails closed when the claim is missing."""
    keys = _split_csv(getattr(settings, "CASDOOR_CLAIM_GROUPS", ""))
    for key in keys:
        value = claims.get(key)
        if value is None:
            continue
        if isinstance(value, str):
            return [value] if value.strip() else []
        if isinstance(value, (list, tuple)):
            out: list[str] = []
            for item in value:
                if isinstance(item, str):
                    if item.strip():
                        out.append(item.strip())
                elif isinstance(item, dict):
                    name = item.get("name") or item.get("displayName") or ""
                    if isinstance(name, str) and name.strip():
                        out.append(name.strip())
            return out
    return []


def _check_group_access(claims: dict) -> Optional[str]:
    """Return None if the user's groups include at least one of the
    configured ``CASDOOR_REQUIRED_GROUPS``, or if the setting is
    empty (no gating). Otherwise return a human-readable rejection
    reason for the AuthenticationFailed message. Modeled on the
    Nextcloud user_oidc plugin's "Restrict login to a list of
    groups" toggle."""
    required = _split_csv(getattr(settings, "CASDOOR_REQUIRED_GROUPS", ""))
    if not required:
        return None  # gating disabled
    user_groups = set(_claim_groups(claims))
    if user_groups.intersection(required):
        return None
    # Compose a precise log-friendly reason. Don't echo the user's
    # full group list to error messages (could leak unrelated org
    # memberships); just say which groups would have been accepted.
    return (
        f"user is not a member of any required group "
        f"({', '.join(required)})"
    )


def _resolve_user(claims: dict) -> Optional[User]:
    """Find or create the Django ``User`` matching this Casdoor JWT.

    Resolution order:
      1. ``Creator.casdoor_sub == <CASDOOR_CLAIM_SUB>`` — the
         post-cutover hot path; one DB hit when the link is already
         persisted.
      2. ``User.email iexact <CASDOOR_CLAIM_EMAIL>`` — first-time
         link for an existing legacy account; on success we backfill
         ``Creator.casdoor_sub`` so subsequent requests take path 1.
      3. Auto-provision a new ``User`` + ``Creator``, stamp the sub,
         and seed the inbox + welcome note (same shape as the
         email-verify registration flow in ``creators.api``).

    All claim names are read from ``settings.CASDOOR_CLAIM_*`` so the
    Casdoor app's Token Format tab can be reshaped by the operator
    without re-deploying code.
    """
    sub = _claim_str(claims, "CASDOOR_CLAIM_SUB")
    if not sub:
        return None

    creator = Creator.objects.filter(casdoor_sub=sub).select_related("user_id").first()
    if creator is not None:
        return creator.user_id

    # Lazy import to avoid the notes <-> creators app boot cycle.
    from notes.services import seed_inbox_and_welcome_note

    email = _claim_str(claims, "CASDOOR_CLAIM_EMAIL").lower()
    if email:
        existing = User.objects.filter(email__iexact=email).first()
        if existing is not None:
            existing_creator = ensure_creator(existing)
            existing.creator_set.update(casdoor_sub=sub)
            # Idempotent — protects legacy accounts that predate the
            # email-verify / OAuth onboarding seed and would otherwise
            # land on an empty editor sidebar.
            seed_inbox_and_welcome_note(existing_creator)
            return existing

    # Auto-provision. Username comes from CASDOOR_CLAIM_USERNAME (e.g.
    # `preferred_username`), display-name parts from
    # CASDOOR_CLAIM_DISPLAY_NAME / GIVEN_NAME / FAMILY_NAME. Fall back
    # to the email local-part when no username claim is present.
    raw_username = _claim_str(claims, "CASDOOR_CLAIM_USERNAME")
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
        first_name=_claim_str(claims, "CASDOOR_CLAIM_GIVEN_NAME")[:30],
        last_name=_claim_str(claims, "CASDOOR_CLAIM_FAMILY_NAME")[:150],
        is_active=True,
    )
    user.set_unusable_password()
    user.save()
    creator = ensure_creator(user)
    creator.casdoor_sub = sub
    creator.save(update_fields=["casdoor_sub"])
    # Match the email-verify and OAuth-register flows so every newly
    # provisioned user lands on a non-empty workspace (Inbox + welcome
    # note). Without this, Casdoor users hit an empty editor sidebar
    # because /api/v1/courses/ returns no rows on first load.
    seed_inbox_and_welcome_note(creator)
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
        if len(parts) != 2:
            return None
        scheme = parts[0].lower()
        token = parts[1].strip()
        if not token:
            return None
        # Accept both `Bearer <jwt>` (the OAuth standard, used by all
        # current SPA builds since 0.1.117) and `Token <jwt>` (the
        # legacy scheme older SPA builds in the wild send because
        # the original DRF authtoken plumbing always wrote `Token
        # <hex>`). For non-JWT shapes (DRF authtoken hex), let the
        # stock `TokenAuthentication` handle the `Token` scheme;
        # for `Bearer ntc_...` MCP keys, hand off to
        # `ApiKeyAuthentication`. Detect a JWT cheaply by the
        # `eyJ` base64 prefix that every JWS header produces.
        if scheme not in ("bearer", "token"):
            return None
        if scheme == "token" and not token.startswith("eyJ"):
            return None  # leave DRF hex tokens for stock TokenAuthentication
        if token.startswith("ntc_"):
            return None  # leave MCP API keys for ApiKeyAuthentication

        claims = verify_token(token)
        if claims is None:
            raise AuthenticationFailed(
                "Cannot sign in: "
                "Backend.Creators.CasdoorAuth/authenticate — "
                "JWT verification failed (signature, audience, or "
                "expiry mismatch). Sign in again to refresh the token."
            )

        # Group-based ACL gate. When CASDOOR_REQUIRED_GROUPS is empty
        # this returns None and we fall through; otherwise the JWT
        # must carry at least one matching group in the configured
        # groups claim or auth is rejected. Mirrors the Nextcloud
        # user_oidc "Restrict login to a list of groups" toggle.
        denied_reason = _check_group_access(claims)
        if denied_reason is not None:
            logger.info(
                "Casdoor JWT rejected by group ACL: "
                "Backend.Creators.CasdoorAuth/authenticate — %s.",
                denied_reason,
            )
            raise AuthenticationFailed(
                "Cannot sign in: "
                "Backend.Creators.CasdoorAuth/authenticate — "
                f"{denied_reason}. Ask the Notechondria admin to add "
                "your account to an allowed group on the Casdoor side."
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
