"""CLI entry point: ``notechondria-mcp``.

Subcommands:
- (default) / ``serve``: run the MCP server over stdio.
- ``check``: verify the config + backend connectivity, then exit.
- ``batch``: execute a JSONL stream of tool calls (bulk imports).
"""

from __future__ import annotations

import argparse
import sys

from .batch import run_batch
from .client import BackendClient, BackendError
from .config import describe_missing, load_config
from .server import serve_stdio


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="notechondria-mcp")
    sub = parser.add_subparsers(dest="command")
    sub.add_parser("serve", help="Run the MCP server over stdio (default).")
    sub.add_parser("check", help="Verify config + backend connectivity.")
    batch_parser = sub.add_parser(
        "batch",
        help="Execute tool calls from a JSONL file ('-' or omitted = "
        "stdin): one {\"tool\": ..., \"arguments\": {...}} per line; "
        "one JSON result per line.",
    )
    batch_parser.add_argument("file", nargs="?", default="-")
    batch_parser.add_argument(
        "--stop-on-error",
        action="store_true",
        help="Abort on the first failed item (default: continue).",
    )
    args = parser.parse_args(argv)

    config = load_config()

    if args.command == "batch":
        missing = describe_missing(config)
        if missing:
            print(missing, file=sys.stderr)
            return 2
        if args.file == "-":
            return run_batch(config, stop_on_error=args.stop_on_error)
        with open(args.file, "r", encoding="utf-8") as handle:
            return run_batch(config, source=handle, stop_on_error=args.stop_on_error)

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
