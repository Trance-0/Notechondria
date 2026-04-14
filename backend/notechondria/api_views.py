import logging
import os
from pathlib import Path
from typing import Optional
from urllib.parse import urlencode

import requests as http_requests
from django.conf import settings
from django.http import (
    Http404,
    HttpResponse,
    HttpResponseBadRequest,
    HttpResponseForbidden,
    HttpResponseNotFound,
    HttpResponseServerError,
    JsonResponse,
)
from django.views.decorators.http import require_GET

logger = logging.getLogger("django")

HANDSHAKE_SERVICE_ID = "notechondria-backend"
HANDSHAKE_API_VERSION = "v1"
# Capabilities the frontend can feature-flag against. Bump an entry (or add
# a new one) when the shape of an endpoint or a response payload changes in
# a way that old clients cannot parse.
HANDSHAKE_CAPABILITIES = {
    "auth": 1,
    "notes": 1,
    "courses": 1,
    "planner": 1,
    "calendar_feeds": 1,
    "attachments": 1,
    "mcp": 1,
}

_cached_backend_version: Optional[str] = None


def _read_backend_version() -> str:
    global _cached_backend_version
    if _cached_backend_version is not None:
        return _cached_backend_version
    candidate = Path(settings.BASE_DIR).parent / "VERSION"
    try:
        _cached_backend_version = candidate.read_text(encoding="utf-8").strip() or "0.0.0"
    except OSError:
        _cached_backend_version = "0.0.0"
    return _cached_backend_version


def health_check(request):
    return JsonResponse({"status": "ok", "service": HANDSHAKE_SERVICE_ID})


@require_GET
def handshake(request):
    """Identify this backend to a client that just pointed at a new API URL.

    Frontends (editor/planner/portal) call GET /api/v1/handshake/ whenever the
    user edits the API base URL in Settings. A correct response proves two
    things: (a) the URL really is a Notechondria backend and not a random
    server, and (b) the client's capability expectations are compatible with
    the server's. If `service` doesn't match HANDSHAKE_SERVICE_ID or
    `api_version` doesn't match HANDSHAKE_API_VERSION, the frontend refuses
    to switch.
    """
    return JsonResponse(
        {
            "service": HANDSHAKE_SERVICE_ID,
            "api_version": HANDSHAKE_API_VERSION,
            "version": _read_backend_version(),
            "capabilities": HANDSHAKE_CAPABILITIES,
        }
    )


def _api_error_response(request, message, status_code):
    if request.path.startswith("/api/"):
        return JsonResponse(
            {
                "detail": message,
                "status_code": status_code,
                "path": request.path,
            },
            status=status_code,
        )
    return None


def api_bad_request(request, exception):
    response = _api_error_response(request, "Bad request.", 400)
    if response is not None:
        return response
    return HttpResponseBadRequest("Bad request.")


def api_permission_denied(request, exception):
    response = _api_error_response(request, "Permission denied.", 403)
    if response is not None:
        return response
    return HttpResponseForbidden("Permission denied.")


def api_page_not_found(request, exception):
    response = _api_error_response(request, "API route not found.", 404)
    if response is not None:
        return response
    return HttpResponseNotFound("Page not found.")


def api_server_error(request):
    response = _api_error_response(request, "Internal server error.", 500)
    if response is not None:
        return response
    return HttpResponseServerError("Internal server error.")


def _oauth_result_page(title, message, success=True):
    """Return a minimal HTML page that shows an OAuth result and auto-closes."""
    colour = "#16a34a" if success else "#dc2626"
    icon = "\u2714" if success else "\u2716"  # ✔ or ✖
    return HttpResponse(
        f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title}</title>
<style>
  body {{ font-family: system-ui, sans-serif; display: flex;
         justify-content: center; align-items: center; min-height: 100vh;
         margin: 0; background: #f8fafc; color: #1e293b; }}
  .card {{ text-align: center; padding: 2rem 3rem; border-radius: 16px;
           background: #fff; box-shadow: 0 1px 3px rgba(0,0,0,.1); }}
  .icon {{ font-size: 3rem; color: {colour}; }}
  h1 {{ font-size: 1.25rem; margin: .75rem 0 .5rem; }}
  p {{ color: #64748b; margin: 0; }}
  .hint {{ margin-top: 1rem; font-size: .85rem; color: #94a3b8; }}
</style></head><body>
<div class="card">
  <div class="icon">{icon}</div>
  <h1>{title}</h1>
  <p>{message}</p>
  <p class="hint">You can close this tab and return to the app.</p>
</div></body></html>""",
        content_type="text/html",
    )


def oauth_callback(request, provider):
    """Handle GET redirect from Google / GitHub after the user authorises.

    For login / register flows the view redirects to the frontend app with the
    ``code`` and ``state`` query parameters so the SPA can exchange them.

    For bind flows (``state`` ends with ``_bind``) the backend exchanges the
    code itself and renders a static success / failure page.
    """
    code = request.GET.get("code", "")
    state = request.GET.get("state", "")
    error = request.GET.get("error", "")

    if error:
        return _oauth_result_page(
            "Authentication failed",
            f"The provider returned an error: {error}",
            success=False,
        )

    if not code:
        return _oauth_result_page(
            "Authentication failed",
            "No authorisation code received from the provider.",
            success=False,
        )

    # Determine the frontend origin to redirect to.
    frontend_origin = os.getenv("FRONTEND_ORIGIN", "").rstrip("/")

    # Default frontend path is the editor app.
    frontend_path = "/Notechondria/editor/"
    if frontend_origin:
        redirect_target = f"{frontend_origin}{frontend_path}"
    else:
        # Fallback: same origin (Docker Compose where gateway routes everything)
        redirect_target = frontend_path

    params = urlencode({"code": code, "state": state})
    redirect_url = f"{redirect_target}?{params}"

    return HttpResponse(
        f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta http-equiv="refresh" content="0;url={redirect_url}">
<title>Redirecting…</title>
<style>
  body {{ font-family: system-ui, sans-serif; display: flex;
         justify-content: center; align-items: center; min-height: 100vh;
         margin: 0; background: #f8fafc; color: #1e293b; }}
</style></head><body>
<p>Redirecting to the app…</p>
<script>window.location.replace({redirect_url!r});</script>
</body></html>""",
        content_type="text/html",
    )


def media_serve(request, path):
    """Serve media files: try local disk first, proxy to R2 if configured.

    When Cloudflare R2 is the storage backend the API rewrites media URLs to
    same-origin ``/media/`` paths so Flutter Web's CanvasKit renderer can load
    them without CORS issues.  This view fulfils those requests by proxying to
    R2 when the file is not on the local filesystem.
    """
    local_path = os.path.join(settings.MEDIA_ROOT, path)
    if os.path.isfile(local_path):
        from django.views.static import serve
        return serve(request, path, settings.MEDIA_ROOT)

    media_url = getattr(settings, "MEDIA_URL", "/media/")
    if media_url.startswith("http"):
        target = f"{media_url}{path}"
        try:
            resp = http_requests.get(target, timeout=30, stream=True)
            if resp.status_code == 200:
                django_resp = HttpResponse(
                    resp.content,
                    content_type=resp.headers.get("Content-Type", "application/octet-stream"),
                )
                django_resp["Cache-Control"] = "public, max-age=86400"
                return django_resp
        except Exception as exc:
            logger.warning("media_serve: failed to proxy %s: %s", target, exc)

    raise Http404(f"Media file not found: {path}")
