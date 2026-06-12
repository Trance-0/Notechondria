"""Casdoor -> Django password synchronization.

Keeps the permanent email/password fallback login
(``LoginApiView``, restored in 0.1.111 for Casdoor outages) working
with the user's *current* Casdoor password. Two complementary paths:

1. ``sync_password_from_claims`` — the operator configured Casdoor's
   application Token Format as JWT-Custom with the ``Password``,
   ``Password salt`` and ``Password type`` token fields, so a verified
   JWT can carry the credential hash. When the claims are present and
   non-empty we mirror them into ``User.password``. NOTE: current
   Casdoor builds scrub the ``password`` claim server-side (verified
   against auth.trance-0.com on 2026-06-12: the claim key exists but
   its value is empty while ``passwordType`` says ``bcrypt``), so this
   path is dormant until the IdP starts emitting the hash. It costs
   one dict lookup per profile sync, and activates automatically.

2. ``password_grant`` — Resource Owner Password Credentials grant
   against Casdoor's ``/api/login/oauth/access_token``. Used by the
   fallback login view: when the submitted password does not match the
   local hash, the backend asks Casdoor directly; on success (and a
   ``sub`` match against ``Creator.casdoor_sub``) the caller stores
   the verified plaintext via ``set_password``. Network failures are
   reported distinctly from credential rejections so the caller can
   keep treating the local hash as the offline source of truth.

Security note: this module never logs password material — neither
plaintext, hashes, salts, nor raw tokens.
"""

from __future__ import annotations

import logging
from typing import Optional, Tuple

from django.conf import settings

logger = logging.getLogger("django")

#: ``password_grant`` outcome markers.
GRANT_OK = "ok"
GRANT_REJECTED = "rejected"
GRANT_UNREACHABLE = "unreachable"
GRANT_DISABLED = "disabled"


def _claim_value(claims: dict, setting_name: str, default_key: str) -> str:
    """Read a claim by the (comma-separated) names configured in
    ``settings.<setting_name>``, falling back to ``default_key``."""
    raw = getattr(settings, setting_name, "") or default_key
    for key in [piece.strip() for piece in raw.split(",") if piece.strip()]:
        value = claims.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def sync_password_from_claims(user, claims: dict) -> bool:
    """Mirror the Casdoor credential hash claims into ``User.password``.

    Returns True when the local password was updated. Supported
    ``passwordType`` values:

    - ``plain``  — the claim carries the plaintext; stored via
      ``set_password`` (PBKDF2, Django default hasher).
    - ``bcrypt`` — the claim carries a ``$2a$/$2b$/$2y$`` bcrypt hash;
      stored as ``bcrypt$<hash>`` for
      ``django.contrib.auth.hashers.BCryptPasswordHasher`` (enabled in
      ``settings.PASSWORD_HASHERS``; needs the ``bcrypt`` package).

    Any other type is logged once per sync attempt and skipped — do
    not guess at Casdoor's salted-digest recipes without a reference
    hash to verify against.
    """
    if user is None or not isinstance(claims, dict):
        return False
    password_value = _claim_value(
        claims, "CASDOOR_CLAIM_PASSWORD", "password"
    )
    if not password_value:
        # Dormant path: Casdoor scrubbed the hash (see module docstring).
        return False
    password_type = _claim_value(
        claims, "CASDOOR_CLAIM_PASSWORD_TYPE", "passwordType"
    ).lower()

    if password_type in ("", "plain"):
        new_encoded = None  # plaintext — use set_password below
    elif password_type == "bcrypt":
        if not password_value.startswith("$2"):
            logger.warning(
                "Password fallback not synced: "
                "Backend.Creators.CasdoorPassword/claims_sync — "
                "passwordType=bcrypt but the claim value is not a "
                "bcrypt hash shape; skipping."
            )
            return False
        new_encoded = "bcrypt$" + password_value
    else:
        logger.warning(
            "Password fallback not synced: "
            "Backend.Creators.CasdoorPassword/claims_sync — "
            "unsupported Casdoor passwordType=%r (supported: plain, "
            "bcrypt). The email/password fallback keeps using the "
            "previously stored local hash.",
            password_type,
        )
        return False

    try:
        if new_encoded is None:
            if user.check_password(password_value):
                return False  # already in sync; skip the write
            user.set_password(password_value)
        else:
            if user.password == new_encoded:
                return False
            user.password = new_encoded
        user.save(update_fields=["password"])
    except Exception as exc:  # noqa: BLE001
        logger.warning(
            "Password fallback not synced: "
            "Backend.Creators.CasdoorPassword/claims_sync — "
            "storing the synced credential failed for username=%s: %s.",
            getattr(user, "username", "?"),
            exc,
        )
        return False
    logger.info(
        "Password fallback synced from Casdoor JWT claims: "
        "Backend.Creators.CasdoorPassword/claims_sync — "
        "username=%s passwordType=%s.",
        user.username,
        password_type or "plain",
    )
    return True


def password_grant(identifier: str, password: str) -> Tuple[str, Optional[dict]]:
    """Try Casdoor's ROPC grant with the submitted credentials.

    Returns ``(GRANT_OK, verified_claims)`` on success;
    ``(GRANT_REJECTED, None)`` when Casdoor answered but refused the
    credentials; ``(GRANT_UNREACHABLE, None)`` on timeout / connection
    error / 5xx (the Casdoor-outage case the fallback login exists
    for); ``(GRANT_DISABLED, None)`` when CASDOOR_* env vars are not
    configured.
    """
    from .casdoor_auth import verify_token

    endpoint = (getattr(settings, "CASDOOR_ENDPOINT", "") or "").rstrip("/")
    client_id = getattr(settings, "CASDOOR_CLIENT_ID", "") or ""
    client_secret = getattr(settings, "CASDOOR_CLIENT_SECRET", "") or ""
    if not endpoint or not client_id:
        return GRANT_DISABLED, None

    import requests

    try:
        response = requests.post(
            endpoint + "/api/login/oauth/access_token",
            data={
                "grant_type": "password",
                "client_id": client_id,
                "client_secret": client_secret,
                "username": identifier,
                "password": password,
            },
            timeout=8,
        )
    except requests.RequestException as exc:
        logger.warning(
            "Casdoor unreachable during password fallback: "
            "Backend.Creators.CasdoorPassword/password_grant — %s. "
            "Falling back to the locally stored hash.",
            type(exc).__name__,
        )
        return GRANT_UNREACHABLE, None

    if response.status_code >= 500:
        logger.warning(
            "Casdoor unreachable during password fallback: "
            "Backend.Creators.CasdoorPassword/password_grant — "
            "HTTP %s from the token endpoint. Falling back to the "
            "locally stored hash.",
            response.status_code,
        )
        return GRANT_UNREACHABLE, None

    try:
        body = response.json()
    except ValueError:
        return GRANT_REJECTED, None
    access_token = body.get("access_token") if isinstance(body, dict) else None
    if not access_token:
        # Casdoor returns 200 with {"error": ...} for bad credentials.
        return GRANT_REJECTED, None
    claims = verify_token(access_token)
    if claims is None:
        logger.warning(
            "Casdoor password grant returned an unverifiable token: "
            "Backend.Creators.CasdoorPassword/password_grant — "
            "JWT signature/audience check failed; treating as rejected."
        )
        return GRANT_REJECTED, None
    return GRANT_OK, claims


__all__ = [
    "GRANT_DISABLED",
    "GRANT_OK",
    "GRANT_REJECTED",
    "GRANT_UNREACHABLE",
    "password_grant",
    "sync_password_from_claims",
]
