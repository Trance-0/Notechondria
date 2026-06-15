"""CLI entry point: ``notechondria-mcp``.

Subcommands:
- (default) / ``serve``: run the MCP server over stdio.
- ``check``: verify the config + backend connectivity, then exit.
"""

from __future__ import annotations

import argparse
import sys

from .client import BackendClient, BackendError
from .config import describe_missing, load_config
from .server import serve_stdio


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="notechondria-mcp")
    sub = parser.add_subparsers(dest="command")
    sub.add_parser("serve", help="Run the MCP server over stdio (default).")
    sub.add_parser("check", help="Verify config + backend connectivity.")
    args = parser.parse_args(argv)

    config = load_config()

    if args.command == "check":
        missing = describe_missing(config)
        if missing:
            print(missing, file=sys.stderr)
            return 2
        try:
            profile = BackendClient(config).get("settings/")
        except BackendError as exc:
            print(f"Backend check failed: {exc}", file=sys.stderr)
            return 1
        username = ""
        if isinstance(profile, dict):
            username = str(profile.get("username") or "")
        print(f"OK — connected to {config.api_url} as {username or '<user>'}.")
        return 0

    # Default / `serve`: refuse to start without credentials so the agent
    # host sees a clear stderr message instead of every tool 401-ing.
    missing = describe_missing(config)
    if missing:
        print(missing, file=sys.stderr)
        return 2
    return serve_stdio(config)


if __name__ == "__main__":
    raise SystemExit(main())
