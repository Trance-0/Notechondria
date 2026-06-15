"""Configuration loading for the Notechondria MCP CLI.

Resolution order (first non-empty wins):

1. Environment variables ``NOTECHONDRIA_API_URL`` /
   ``NOTECHONDRIA_API_KEY``.
2. A JSON config file at ``$NOTECHONDRIA_CONFIG`` or
   ``~/.notechondria/config.json`` with keys ``api_url`` / ``api_key``.

The API key is the same ``ntc_<key>`` the user mints in the web app's
Settings → API settings (there is one key per user). The API URL is the
versioned base, e.g. ``https://notechondria.trance-0.com/api/v1``.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

DEFAULT_API_URL = "https://notechondria.trance-0.com/api/v1"


@dataclass
class Config:
    api_url: str
    api_key: str

    @property
    def is_complete(self) -> bool:
        return bool(self.api_url) and bool(self.api_key)


def _config_path() -> Path:
    override = os.environ.get("NOTECHONDRIA_CONFIG", "").strip()
    if override:
        return Path(override).expanduser()
    return Path.home() / ".notechondria" / "config.json"


def _read_file_config() -> dict:
    path = _config_path()
    try:
        with path.open(encoding="utf-8") as handle:
            data = json.load(handle)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def load_config() -> Config:
    """Resolve the CLI config from env then the config file."""
    file_cfg = _read_file_config()
    api_url = (
        os.environ.get("NOTECHONDRIA_API_URL", "").strip()
        or str(file_cfg.get("api_url", "")).strip()
        or DEFAULT_API_URL
    )
    api_key = (
        os.environ.get("NOTECHONDRIA_API_KEY", "").strip()
        or str(file_cfg.get("api_key", "")).strip()
    )
    return Config(api_url=_normalize_api_url(api_url), api_key=api_key)


def _normalize_api_url(raw: str) -> str:
    """Trim trailing slashes and ensure the ``/api/v1`` suffix, matching
    the web client's `_normalizeBaseUrl`."""
    value = raw.strip().rstrip("/")
    if not value:
        return value
    if value.endswith("/api/v1"):
        return value
    if value.endswith("/api"):
        return value + "/v1"
    return value + "/api/v1"


def describe_missing(config: Config) -> Optional[str]:
    """Return a human-readable hint when the config is incomplete, else
    None. Never echoes the key itself."""
    if config.is_complete:
        return None
    parts = []
    if not config.api_key:
        parts.append(
            "no API key — set NOTECHONDRIA_API_KEY or `api_key` in "
            f"{_config_path()} (mint one in the web app's Settings → "
            "API settings)"
        )
    if not config.api_url:
        parts.append("no API URL")
    return "Notechondria MCP config incomplete: " + "; ".join(parts) + "."
