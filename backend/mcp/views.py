"""MCP Streamable HTTP transport view.

POST /mcp/ — accepts a JSON-RPC 2.0 request, returns a JSON-RPC response.
Requires API key authentication (``Authorization: Bearer ntc_...``).

Reference: https://spec.modelcontextprotocol.io/specification/2025-03-26/basic/transports/
"""

import json
import logging
import uuid

from django.http import JsonResponse
from django.views import View
from django.utils.decorators import method_decorator
from django.views.decorators.csrf import csrf_exempt

from creators.authentication import ApiKeyAuthentication
from creators.utils import ensure_creator

from . import protocol

logger = logging.getLogger("django")


@method_decorator(csrf_exempt, name="dispatch")
class McpView(View):
    """Streamable HTTP MCP endpoint."""

    def post(self, request):
        # --- Authenticate via API key ---
        auth = ApiKeyAuthentication()
        try:
            result = auth.authenticate(request)
        except Exception as exc:
            return _json_error(
                401,
                (
                    "MCP request rejected: "
                    "Backend.Mcp.Protocol/authenticate \u2014 "
                    f"{exc}."
                ),
            )
        if result is None:
            return _json_error(
                401,
                (
                    "MCP request rejected: "
                    "Backend.Mcp.Protocol/authenticate \u2014 "
                    "API key required. Use: Authorization: Bearer ntc_<key>."
                ),
            )
        user, _raw_key = result
        creator = getattr(request, "creator", None) or ensure_creator(user)

        # --- Parse JSON-RPC body ---
        content_type = request.content_type or ""
        if "json" not in content_type:
            return _json_error(
                415,
                (
                    "MCP request rejected: "
                    "Backend.Mcp.Protocol/parse \u2014 "
                    "Content-Type must be application/json."
                ),
            )
        try:
            body = json.loads(request.body)
        except (json.JSONDecodeError, ValueError):
            return protocol._error_response(
                protocol.PARSE_ERROR,
                (
                    "MCP request rejected: "
                    "Backend.Mcp.Protocol/parse \u2014 "
                    "request body is not valid JSON."
                ),
                http_status=400,
            )

        if not isinstance(body, dict):
            return protocol._error_response(
                protocol.INVALID_REQUEST,
                (
                    "MCP request rejected: "
                    "Backend.Mcp.Protocol/parse \u2014 "
                    "JSON-RPC payload must be a single object, not a list or scalar."
                ),
                http_status=400,
            )
        if body.get("jsonrpc") != protocol.JSONRPC_VERSION:
            return protocol._error_response(
                protocol.INVALID_REQUEST,
                (
                    "MCP request rejected: "
                    "Backend.Mcp.Protocol/parse \u2014 "
                    'missing or invalid "jsonrpc" field '
                    f'(expected "{protocol.JSONRPC_VERSION}").'
                ),
                body.get("id"),
                http_status=400,
            )

        # --- Dispatch ---
        response = protocol.handle_request(body, user, creator)

        # Attach session ID header per MCP spec.
        session_id = request.headers.get("Mcp-Session-Id")
        if session_id:
            response["Mcp-Session-Id"] = session_id
        else:
            response["Mcp-Session-Id"] = str(uuid.uuid4())

        return response

    def get(self, request):
        """SSE endpoint for server-initiated notifications.

        For now we don't push notifications, so this returns 405.
        Clients can still use POST for all interactions.
        """
        return JsonResponse(
            {"detail": (
                "MCP request rejected: "
                "Backend.Mcp.Protocol/sse_get \u2014 "
                "server-initiated SSE notifications are not implemented; "
                "use POST for all MCP interactions."
            )},
            status=405,
        )

    def delete(self, request):
        """Terminate session \u2014 acknowledge and return 200."""
        return JsonResponse(
            {"detail": (
                "MCP session terminated: "
                "Backend.Mcp.Protocol/session.delete \u2014 "
                "client requested DELETE on the MCP endpoint."
            )},
            status=200,
        )


def _json_error(status, message):
    return JsonResponse({"detail": message}, status=status)
