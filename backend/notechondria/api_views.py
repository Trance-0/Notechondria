import datetime as _dt
import json
import logging
import os
import subprocess
from pathlib import Path
from typing import Optional
from urllib.parse import urlencode

import requests as http_requests
from django.conf import settings
from django.utils import timezone
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
_cached_build_metadata: Optional[dict] = None


def _version_file_candidates() -> list[Path]:
    """Filesystem paths to check for the VERSION file. Same set is
    reused by `_build_metadata` to look up the file's mtime as a
    last-resort `build_time` proxy."""
    base = Path(settings.BASE_DIR)
    return [
        base.parent / "VERSION",          # dev: <repo>/VERSION when BASE_DIR=<repo>/backend
        base.parent.parent / "VERSION",   # nested layouts
        Path("/home/VERSION"),            # canonical Docker location (COPY VERSION /home/VERSION)
        Path("/VERSION"),
    ]


def _read_backend_version() -> str:
    """Resolve the deployed VERSION string. Filesystem first (the
    Dockerfile copies VERSION into the image at build time, so the
    file mtime is a reliable build-time proxy too), then the
    `BACKEND_VERSION` env var as a runtime override, then `git
    describe` for dev machines. Returns the literal string
    ``"unknown"`` only when every source fails — never falls back to
    ``"0.0.0"`` because that string was indistinguishable from a real
    version and silently masked stale-deploy bugs in production.

    Cached for the lifetime of the gunicorn worker (refreshes on
    restart). The cache is also used by `/api/v1/handshake/`'s
    `build` block, so the version + commit + build_time fields stay
    in sync across requests within the same worker.
    """
    global _cached_backend_version
    if _cached_backend_version is not None:
        return _cached_backend_version

    for candidate in _version_file_candidates():
        try:
            text = candidate.read_text(encoding="utf-8").strip()
        except OSError:
            continue
        if text:
            _cached_backend_version = text
            return _cached_backend_version

    env_version = (os.getenv("BACKEND_VERSION") or "").strip()
    if env_version:
        _cached_backend_version = env_version
        return _cached_backend_version

    sha = _git_describe()
    if sha:
        _cached_backend_version = f"git-{sha}"
        return _cached_backend_version

    logger.warning(
        "Backend version unresolved: "
        "Backend.Notechondria.Handshake/read_version — "
        "no VERSION file at any candidate path, no BACKEND_VERSION env "
        "var, no git available. Returning 'unknown' so handshake never "
        "lies about the deployed build."
    )
    _cached_backend_version = "unknown"
    return _cached_backend_version


def _git_describe() -> str:
    """Best-effort short git SHA + dirty flag. Used as the version /
    commit fallback when no VERSION / BUILD_COMMIT file made it into
    the image (typical dev / first-build state). Silent on
    failure — git isn't always installed in the production image."""
    repo_root = Path(settings.BASE_DIR).parent
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--short=12", "HEAD"],
            capture_output=True,
            text=True,
            timeout=2,
            cwd=str(repo_root),
            check=False,
        )
    except (FileNotFoundError, OSError, subprocess.SubprocessError):
        return ""
    if result.returncode != 0:
        return ""
    return result.stdout.strip()


def _read_build_commit() -> str:
    """Resolve the build commit. Filesystem (`/home/BUILD_COMMIT`,
    written by the Dockerfile from a build ARG) → env var →
    `git rev-parse HEAD`. Truncated to 40 chars to fit a SHA."""
    for candidate in [
        Path("/home/BUILD_COMMIT"),
        Path(settings.BASE_DIR).parent / "BUILD_COMMIT",
    ]:
        try:
            text = candidate.read_text(encoding="utf-8").strip()
        except OSError:
            continue
        if text:
            return text[:40]
    env_commit = (os.getenv("BACKEND_BUILD_COMMIT") or "").strip()
    if env_commit:
        return env_commit[:40]
    sha = _git_describe()
    if sha:
        return sha
    return ""


def _read_build_time() -> str:
    """Resolve the build timestamp. Filesystem (`/home/BUILD_TIME`,
    written by the Dockerfile at COPY time) → env var → mtime of the
    VERSION file as a proxy (the file is COPY'd into the image so its
    mtime equals the image build time)."""
    for candidate in [
        Path("/home/BUILD_TIME"),
        Path(settings.BASE_DIR).parent / "BUILD_TIME",
    ]:
        try:
            text = candidate.read_text(encoding="utf-8").strip()
        except OSError:
            continue
        if text:
            return text
    env_time = os.getenv("BACKEND_BUILD_TIME") or ""
    if env_time:
        return env_time
    for candidate in _version_file_candidates():
        try:
            stat = candidate.stat()
        except OSError:
            continue
        return _dt.datetime.fromtimestamp(
            stat.st_mtime, tz=_dt.timezone.utc
        ).isoformat()
    return ""


def _build_metadata() -> dict:
    """Build provenance for `/api/v1/handshake/`. Auto-derives every
    field from the filesystem first so a fresh container with no env
    vars set still reports the truth. Cached on the worker — these
    facts don't change after the image is built. `deploy_target` is
    the only env-driven knob (it's a label, not a derived fact)."""
    global _cached_build_metadata
    if _cached_build_metadata is None:
        _cached_build_metadata = {
            "version": _read_backend_version(),
            "commit": _read_build_commit(),
            "build_time": _read_build_time(),
            "deploy_target": os.getenv("BACKEND_DEPLOY_TARGET") or "",
        }
    return _cached_build_metadata


def health_check(request):
    return JsonResponse({"status": "ok", "service": HANDSHAKE_SERVICE_ID})


@require_GET
def ping(request):
    """Minimal liveness check used by the frontend debug-log `ping` command.

    Returns a compact JSON payload with a server-side UTC timestamp so the
    client can measure round-trip latency without paying for the full
    handshake payload. Matches the §1.7 shape on failure via the usual
    DRF exception handler; on success the payload is small by design:
    the frontend only needs `pong` and `timestamp` to prove the path
    from the device to the backend is live.
    """
    return JsonResponse(
        {
            "pong": True,
            "service": HANDSHAKE_SERVICE_ID,
            "timestamp": timezone.now().isoformat(),
        }
    )


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
            "build": _build_metadata(),
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

    0.1.120: structured info logs at every branch. The earlier "user
    suddenly logged out after GitHub repo link, no logs on backend"
    symptom came from this view being silent on the success path while
    the SPA's cold-boot post-redirect raced an expired Casdoor JWT —
    making it look like the auth pipeline was broken. With these
    logs plus the GithubSyncCallbackApiView entry/exit lines, an
    operator can pin the failure to either the redirect leg
    (``oauth_callback`` recorded entry) or the SPA-side install POST
    (``GithubSync/install_callback`` recorded entry).
    """
    code = request.GET.get("code", "")
    state = request.GET.get("state", "")
    error = request.GET.get("error", "")
    installation_id = request.GET.get("installation_id", "")
    setup_action = request.GET.get("setup_action", "")

    logger.info(
        "OAuth callback received: "
        "Backend.Notechondria.OAuth/callback — "
        "provider=%s state=%r has_code=%s installation_id=%r "
        "setup_action=%r error=%r.",
        provider,
        state,
        bool(code),
        installation_id,
        setup_action,
        error,
    )

    if error:
        logger.warning(
            "OAuth callback rejected by provider: "
            "Backend.Notechondria.OAuth/callback — "
            "provider=%s error=%s.",
            provider, error,
        )
        return _oauth_result_page(
            "Authentication failed",
            f"The provider returned an error: {error}",
            success=False,
        )

    if not code:
        # GitHub App install callbacks may arrive without a `code` when
        # the user only adjusted an existing installation (no fresh OAuth
        # exchange happened). Fall through to the redirect branch so the
        # SPA can read `installation_id` from the query string and
        # finish wiring up the integration.
        if provider == "github" and installation_id:
            logger.info(
                "OAuth callback (GitHub install-only, no code): "
                "Backend.Notechondria.OAuth/callback — "
                "installation_id=%s setup_action=%s.",
                installation_id, setup_action,
            )
        else:
            logger.warning(
                "OAuth callback missing code: "
                "Backend.Notechondria.OAuth/callback — "
                "provider=%s state=%r.",
                provider, state,
            )
            return _oauth_result_page(
                "Authentication failed",
                "No authorisation code received from the provider.",
                success=False,
            )

    # Determine the frontend origin to redirect to.
    frontend_origin = os.getenv("FRONTEND_ORIGIN", "").rstrip("/")

    # 0.1.128: route the same-tab fallback back to the app that
    # started the flow. The SPA appends `_editor` / `_planner` /
    # `_portal` to `state` (mirroring the `_bind` suffix convention);
    # GitHub App installs round-trip `state` to this callback. Flows
    # that predate the suffix (or strip it) keep the historical
    # editor default. The popup path posts back to `window.opener`
    # and never navigates, so this only matters when the popup was
    # blocked or a legacy same-tab flow is in use.
    frontend_path = "/Notechondria/editor/"
    for app_key in ("editor", "planner", "portal"):
        if state.endswith(f"_{app_key}"):
            frontend_path = f"/Notechondria/{app_key}/"
            break
    if frontend_origin:
        redirect_target = f"{frontend_origin}{frontend_path}"
    else:
        # Fallback: same origin (Docker Compose where gateway routes everything)
        redirect_target = frontend_path

    forward = {"code": code, "state": state}
    if installation_id:
        forward["installation_id"] = installation_id
    if setup_action:
        forward["setup_action"] = setup_action
    params = urlencode(forward)
    redirect_url = f"{redirect_target}?{params}"
    logger.info(
        "OAuth callback redirecting to SPA: "
        "Backend.Notechondria.OAuth/callback — "
        "provider=%s target=%s forward_keys=%s.",
        provider,
        redirect_target,
        ",".join(forward.keys()),
    )

    # 0.1.120: dual-mode response.
    # - Popup-mode (the new GitHub-install flow opens this URL via
    #   `window.open(...)` and stays loaded in the parent SPA): the
    #   page detects `window.opener`, posts the OAuth params back to
    #   the parent, and closes itself. The parent SPA never reloads,
    #   so its in-memory auth state survives — fixing the "user
    #   suddenly logged out after GH App link" bug.
    # - Same-tab fallback (legacy callers, plus Casdoor login flows
    #   that aren't routed through a popup): meta-refresh + replace
    #   to the SPA route as before, so existing flows keep working.
    forward_json = json.dumps({k: v for k, v in forward.items()})
    return HttpResponse(
        f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<title>Completing sign-in…</title>
<style>
  body {{ font-family: system-ui, sans-serif; display: flex;
         justify-content: center; align-items: center; min-height: 100vh;
         margin: 0; background: #f8fafc; color: #1e293b; }}
</style></head><body>
<p>Finishing up…</p>
<script>
(function () {{
  var payload = Object.assign({{type: "gh-install"}}, {forward_json});
  // Popup mode: the SPA opened this window with `window.open(...)`.
  // Posting back lets the parent finish the install without losing
  // its in-memory auth state. We close ourselves immediately after
  // the postMessage so the parent's UI takes back focus.
  if (window.opener && !window.opener.closed) {{
    try {{ window.opener.postMessage(payload, "*"); }} catch (e) {{}}
    try {{ window.close(); }} catch (e) {{}}
    return;
  }}
  // Same-tab fallback: redirect to the SPA route as before.
  window.location.replace({redirect_url!r});
}})();
</script>
<noscript>
<meta http-equiv="refresh" content="0;url={redirect_url}">
</noscript>
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
