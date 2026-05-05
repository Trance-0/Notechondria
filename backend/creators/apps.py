import logging
import os

from django.apps import AppConfig


logger = logging.getLogger("django")


class CreatorsConfig(AppConfig):
    name = 'creators'

    def ready(self):
        # Print the deployed image's build provenance once per worker
        # boot so the operator can grep Northflank logs and confirm
        # which image is actually serving — distinct from the
        # /api/v1/handshake/ response, which is only useful when a
        # new request can reach the route. When Docker silently
        # serves a stale layer cache, the handshake never updates
        # but a fresh worker boot will still log the new VERSION /
        # commit / build_time and surface the drift immediately.
        #
        # Lazy import: api_views pulls Django settings (HTTP, etc.),
        # which must not be touched until AppConfig.ready() is called.
        from notechondria.api_views import _build_metadata

        # Skip when the management command is something that
        # spawns workers itself (`runserver` autoreload child) so we
        # don't double-log on every code change in dev.
        if os.environ.get("RUN_MAIN") == "false":
            return

        meta = _build_metadata()
        logger.info(
            "Backend image started: "
            "Backend.Notechondria.Boot/version_log — "
            "version=%s commit=%s build_time=%s deploy_target=%s. "
            "Grep this line per gunicorn worker boot to confirm the "
            "deployed image's build provenance even when "
            "/api/v1/handshake/ is unreachable (e.g. stale Docker "
            "layer cache, broken route, blue/green mid-cutover).",
            meta.get("version") or "<unknown>",
            (meta.get("commit") or "<unknown>")[:12],
            meta.get("build_time") or "<unknown>",
            meta.get("deploy_target") or "<unset>",
        )
