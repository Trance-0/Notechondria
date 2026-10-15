// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void browserRedirect(String url) {
  html.window.location.href = url;
}

/// Rewrites the browser's hash fragment to [path] (e.g. `/courses/cv`)
/// without reloading or adding a history entry. Used to keep the address
/// bar in sync with in-app state changes (tab switches, opening a course)
/// that don't push a Navigator route, so every surface has a unique,
/// shareable URL under Flutter web's default hash strategy.
void replaceBrowserPath(String path) {
  final normalized = path.startsWith('/') ? path : '/$path';
  html.window.history.replaceState(null, '', '#$normalized');
}
