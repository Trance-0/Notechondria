// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Web URL strategy using browser History API.
void browserPushState(String url) {
  html.window.history.pushState(null, '', url);
}

void browserReplaceState(String url) {
  html.window.history.replaceState(null, '', url);
}
