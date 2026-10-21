"""Calendar URL downloads that cannot reach private networks (issue #42).

A subscribed calendar URL is user input that the server fetches, so every
hop is checked: the URL scheme, every address its host resolves to, every
redirect target, and the address the socket actually connected to (which
also covers DNS answers that change between the check and the connect).
Only globally routable addresses are allowed; loopback, link-local (cloud
metadata), private, shared, reserved, multicast, and unspecified ones are
refused. Proxies are not used, because a proxy would hide the real peer.
"""

import http.client
import ipaddress
import socket
import urllib.error
import urllib.parse
import urllib.request

FETCH_TIMEOUT_SECONDS = 10
MAX_REDIRECTS = 5
_ALLOWED_SCHEMES = ("http", "https")
_CONSEQUENCE = "Calendar feed not fetched: planner calendar / feed fetch"


class BlockedCalendarURL(ValueError):
    """The URL, a redirect, or the connected peer is not a public host."""


def _blocked(cause: str) -> BlockedCalendarURL:
    return BlockedCalendarURL(
        f"{_CONSEQUENCE} — {cause}; only public internet calendar hosts can be "
        "subscribed (import the .ics file instead)."
    )


def _address_refused(text: str):
    """The reason [text] (an IP address) is refused, or None if it is public."""
    ip = ipaddress.ip_address(text.split("%", 1)[0])
    mapped = getattr(ip, "ipv4_mapped", None)
    if mapped is not None:
        ip = mapped
    if ip.is_global and not ip.is_multicast:
        return None
    for name in ("loopback", "link_local", "private", "reserved", "multicast", "unspecified"):
        if getattr(ip, f"is_{name}"):
            return f"{name.replace('_', '-')} address {ip}"
    return f"non-public address {ip}"


def check_calendar_url(url: str) -> None:
    """Raises BlockedCalendarURL unless [url] is http(s) on a public host."""
    parts = urllib.parse.urlsplit(url)
    scheme = (parts.scheme or "").lower()
    if scheme not in _ALLOWED_SCHEMES:
        raise _blocked(f"scheme '{scheme or '(none)'}' is not http or https")
    host = parts.hostname
    if not host:
        raise _blocked("the URL has no host")
    try:
        port = parts.port or (443 if scheme == "https" else 80)
    except ValueError:
        raise _blocked("the URL has an invalid port") from None
    try:
        infos = socket.getaddrinfo(host, port, proto=socket.IPPROTO_TCP)
    except socket.gaierror as exc:
        raise urllib.error.URLError(f"host {host} could not be resolved: {exc}") from exc
    for info in infos:
        reason = _address_refused(info[4][0])
        if reason:
            raise _blocked(f"host {host} resolves to the {reason}")


def check_connected_peer(sock, host: str) -> None:
    """Raises BlockedCalendarURL when [sock] is connected to a refused address."""
    reason = _address_refused(sock.getpeername()[0])
    if reason:
        raise _blocked(f"host {host} connected to the {reason}")


class _GuardedHTTPConnection(http.client.HTTPConnection):
    def connect(self):
        super().connect()
        try:
            check_connected_peer(self.sock, self.host)
        except BlockedCalendarURL:
            self.close()
            raise


class _GuardedHTTPSConnection(http.client.HTTPSConnection):
    def connect(self):
        super().connect()
        try:
            check_connected_peer(self.sock, self.host)
        except BlockedCalendarURL:
            self.close()
            raise


class _GuardedHTTPHandler(urllib.request.HTTPHandler):
    def http_open(self, req):
        return self.do_open(_GuardedHTTPConnection, req)


class _GuardedHTTPSHandler(urllib.request.HTTPSHandler):
    def https_open(self, req):
        return self.do_open(_GuardedHTTPSConnection, req, context=self._context)


class _GuardedRedirectHandler(urllib.request.HTTPRedirectHandler):
    max_redirections = MAX_REDIRECTS

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        check_calendar_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def _opener():
    return urllib.request.build_opener(
        urllib.request.ProxyHandler({}),
        _GuardedHTTPHandler(),
        _GuardedHTTPSHandler(),
        _GuardedRedirectHandler(),
    )


def fetch_calendar_text(url: str, headers: dict) -> str:
    """GET [url] with [headers] after the checks above; the body as UTF-8."""
    check_calendar_url(url)
    request = urllib.request.Request(url, headers=headers)
    with _opener().open(request, timeout=FETCH_TIMEOUT_SECONDS) as response:
        return response.read().decode("utf-8")
