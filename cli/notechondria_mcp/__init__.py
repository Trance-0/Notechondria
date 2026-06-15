"""Standalone Notechondria MCP server.

A thin client over the backend's ``/api/v1`` surface, authenticated
with an ``ntc_`` API key. It exposes the same agent-facing tools as the
in-backend ``/mcp/`` endpoint (``backend/mcp/``) so an agent connecting
to either gets the same surface — see ``docs/integrations/
mcp-cli-migration.md``.

Parity rule: every new tool must be added to BOTH this package and
``backend/mcp/tools.py`` (agent-oriented development).
"""

__version__ = "0.1.0"
