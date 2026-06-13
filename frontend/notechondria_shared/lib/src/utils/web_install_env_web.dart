// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

// Web implementation of the install-environment probe. Resolved at
// compile time when `dart.library.html` is available.

/// Whether the app is running inside a mobile browser tab — i.e. on a
/// phone/tablet user agent AND not already launched as an installed
/// home-screen app. Installed PWAs report `display-mode: standalone`
/// (or `navigator.standalone` on iOS Safari) and get a durable storage
/// partition, so the Add-to-Home-Screen nudge only targets the
/// in-browser case.
bool isMobileWebBrowser() {
  final ua = (html.window.navigator.userAgent).toLowerCase();
  final isMobileUa = RegExp(r'iphone|ipad|ipod|android|mobile').hasMatch(ua);
  if (!isMobileUa) return false;
  return !_isStandalone();
}

bool _isStandalone() {
  try {
    if (html.window.matchMedia('(display-mode: standalone)').matches) {
      return true;
    }
  } catch (_) {
    // matchMedia can throw on very old engines; treat as not-standalone.
  }
  // Older iOS Safari exposes a non-standard `navigator.standalone`
  // boolean instead of honoring the display-mode media query. It is
  // not in dart:html's typed `Navigator`, so read it dynamically;
  // absent on every other engine, where it resolves to null.
  final standalone = (html.window.navigator as dynamic).standalone;
  return standalone == true;
}
