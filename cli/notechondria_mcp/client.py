"""Thin HTTP client for the Notechondria ``/api/v1`` surface.

Every request carries ``Authorization: Bearer ntc_<key>``; the backend
validates it with ``creators.authentication.ApiKeyAuthentication`` — the
same auth the in-backend ``/mcp/`` endpoint uses, so the CLI and ``/mcp/``
share one credential per user.

Implemented with the standard library only (``urllib``) so the CLI has
no third-party runtime dependency and the "stdlib only" CI job can run
it without a ``pip install`` step.
"""

from __future__ import annotations

import json as _json
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Optional

from .config import Config


class BackendError(RuntimeError):
    """A non-2xx response from the backend. Carries the status + detail
    so a tool handler can surface a useful message to the agent."""

    def __init__(self, status: int, detail: str):
        super().__init__(f"backend HTTP {status}: {detail}")
        self.status = status
        self.detail = detail


class BackendClient:
    def __init__(self, config: Config, timeout: float = 20.0):
        self._base = config.api_url.rstrip("/")
        self._timeout = timeout
        self._headers = {
            "Authorization": f"Bearer {config.api_key}",
            "Accept": "application/json",
        }

    def _url(self, path: str, params: Optional[dict] = None) -> str:
        url = f"{self._base}/{path.lstrip('/')}"
        if params:
            # Drop None values so callers can pass sparse param dicts.
            query = {k: v for k, v in params.items() if v is not None}
            if query:
                url = f"{url}?{urllib.parse.urlencode(query, doseq=True)}"
        return url

    def _request(
        self,
        method: str,
        path: str,
        *,
        params: Optional[dict] = None,
        json_body: Optional[dict] = None,
    ) -> Any:
        headers = dict(self._headers)
        data = None
        if json_body is not None:
            data = _json.dumps(json_body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(
            self._url(path, params), data=data, method=method, headers=headers
        )
        try:
            with urllib.request.urlopen(request, timeout=self._timeout) as response:
                status = response.getcode()
                body = response.read()
        except urllib.error.HTTPError as exc:
            # HTTPError is a response too: read its body for the detail.
            status = exc.code
            body = exc.read() if hasattr(exc, "read") else b""
        except urllib.error.URLError as exc:
            raise BackendError(0, f"request failed: {exc.reason}") from exc
        except (TimeoutError, OSError) as exc:  # socket timeouts, connection resets
            raise BackendError(0, f"request failed: {exc}") from exc

        if status == 204 or not body:
            if status >= 400:
                raise BackendError(status, "error")
            return None
        try:
            payload = _json.loads(body.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            text = body.decode("utf-8", "replace")
            payload = {"detail": text[:500]}
        if status >= 400:
            detail = ""
            if isinstance(payload, dict):
                detail = str(payload.get("detail") or payload)
            raise BackendError(status, detail or "error")
        return payload

    def get(self, path: str, params: Optional[dict] = None) -> Any:
        return self._request("GET", path, params=params)

    def post(self, path: str, json_body: Optional[dict] = None) -> Any:
        return self._request("POST", path, json_body=json_body or {})

    def patch(self, path: str, json_body: Optional[dict] = None) -> Any:
        return self._request("PATCH", path, json_body=json_body or {})

    def delete(self, path: str) -> Any:
        return self._request("DELETE", path)
