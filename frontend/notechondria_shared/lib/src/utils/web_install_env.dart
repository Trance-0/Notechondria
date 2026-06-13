// Stub web-install environment probe for non-web platforms (native
// desktop / mobile builds and `flutter test`). Resolved at compile
// time when `dart.library.html` is unavailable. See
// `web_install_env_web.dart` for the real browser implementation.

/// Whether the app is running inside a mobile browser tab (as opposed
/// to a native build or an installed home-screen PWA). Always false
/// off the web — native builds have durable storage and their own
/// install story, so the Add-to-Home-Screen nudge does not apply.
bool isMobileWebBrowser() => false;
