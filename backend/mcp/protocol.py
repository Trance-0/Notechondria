"""MCP JSON-RPC 2.0 protocol handler.

Implements the Model Context Protocol (2025-03-26) Streamable HTTP transport.
Each POST carries one JSON-RPC request; the response is a JSON-RPC result.

Reference: https://spec.modelcontextprotocol.io/specification/2025-03-26/
"""

import json
import logging
import uuid

from django.http import JsonResponse

logger = logging.getLogger("django")

# ---------------------------------------------------------------------------
# JSON-RPC helpers
# ---------------------------------------------------------------------------

JSONRPC_VERSION = "2.0"
PARSE_ERROR = -32700
INVALID_REQUEST = -32600
METHOD_NOT_FOUND = -32601
INVALID_PARAMS = -32602
INTERNAL_ERROR = -32603


def _error_response(code, message, req_id=None, http_status=200):
    return JsonResponse(
        {
            "jsonrpc": JSONRPC_VERSION,
            "id": req_id,
            "error": {"code": code, "message": message},
        },
        status=http_status,
    )


def _result_response(result, req_id):
    return JsonResponse(
        {
            "jsonrpc": JSONRPC_VERSION,
            "id": req_id,
            "result": result,
        },
    )


# ---------------------------------------------------------------------------
# MCP Server Info
# ---------------------------------------------------------------------------

SERVER_INFO = {
    "name": "notechondria-mcp",
    "version": "0.1.0",
}

SERVER_CAPABILITIES = {
    "tools": {"listChanged": False},
}

MCP_PROTOCOL_VERSION = "2025-03-26"


# ---------------------------------------------------------------------------
# Tool registry
# ---------------------------------------------------------------------------

_TOOLS = {}  # name -> {"description": str, "inputSchema": dict, "handler": callable}


def register_tool(name, description, input_schema, handler):
    """Register an MCP tool.

    ``handler(user, creator, params) -> dict`` is called when the tool is
    invoked.  It receives the authenticated Django user, their Creator
    instance, and the validated params dict.
    """
    _TOOLS[name] = {
        "description": description,
        "inputSchema": input_schema,
        "handler": handler,
    }


def list_tools():
    return [
        {
            "name": name,
            "description": info["description"],
            "inputSchema": info["inputSchema"],
        }
        for name, info in _TOOLS.items()
    ]


# ---------------------------------------------------------------------------
# Method dispatch
# ---------------------------------------------------------------------------

def handle_request(body, user, creator):
    """Dispatch a parsed JSON-RPC request body.  Returns a Django response."""
    req_id = body.get("id")
    method = body.get("method")
    params = body.get("params", {})

    if method == "initialize":
        # Surface the user's per-account skill.md (import / export
        # preferences, target platforms, etc.) as the MCP `instructions`
        # field. Agents that respect the spec read this on connect.
        skill_md = (getattr(creator, "mcp_skill_md", "") or "").strip()
        result = {
            "protocolVersion": MCP_PROTOCOL_VERSION,
            "capabilities": SERVER_CAPABILITIES,
            "serverInfo": SERVER_INFO,
        }
        if skill_md:
            result["instructions"] = skill_md
        return _result_response(result, req_id)

    if method == "notifications/initialized":
        # Client acknowledgement — nothing to return for notifications.
        return JsonResponse({}, status=204) if req_id is None else _result_response({}, req_id)

    if method == "ping":
        return _result_response({}, req_id)

    if method == "tools/list":
        return _result_response({"tools": list_tools()}, req_id)

    if method == "tools/call":
        tool_name = params.get("name", "")
        tool_args = params.get("arguments", {})
        if tool_name not in _TOOLS:
            return _error_response(
                METHOD_NOT_FOUND,
                (
                    "MCP tool call rejected: "
                    "Backend.Mcp.Protocol/tools.call \u2014 "
                    f"no tool registered under name {tool_name!r}."
                ),
                req_id,
            )
        tool = _TOOLS[tool_name]
        try:
            result = tool["handler"](user, creator, tool_args)
            return _result_response(
                {
                    "content": [
                        {"type": "text", "text": json.dumps(result, default=str)},
                    ],
                },
                req_id,
            )
        except Exception as exc:
            logger.exception("MCP tool %s failed", tool_name)
            return _result_response(
                {
                    "content": [
                        {"type": "text", "text": (
                            f"MCP tool call failed: "
                            f"Backend.Mcp.Protocol/tools.call.{tool_name} \u2014 "
                            f"{exc.__class__.__name__}: {exc}."
                        )},
                    ],
                    "isError": True,
                },
                req_id,
            )

    return _error_response(
        METHOD_NOT_FOUND,
        (
            "MCP request rejected: "
            "Backend.Mcp.Protocol/dispatch \u2014 "
            f"no handler for method {method!r}."
        ),
        req_id,
    )
