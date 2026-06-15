"""Thin HTTP client for the Notechondria ``/api/v1`` surface.

Every request carries ``Authorization: Bearer ntc_<key>``; the backend
validates it with ``creators.authentication.ApiKeyAuthentication`` — the
same auth the in-backend ``/mcp/`` endpoint uses, so the CLI and ``/mcp/``
share one credential per user.
"""

from __future__ import annotations

from typing import Any, Optional

import requests

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
        self._session = requests.Session()
        self._session.headers.update({
            "Authorization": f"Bearer {config.api_key}",
            "Accept": "application/json",
        })

    def _url(self, path: str) -> str:
        return f"{self._base}/{path.lstrip('/')}"

    def _request(
        self,
        method: str,
        path: str,
        *,
        params: Optional[dict] = None,
        json_body: Optional[dict] = None,
    ) -> Any:
        try:
            response = self._session.request(
                method,
                self._url(path),
                params=params,
                json=json_body,
                timeout=self._timeout,
            )
        except requests.RequestException as exc:
            raise BackendError(0, f"request failed: {exc}") from exc
        if response.status_code == 204 or not response.content:
            return None
        try:
            payload = response.json()
        except ValueError:
            payload = {"detail": response.text[:500]}
        if response.status_code >= 400:
            detail = ""
            if isinstance(payload, dict):
                detail = str(payload.get("detail") or payload)
            raise BackendError(response.status_code, detail or "error")
        return payload

    def get(self, path: str, params: Optional[dict] = None) -> Any:
        return self._request("GET", path, params=params)

    def post(self, path: str, json_body: Optional[dict] = None) -> Any:
        return self._request("POST", path, json_body=json_body or {})

    def patch(self, path: str, json_body: Optional[dict] = None) -> Any:
        return self._request("PATCH", path, json_body=json_body or {})

    def delete(self, path: str) -> Any:
        return self._request("DELETE", path)
