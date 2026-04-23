"""DRF exception handler: emits one AGENTS.md §1.7-shaped log line
for every authentication / permission / validation failure and lets
DRF's default handler build the HTTP response.

Why this exists:

* Django's built-in `django.request` logger already emits a generic
  ``WARNING 'Unauthorized: /api/v1/notes/'`` for every 401, which
  doesn't tell the operator which authentication class failed or why
  the token was rejected. We silence that (see settings.LOGGING) and
  emit a shaped line here instead.
* DRF's permission classes (`IsAuthenticated`, `IsAdminUser`, …)
  raise ``NotAuthenticated`` / ``PermissionDenied`` with very terse
  messages ("Authentication credentials were not provided.",
  "Invalid token."). We enrich the log with the request path, the
  configured auth classes, the bearer-token prefix (safe to log, 8
  chars), and the DRF detail string.

Message shape follows AGENTS.md §1.7 everywhere:

    "<consequence>: <module>/<process> — <cause>"

e.g.:

    Request rejected: Backend.Auth/permission_check — 401 on
    POST /api/v1/notes/ (cause: Invalid token.)
"""

import logging

from rest_framework.exceptions import (
    AuthenticationFailed,
    NotAuthenticated,
    PermissionDenied,
)
from rest_framework.views import exception_handler as drf_default_handler


logger = logging.getLogger("notechondria.auth")


def _auth_prefix(request) -> str:
    """Return the first 8 chars of the bearer token if present, so
    the log can point at which API key was rejected without leaking
    the full secret. Returns `"<none>"` when no Authorization header
    is supplied."""
    header = request.META.get("HTTP_AUTHORIZATION", "") if request else ""
    if not header:
        return "<none>"
    # Header shape: "Token <hex>" or "Bearer <hex>".
    parts = header.split(None, 1)
    if len(parts) != 2 or not parts[1]:
        return "<malformed>"
    return parts[1][:8] + "…"


def _path(request) -> str:
    if not request:
        return "<no-request>"
    try:
        return f"{request.method} {request.get_full_path()}"
    except Exception:
        return "<unreachable>"


def handle(exc, context):
    """Called by DRF for every unhandled exception raised inside a view.
    We always delegate response-building back to DRF's default handler;
    this wrapper exists only to emit a richer log line."""
    request = context.get("request") if isinstance(context, dict) else None

    if isinstance(exc, NotAuthenticated):
        logger.info(
            "Request rejected: Backend.Auth/permission_check \u2014 "
            "401 on %s (token=%s, cause: %s)",
            _path(request),
            _auth_prefix(request),
            getattr(exc, "detail", exc) or "missing credentials",
        )
    elif isinstance(exc, AuthenticationFailed):
        logger.info(
            "Request rejected: Backend.Auth/token_check \u2014 "
            "401 on %s (token=%s, cause: %s)",
            _path(request),
            _auth_prefix(request),
            getattr(exc, "detail", exc) or "invalid credentials",
        )
    elif isinstance(exc, PermissionDenied):
        logger.info(
            "Request rejected: Backend.Auth/permission_check \u2014 "
            "403 on %s (token=%s, cause: %s)",
            _path(request),
            _auth_prefix(request),
            getattr(exc, "detail", exc) or "insufficient permissions",
        )
    # Everything else (ValidationError, NotFound, ParseError, 5xx) is
    # already visible in the access log + Django's ERROR-level
    # django.request line for 5xx. We don't duplicate those here.

    return drf_default_handler(exc, context)
