// Local folder smoke checks, client level (design 8.5, Phase 1): the
// editor's real HttpNotechondriaClient over a LocalFolderController's
// StorageModeClient and MemoryFolderPlatform, inside http.runWithClient
// with a recorder, and no app wiring. App-level checks join in Phase 2.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:notechondria_shared/local_folder_testing.dart';
import 'package:notechondria_shared/notechondria_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:editor_app/main.dart' as app;

const String _base = 'https://notechondria.trance-0.com/api/v1';
const String _token = 'local-folder';

/// Stands in for every `http.Client()` (8.5): records each request.
class _Recorder extends http.BaseClient {
  final List<http.BaseRequest> requests = [];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return http.StreamedResponse(
        http.ByteStream.fromBytes(utf8.encode(jsonEncode({
          'service': 'notechondria-backend',
          'api_version': 'v1',
          'version': '9.9.9',
        }))),
        200,
        headers: {'content-type': 'application/json'});
  }
}

/// A dart:io client created outside the zone fails the test (8.5).
class _NoDartIo extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('dart:io HttpClient created during a folder smoke test');
}

/// A browser-local controller that connects an empty folder, as the
/// sign-in option does.
Future<(LocalFolderController, MemoryFolderFs)> _connected() async {
  SharedPreferences.setMockInitialValues({});
  await LocalFolderBoot.preload();
  final platform = MemoryFolderPlatform();
  final folder = MemoryFolderFs(name: 'Smoke');
  platform.picker.willReturn(folder);
  final c = LocalFolderController.forTest(
      app: 'editor', platform: platform, boot: LocalFolderBoot.snapshot);
  addTearDown(c.dispose);
  final pick = await c.pickForConnect();
  await c.connectPicked(pick!, remember: false);
  expect(c.state, LocalFolderState.active);
  return (c, folder);
}

Future<String> _error(Future<Object?> call) async {
  try {
    await call;
  } catch (e) {
    return '$e';
  }
  fail('expected the request to fail');
}

void registerLocalFolderSmokeTests() {
  group('local folder, client level (Phase 1)', () {
    HttpOverrides? previous;
    setUp(() {
      previous = HttpOverrides.current;
      HttpOverrides.global = _NoDartIo();
    });
    tearDown(() => HttpOverrides.global = previous);

    test('notes live in the folder and nothing reaches the network', () async {
      final recorder = _Recorder();
      await http.runWithClient(() async {
        final (c, fs) = await _connected();
        final client = app.HttpNotechondriaClient(
            httpClient: c.httpClient, initialBaseUrl: _base);
        final note = await client
            .createNote(_token, {'title': 'Smoke', 'content': '# Smoke\n\nBody'});
        final hex = '${note['uuid']}'.replaceAll('-', '');
        expect(fs.exists('notes/$hex.md'), isTrue);
        expect(fs.exists('notes/$hex.meta.json'), isTrue);
        final id = note['id'] as int;
        await client.updateNote(_token, id, {'content': 'Edited'});
        expect(fs.textOf('notes/$hex.md'), contains('Edited'));
        await client.deleteNote(_token, id);
        expect(fs.exists('trash/notes/$hex.md'), isTrue);
        await client.restoreDeletedNote(_token, id);
        await client.deleteNote(_token, id);
        expect((await client.emptyDeletedNotes(_token))['count'], 1);
        expect(fs.paths.where((p) => p.contains(hex)), isEmpty);
        final handshake = await client.verifyHandshake(_base);
        expect(handshake.ok, isTrue);
        final ping = await pingBackend(_base, client: c.httpClient);
        expect(ping.ok, isTrue);
        // Multipart reaches the transport (the 8 `_httpClient.send` sites):
        // attachments arrive in Phase 2, so the folder answers 501.
        final upload = await _error(client.uploadNoteAttachment(_token, id,
            XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'a.png')));
        expect(upload, contains('Feature not available yet: '));
      }, () => recorder);
      expect(recorder.requests, isEmpty);
    });

    test('revoked mid-session: 503 with the needsPermission detail, no request',
        () async {
      final recorder = _Recorder();
      await http.runWithClient(() async {
        final (c, fs) = await _connected();
        final client = app.HttpNotechondriaClient(
            httpClient: c.httpClient, initialBaseUrl: _base);
        final note = await client.createNote(_token, {'title': 'Draft'});
        fs.revoke();
        final save = await _error(
            client.updateNote(_token, note['id'] as int, {'content': 'x'}));
        expect(save, contains(LocalFolderMessages.needsPermission('Smoke')));
        expect(c.state, LocalFolderState.needsPermission);
        final list = await _error(client.listNotes(token: _token));
        expect(list, contains('Folder access lost: '));
        expect(list.toLowerCase(), isNot(contains('session rejected:')));
        expect((await pingBackend(_base, client: c.httpClient)).ok, isTrue);
      }, () => recorder);
      expect(recorder.requests, isEmpty);
    });

    test('Check for updates is the one request that leaves the page',
        () async {
      final recorder = _Recorder();
      await http.runWithClient(() async {
        final (c, _) = await _connected();
        final client = app.HttpNotechondriaClient(
            httpClient: c.httpClient, initialBaseUrl: _base);
        final check = await checkCloudVersion(client: c.httpClient, apiBaseUrl: _base);
        expect(check.ok, isTrue);
        await runCloudVersionCheck(_base, () async {
          await client.createNote(_token, {'title': 'inside the zone'});
        });
      }, () => recorder);
      expect(recorder.requests, hasLength(1));
      expect(recorder.requests.single.url.toString(), '$_base/handshake/');
      expect(recorder.requests.single.headers.containsKey('Authorization'), isFalse);
    });
  });
}
