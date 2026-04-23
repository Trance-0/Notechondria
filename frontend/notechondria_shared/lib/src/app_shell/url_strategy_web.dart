// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Web URL strategy using the browser History API. Replaces each
/// app's per-app copy. Resolved at compile time when
/// `dart.library.html` is available.
void browserPushState(String url) {
  html.window.history.pushState(null, '', url);
}

void browserReplaceState(String url) {
  html.window.history.replaceState(null, '', url);
}

void browserRedirect(String url) {
  html.window.location.href = url;
}
