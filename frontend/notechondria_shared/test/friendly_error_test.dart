import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/notechondria_shared.dart';

/// `friendlyError` maps raw exception strings to clean, localized
/// user-facing messages and passes already-human backend messages
/// through unchanged.
void main() {
  late dynamic en;
  late dynamic zh;

  setUp(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  test('browser fetch failure -> friendly network message', () {
    expect(friendlyError(en, 'ClientException: Failed to fetch, uri=...'),
        en.errorNetwork);
    expect(friendlyError(zh, 'ClientException: Failed to fetch'),
        zh.errorNetwork);
  });

  test('socket / connection errors -> network message', () {
    expect(friendlyError(en, 'SocketException: Connection refused'),
        en.errorNetwork);
    expect(
        friendlyError(en, 'Exception: Connection reset by peer'),
        en.errorNetwork);
  });

  test('timeouts -> timeout message', () {
    expect(friendlyError(en, 'TimeoutException after 0:00:08'),
        en.errorTimeout);
  });

  test('5xx -> server message', () {
    expect(friendlyError(en, 'backend HTTP 503: service unavailable'),
        en.errorServer);
  });

  test('already-human backend message passes through unchanged', () {
    expect(friendlyError(en, 'Title is required.'), 'Title is required.');
    // The "Exception: " prefix is stripped.
    expect(friendlyError(en, 'Exception: Title is required.'),
        'Title is required.');
  });

  test('empty error -> network message (best guess)', () {
    expect(friendlyError(en, ''), en.errorNetwork);
    expect(friendlyError(en, null), en.errorNetwork);
  });
}
