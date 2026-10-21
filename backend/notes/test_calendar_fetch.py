"""Private-host guard of calendar URL downloads (issue #42). No network: the
refused URLs fail before any connection, and DNS is patched where a host
name is needed."""

import socket
import urllib.request
from types import SimpleNamespace
from unittest import mock

from django.test import SimpleTestCase

from notes import calendar_fetch
from notes.calendar_fetch import BlockedCalendarURL, check_calendar_url
from notes.services import read_calendar_feed, summarize_calendar_feed


def _resolves_to(address):
    def fake(host, port, *args, **kwargs):
        family = socket.AF_INET6 if ":" in address else socket.AF_INET
        return [(family, socket.SOCK_STREAM, socket.IPPROTO_TCP, "", (address, port))]

    return fake


class CalendarUrlGuardTests(SimpleTestCase):
    def test_refuses_non_public_addresses(self):
        for url in [
            "http://127.0.0.1/a.ics",
            "http://127.1.2.3:8000/a.ics",
            "http://10.0.0.5/a.ics",
            "http://172.16.0.1/a.ics",
            "https://192.168.1.1/a.ics",
            "http://169.254.169.254/latest/meta-data/",
            "http://100.64.0.1/a.ics",
            "http://0.0.0.0/a.ics",
            "http://224.0.0.1/a.ics",
            "http://[::1]/a.ics",
            "http://[fe80::1]/a.ics",
            "http://[fd00::1]/a.ics",
            "http://[::ffff:127.0.0.1]/a.ics",
        ]:
            with self.subTest(url=url):
                with self.assertRaises(BlockedCalendarURL) as ctx:
                    check_calendar_url(url)
                self.assertIn("Calendar feed not fetched: planner calendar / feed fetch — ", str(ctx.exception))

    def test_refuses_other_schemes_and_missing_hosts(self):
        for url in ["file:///etc/passwd", "ftp://example.com/a.ics", "gopher://example.com/", "http:///a.ics", "a.ics"]:
            with self.subTest(url=url):
                with self.assertRaises(BlockedCalendarURL):
                    check_calendar_url(url)

    def test_allows_a_public_address(self):
        check_calendar_url("https://93.184.216.34/basic.ics")
        check_calendar_url("http://[2606:2800:220:1::248]/basic.ics")

    def test_refuses_a_host_name_that_resolves_to_a_private_address(self):
        with mock.patch.object(socket, "getaddrinfo", _resolves_to("10.1.2.3")):
            with self.assertRaises(BlockedCalendarURL) as ctx:
                check_calendar_url("https://calendar.example.com/basic.ics")
        self.assertIn("calendar.example.com resolves to the private address 10.1.2.3", str(ctx.exception))
        with mock.patch.object(socket, "getaddrinfo", _resolves_to("93.184.216.34")):
            check_calendar_url("https://calendar.example.com/basic.ics")

    def test_refuses_a_redirect_to_a_private_address(self):
        handler = calendar_fetch._GuardedRedirectHandler()
        request = urllib.request.Request("https://93.184.216.34/basic.ics")
        for target in ["http://127.0.0.1/admin/", "http://169.254.169.254/latest/meta-data/", "file:///etc/passwd"]:
            with self.subTest(target=target):
                with self.assertRaises(BlockedCalendarURL):
                    handler.redirect_request(request, None, 302, "Found", {}, target)
        self.assertEqual(handler.max_redirections, calendar_fetch.MAX_REDIRECTS)

    def test_refuses_a_connected_peer_with_a_private_address(self):
        # A DNS answer can change between the check and the connect.
        sock = SimpleNamespace(getpeername=lambda: ("192.168.0.9", 443))
        with self.assertRaises(BlockedCalendarURL) as ctx:
            calendar_fetch.check_connected_peer(sock, "calendar.example.com")
        self.assertIn("connected to the private address 192.168.0.9", str(ctx.exception))
        calendar_fetch.check_connected_peer(SimpleNamespace(getpeername=lambda: ("93.184.216.34", 443)), "x")

    def test_the_opener_uses_no_proxy_and_the_guarded_handlers(self):
        opener = calendar_fetch._opener()
        kinds = {type(h) for h in opener.handlers}
        self.assertIn(calendar_fetch._GuardedHTTPHandler, kinds)
        self.assertIn(calendar_fetch._GuardedHTTPSHandler, kinds)
        self.assertIn(calendar_fetch._GuardedRedirectHandler, kinds)
        self.assertNotIn(urllib.request.HTTPHandler, kinds)
        proxies = [h for h in opener.handlers if isinstance(h, urllib.request.ProxyHandler)]
        self.assertTrue(all(h.proxies == {} for h in proxies))


class CalendarFeedReadTests(SimpleTestCase):
    def test_a_private_feed_url_is_refused_and_summarized(self):
        feed = SimpleNamespace(raw_ical="", source_url="http://169.254.169.254/latest/meta-data/", title="Metadata")
        with mock.patch.object(urllib.request.OpenerDirector, "open") as opened:
            with self.assertRaises(BlockedCalendarURL):
                read_calendar_feed(feed)
            summary = summarize_calendar_feed(feed)
        opened.assert_not_called()
        self.assertFalse(summary["ok"])
        self.assertIn("link-local address 169.254.169.254", summary["error"])

    def test_inline_ical_needs_no_fetch(self):
        feed = SimpleNamespace(raw_ical="BEGIN:VCALENDAR\nEND:VCALENDAR\n", source_url="http://127.0.0.1/", title="x")
        self.assertEqual(read_calendar_feed(feed), feed.raw_ical)
