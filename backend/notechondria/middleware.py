import logging
import sys
import time
from urllib.parse import urlparse

from django.conf import settings
from django.http import HttpResponse

_access_logger = logging.getLogger("notechondria.access")


class _AnsiColor:
    """ANSI SGR color codes. Emitted only when the access log's destination
    is a TTY; otherwise the colors are suppressed so we don't splatter
    escape sequences into Jenkins/Render/Northflank captured stdout."""

    RESET = "\x1b[0m"
    BOLD = "\x1b[1m"
    DIM = "\x1b[2m"
    CYAN = "\x1b[36m"   # INFO — 2xx under threshold
    YELLOW = "\x1b[33m"  # WARNING — 3xx/4xx, or slow 2xx
    RED = "\x1b[31m"    # CRITICAL — 5xx, or very slow anything
    MAGENTA = "\x1b[35m"  # HTTP method highlight


def _stdout_is_tty() -> bool:
    try:
        return sys.stdout.isatty()
    except Exception:
        return False


# Cache TTY detection once at import time. If operators want colors in
# captured logs anyway they can set DJANGO_ACCESS_LOG_FORCE_COLOR=1.
_COLOR_ENABLED = (
    _stdout_is_tty()
    or str(
        __import__("os").environ.get("DJANGO_ACCESS_LOG_FORCE_COLOR", "")
    ).strip().lower()
    in {"1", "true", "yes"}
)


def _paint(text: str, color: str) -> str:
    if not _COLOR_ENABLED:
        return text
    return f"{color}{text}{_AnsiColor.RESET}"


# Duration thresholds (ms) for slow-response flagging. A slow response
# is still INFO-level (the request succeeded), but duration >= _SLOW_MS
# adds a colored duration field so operators skimming logs can spot it.
# We no longer promote slow 2xx to WARNING/CRITICAL — a slow 200 is not
# a failure, it's a perf signal, and mixing the two creates false alerts.
_SLOW_MS = 500.0
_VERY_SLOW_MS = 2000.0


def _level_for(status: int) -> tuple[str, str]:
    """Pick `(log_level, color)` from HTTP status.

    The only signal here is "did the request fail?" — 5xx is a real
    server problem, 4xx is a client-or-auth problem (noise-level, not
    an alert), 3xx and 2xx are success. Duration colors the row
    separately without changing the level.
    """
    if status >= 500:
        return "error", _AnsiColor.RED
    if status >= 400:
        # 401/403/404/429 are routine on a public API and belong at
        # INFO level — the frontend retries authenticated calls and
        # produces its own shaped log for every permanent failure.
        # Operators who want every 4xx highlighted can grep ` 4\d\d `.
        return "info", _AnsiColor.YELLOW
    return "info", _AnsiColor.CYAN


class RequestTimingMiddleware:
    """Time every HTTP request and log the result under
    `notechondria.access`.

    Format (tab-separated for grep-friendliness, colored for humans):

        <status> <duration_ms>ms <METHOD> <path>

    Level picking:
      * 5xx                 → logger.error    + red status
      * 4xx                 → logger.info     + yellow status
      * 2xx / 3xx           → logger.info     + cyan status

    Duration is colored independently: >= _VERY_SLOW_MS in red,
    >= _SLOW_MS in yellow, otherwise the status color. This keeps
    level = failure-signal and color = perf-signal cleanly separated,
    which is what the operator wants when skimming prod logs.
    """

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        start = time.monotonic()
        response = self.get_response(request)
        duration_ms = (time.monotonic() - start) * 1000.0

        status = getattr(response, "status_code", 0)
        method = request.method or "?"
        path = (
            request.get_full_path()
            if hasattr(request, "get_full_path")
            else request.path
        )

        level, status_color = _level_for(status)
        if duration_ms >= _VERY_SLOW_MS:
            duration_color = _AnsiColor.RED
        elif duration_ms >= _SLOW_MS:
            duration_color = _AnsiColor.YELLOW
        else:
            duration_color = status_color

        log = getattr(_access_logger, level)
        status_text = _paint(f"{status}", status_color + _AnsiColor.BOLD)
        duration_text = _paint(f"{duration_ms:7.1f}ms", duration_color)
        method_text = _paint(f"{method:<6}", _AnsiColor.MAGENTA)
        log("%s  %s  %s %s", status_text, duration_text, method_text, path)

        return response


class ApiCorsMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        is_cors_path = request.path.startswith("/api/") or request.path.startswith("/media/")
        origin = request.headers.get("Origin", "")

        if is_cors_path and request.method == "OPTIONS":
            response = HttpResponse(status=204)
        else:
            response = self.get_response(request)

        if not is_cors_path or not origin:
            return response

        if self._is_allowed_origin(origin):
            response["Access-Control-Allow-Origin"] = origin
            response["Access-Control-Allow-Credentials"] = "true"
            response["Access-Control-Allow-Headers"] = "Authorization, Content-Type, Accept, Origin, X-Requested-With"
            response["Access-Control-Allow-Methods"] = "GET, POST, PATCH, PUT, DELETE, OPTIONS"
            response["Vary"] = "Origin"

        return response

    @staticmethod
    def _is_allowed_origin(origin: str) -> bool:
        parsed = urlparse(origin)
        host = parsed.hostname or ""
        if host in {"localhost", "127.0.0.1"}:
            return True
        if host in settings.ALLOWED_HOSTS:
            return True
        # Check CSRF_TRUSTED_ORIGINS for cross-origin frontend deployments
        # (e.g. GitHub Pages frontend talking to Render backend)
        for trusted in getattr(settings, "CSRF_TRUSTED_ORIGINS", []):
            trusted_parsed = urlparse(trusted)
            if trusted_parsed.hostname == host:
                return True
        return False
