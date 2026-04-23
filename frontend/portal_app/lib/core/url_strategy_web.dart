// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void browserRedirect(String url) {
  html.window.location.href = url;
}
