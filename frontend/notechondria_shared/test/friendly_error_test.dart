import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/notechondria_shared.dart';

/// `friendlyError` maps raw exception strings to clean, localized
/// AGENTS.md §1.8 messages (consequence, module/process, cause) and passes
/// already-human backend messages through unchanged.
void main() {
  late AppLocalizations en;
  late AppLocalizations zh;

  setUp(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  test('browser fetch failure -> network message naming the module', () {
    // The HTTP layer's shaped failure carries its own module/process.
    expect(
        friendlyError(
            en,
            'Exception: Server request failed: Portal.HTTP/request — client '
            'failed to fetch GET https://x/api/v1/front-page/ before a '
            'response arrived (ClientException).'),
        en.errorNetwork('Portal.HTTP/request'));
    // A bare browser error falls back to the caller's module/process.
    expect(
        friendlyError(zh, 'ClientException: Failed to fetch',
            source: 'Editor.Startup/initial_data'),
        zh.errorNetwork('Editor.Startup/initial_data'));
  });

  test('socket / connection errors -> network message', () {
    expect(friendlyError(en, 'SocketException: Connection refused'),
        en.errorNetwork('Backend.HTTP/request'));
    expect(friendlyError(en, 'Exception: Connection reset by peer'),
        en.errorNetwork('Backend.HTTP/request'));
  });

  test('timeouts -> timeout message', () {
    expect(friendlyError(en, 'TimeoutException after 0:00:08'),
        en.errorTimeout('Backend.HTTP/request'));
  });

  test('startup timeout -> backend-unavailable message with its bound', () {
    const timeout = BackendStartupTimeout(
      source: 'Portal.Startup/bootstrap',
      request: 'GET /api/v1/front-page/',
      timeout: Duration(seconds: 10),
    );
    const skipped = BackendStartupTimeout(
      source: 'Portal.Startup/bootstrap',
      request: 'GET /api/v1/courses/',
      timeout: Duration(seconds: 10),
      skipped: true,
    );
    final message = friendlyError(en, timeout.toString());
    expect(message, en.startupBackendTimeout('Portal.Startup/bootstrap', 10));
    expect(message, contains('did not respond within 10s'));
    expect(friendlyError(en, skipped.toString()), message);
    expect(friendlyError(zh, timeout.toString()),
        zh.startupBackendTimeout('Portal.Startup/bootstrap', 10));
  });

  test('5xx -> server message', () {
    expect(friendlyError(en, 'backend HTTP 503: service unavailable'),
        en.errorServer('Backend.HTTP/request'));
  });

  test('already-human backend message passes through unchanged', () {
    expect(friendlyError(en, 'Title is required.'), 'Title is required.');
    // The "Exception: " prefix is stripped.
    expect(friendlyError(en, 'Exception: Title is required.'),
        'Title is required.');
  });

  test('empty error -> network message (best guess)', () {
    expect(friendlyError(en, ''), en.errorNetwork('Backend.HTTP/request'));
    expect(friendlyError(en, null), en.errorNetwork('Backend.HTTP/request'));
  });
}
