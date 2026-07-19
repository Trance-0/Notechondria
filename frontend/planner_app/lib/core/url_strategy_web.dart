// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void browserRedirect(String url) {
  html.window.location.href = url;
}

/// Rewrites the hash fragment without reloading (unique tab URLs).
void replaceBrowserPath(String path) {
  final normalized = path.startsWith('/') ? path : '/$path';
  html.window.history.replaceState(null, '', '#$normalized');
}
