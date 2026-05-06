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


def _sync_creator_from_claims(creator, claims: dict) -> None:
    """Refresh a Creator's profile attributes from the verified
    Casdoor JWT claims. Mirrors Nextcloud user_oidc's
    `Sync user attributes on every login` pattern.

    Updates (skipping any claim that comes back empty so we never
    overwrite a meaningful local value with a blank IdP field):

    - ``Creator.display_name``  — `<CASDOOR_CLAIM_DISPLAY_NAME>`
    - ``Creator.avatar_url``    — `<CASDOOR_CLAIM_AVATAR>`
    - ``User.first_name``       — `<CASDOOR_CLAIM_GIVEN_NAME>`
    - ``User.last_name``        — `<CASDOOR_CLAIM_FAMILY_NAME>`
    - ``User.email``            — `<CASDOOR_CLAIM_EMAIL>`

    Deliberately **not** touched:

    - ``User.username`` — changing it breaks the Django ORM PK
      reference shape (every owner-keyed FK on courses, notes,
      attachments resolves through the username on the Casdoor
      side too) and external links to /api/v1/creators/<username>/.
      The username is set once at account creation and is stable
      for the lifetime of the account.
    - ``Creator.image`` (local upload) — left alone so a user who
      uploaded a custom avatar in Notechondria doesn't have it
      silently replaced by the Casdoor avatar. The SPA prefers
      `avatar_url` when set, otherwise falls back to `image`.

    Throttled at 5-minute granularity via
    ``casdoor_profile_synced_at`` — a busy SPA fires hundreds of
    JWT-authenticated requests during a session and we don't want
    each one writing to the DB. Within 5 minutes of the last
    sync, this is a no-op — *unless* the JWT was issued in the
    last ~60 seconds (its ``iat`` claim is fresh), which signals the
    user just signed in / refreshed the token and any avatar /
    display-name change on the Casdoor side should propagate
    immediately even if a sync ran a couple of minutes earlier.
    """
    from datetime import datetime, timedelta, timezone as dt_timezone
    from django.utils import timezone

    if creator is None:
        return
    last_sync = creator.casdoor_profile_synced_at
    now_utc = timezone.now()
    iat_claim = claims.get("iat") if isinstance(claims, dict) else None
    iat_dt: Optional[datetime] = None
    if isinstance(iat_claim, (int, float)):
        try:
            iat_dt = datetime.fromtimestamp(int(iat_claim), tz=dt_timezone.utc)
        except (OverflowError, OSError, ValueError):
            iat_dt = None
    fresh_token = iat_dt is not None and (now_utc - iat_dt) < timedelta(seconds=60)
    if (
        last_sync is not None
        and (now_utc - last_sync) < timedelta(minutes=5)
        and not fresh_token
    ):
        return

    user = creator.user_id
    user_dirty: list[str] = []
    creator_dirty: list[str] = []

    given = _claim_str(claims, "CASDOOR_CLAIM_GIVEN_NAME")
    if given and given[:30] != user.first_name:
        user.first_name = given[:30]
        user_dirty.append("first_name")
    family = _claim_str(claims, "CASDOOR_CLAIM_FAMILY_NAME")
    if family and family[:150] != user.last_name:
        user.last_name = family[:150]
        user_dirty.append("last_name")
    email = _claim_str(claims, "CASDOOR_CLAIM_EMAIL").lower()
    if email and email[:254] != (user.email or "").lower():
        user.email = email[:254]
        user_dirty.append("email")
    if user_dirty:
        try:
            user.save(update_fields=user_dirty)
        except Exception as exc:  # noqa: BLE001
            logger.warning(
                "User profile refresh from Casdoor JWT failed: "
                "Backend.Creators.CasdoorAuth/profile_sync — "
                "username=%s fields=%s cause=%s.",
                user.username,
                ",".join(user_dirty),
                exc,
            )

    display = _claim_str(claims, "CASDOOR_CLAIM_DISPLAY_NAME")
    if display and display[:255] != creator.display_name:
        creator.display_name = display[:255]
        creator_dirty.append("display_name")
    avatar = _claim_str(claims, "CASDOOR_CLAIM_AVATAR")
    if avatar and avatar[:512] != creator.avatar_url:
        creator.avatar_url = avatar[:512]
        creator_dirty.append("avatar_url")
    creator.casdoor_profile_synced_at = now_utc
    creator_dirty.append("casdoor_profile_synced_at")
    try:
        creator.save(update_fields=creator_dirty)
    except Exception as exc:  # noqa: BLE001
        logger.warning(
            "Creator profile refresh from Casdoor JWT failed: "
            "Backend.Creators.CasdoorAuth/profile_sync — "
            "username=%s fields=%s cause=%s.",
            user.username,
            ",".join(creator_dirty),
            exc,
        )


def _resolve_existing_user(claims: dict) -> Optional[User]:
    """Find the Django ``User`` whose Creator already carries the
    Casdoor `sub` from these claims, or return ``None`` to signal
    that the SPA must run the link-challenge flow (gitea-style:
    bind to a legacy account or create a new one with a
    user-chosen password).

    Auto-provisioning by sub and auto-linking by email address
    were retired in 0.1.118 — the user must explicitly choose
    bind-vs-create after the JWT verifies. See
    ``CasdoorExchangeApiView`` for the issuance side and
    ``CasdoorLinkBindApiView`` / ``CasdoorLinkCreateApiView``
    for the completion endpoints.
    """
    sub = _claim_str(claims, "CASDOOR_CLAIM_SUB")
    if not sub:
        return None

    creator = (
        Creator.objects.filter(casdoor_sub=sub)
        .select_related("user_id")
        .first()
    )
    if creator is not None:
        return creator.user_id
    return None


# Backwards-compat alias kept so older callers (e.g.
# `CasdoorExchangeApiView` between 0.1.96 and 0.1.117) that still
# import `_resolve_user` resolve to the new fast-path-only helper.
# The auto-provision side of the original 0.1.96 implementation
# now lives in `CasdoorLinkCreateApiView`.
_resolve_user = _resolve_existing_user


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
        # Refresh display_name / avatar_url / first_name / last_name /
        # email from the verified claims. Throttled at 5 minutes (see
        # `_sync_creator_from_claims`) so a busy SPA doesn't write to
        # the row on every JWT-authenticated request.
        creator = (
            Creator.objects.filter(user_id=user)
            .select_related("user_id")
            .first()
        )
        if creator is not None:
            _sync_creator_from_claims(creator, claims)
        request.casdoor_claims = claims  # downstream views can read it
        return (user, token)

    def authenticate_header(self, request):  # noqa: D401
        return self.keyword


__all__ = [
    "CasdoorJWTAuthentication",
    "verify_token",
]
