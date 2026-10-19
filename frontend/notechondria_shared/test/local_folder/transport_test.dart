import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:notechondria_shared/local_folder_testing.dart';
import 'package:notechondria_shared/src/components/debug_log.dart';
import 'package:notechondria_shared/src/http/http_client_internals_mixin.dart';
import 'package:notechondria_shared/src/local_folder/folder_layout.dart';
import 'package:notechondria_shared/src/local_folder/folder_lock.dart';
import 'package:notechondria_shared/src/local_folder/folder_messages.dart';
import 'package:notechondria_shared/src/local_folder/local_folder_controller.dart';
import 'package:notechondria_shared/src/local_folder/router.dart';
import 'package:notechondria_shared/src/local_folder/transport.dart';
import 'package:notechondria_shared/src/models/api_debug_snapshot.dart';
import 'package:notechondria_shared/src/startup/startup_budget.dart';

import 'backend_harness.dart';
import 'folder_fixtures.dart';

/// The app side of `send()`: the startup-budget condition of main 2.7.
class _Host with HttpClientInternalsMixin {
  _Host(this.httpClient);
  @override
  final http.Client httpClient;
  @override
  void Function(DebugLogLevel, String, String)? get logger => null;
  @override
  final ValueNotifier<ApiDebugSnapshot?> debugSnapshot = ValueNotifier(null);
  @override
  final ValueNotifier<List<ApiDebugSnapshot>> debugHistory =
      ValueNotifier(const []);
  @override
  String get httpLogTagPrefix => 'Editor';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('folder states (2.8 rule 4)', () {
    test('handshake and ping answer from memory in every state', () async {
      final p = MemoryFolderPlatform();
      final (c, _) = await folderApp(platform: p, open: false);
      p.handleStore.records.clear();
      await c.open();
      expect(c.state, LocalFolderState.needsPick);
      final hs = await callApi(c, 'GET', '/handshake/');
      expect(hs.statusCode, 200);
      expect(mapOf(hs)['service'], 'notechondria-backend');
      expect(mapOf(hs)['storage'], {'backend': 'local-folder', 'label': 'Local folder: Notes'});
      expect((await callApi(c, 'GET', '/ping/')).statusCode, 200);
      final settings = await callApi(c, 'GET', '/settings/');
      expect(settings.statusCode, 503);
      expect(detailOf(settings), LocalFolderMessages.needsPickMissingRecord('Notes'));
    });

    test('opening holds a request, then answers for the state reached',
        () async {
      // Without an index the folder goes to `scanning` first, whose 503 the
      // held request gets; with the index it goes straight to `active`.
      final (first, fs) = await folderApp(open: false);
      final held = callApi(first, 'GET', '/settings/');
      await first.open();
      final scanning = await held;
      expect(scanning.statusCode, 503);
      expect(detailOf(scanning), startsWith('Folder not ready: Shared.LocalFolder/scan — '));
      final (c, _) = await folderApp(fs: fs, open: false);
      expect(c.state, LocalFolderState.opening);
      final pending = callApi(c, 'GET', '/settings/');
      await c.open();
      expect((await pending).statusCode, 200);
    });

    test('opening past the deadline answers with the opening cause', () async {
      final (c, _) = await folderApp(open: false);
      final t = LocalFolderTransport(c,
          readDeadline: const Duration(milliseconds: 30),
          writeDeadline: const Duration(milliseconds: 30));
      final read = await callApi(c, 'GET', '/notes/', client: t);
      expect(read.statusCode, 503);
      expect(detailOf(read),
          LocalFolderMessages.readDeadline('/api/v1/notes/', kDeadlineCauseOpening));
      final write = await callApi(c, 'POST', '/notes/', client: t, json: {'title': 'x'});
      expect(detailOf(write),
          LocalFolderMessages.writeDeadline('POST', '/api/v1/notes/', kDeadlineCauseOpening));
    });

    test('needsPermission, error, and disconnected answer 503, never 401/403',
        () async {
      final fs = await newNotechondriaFolder();
      fs.revoke();
      final (c, _) = await folderApp(fs: fs);
      expect(c.state, LocalFolderState.needsPermission);
      final r = await callApi(c, 'PATCH', '/notes/1/', json: {'content': 'x'});
      expect(r.statusCode, 503);
      expect(detailOf(r), LocalFolderMessages.needsPermission('Notes'));

      final denied = await newNotechondriaFolder()..deny();
      final (e, _) = await folderApp(fs: denied);
      expect(e.state, LocalFolderState.error);
      expect(detailOf(await callApi(e, 'GET', '/notes/')),
          startsWith('Folder unavailable: Shared.LocalFolder/permission — '));

      final (d, _) = await folderApp();
      await d.disconnect();
      expect(detailOf(await callApi(d, 'GET', '/notes/')),
          LocalFolderMessages.disconnectedHereRead('Notes'));
      expect(detailOf(await callApi(d, 'DELETE', '/notes/1/')),
          LocalFolderMessages.disconnectedHereWrite('Notes'));
    });

    test('revoked mid-session: the failing request reports needsPermission',
        () async {
      final (c, fs) = await folderApp();
      final note = await createNote(c);
      fs.revoke();
      final r = await callApi(c, 'PATCH', '/notes/${note['id']}/', json: {'content': 'new'});
      expect(r.statusCode, 503);
      expect(detailOf(r), LocalFolderMessages.needsPermission('Notes'));
      expect(c.state, LocalFolderState.needsPermission);
      expect((await callApi(c, 'GET', '/notes/')).statusCode, 503);
    });

    test('a folder named after a sentinel is scrubbed in every detail (2.5)',
        () async {
      final fs = await newNotechondriaFolder(name: 'Invalid token')..revoke();
      final (c, _) = await folderApp(fs: fs, name: 'Invalid token');
      final detail = detailOf(await callApi(c, 'GET', '/notes/'));
      expect(containsSessionRejectionSentinel(detail), isFalse);
      expect(detail.replaceAll('\u2060', ''),
          LocalFolderMessages.needsPermission('Invalid token'));
    });
  });

  group('routing fallbacks (2.8 rule 2, 4.1)', () {
    test('a path without /api/v1/ answers 404 and sends nothing', () async {
      final (c, _) = await folderApp();
      final r = await callApi(c, 'GET', '/media/a.png', base: 'https://cdn.example');
      expect(r.statusCode, 404);
      expect(detailOf(r), LocalFolderMessages.notApiRoute('GET', '/media/a.png'));
    });

    test('501 details carry no sentinel or deep-link marker (T2)', () async {
      final (c, _) = await folderApp();
      final paths = {
        'POST /auth/login/': LocalFolderMessages.emailSignIn,
        'POST /auth/casdoor/exchange/': LocalFolderMessages.casdoorSignIn,
        'POST /courses/3/subscribe/': LocalFolderMessages.courseNotSubscribed,
        'POST /courses/3/transfer/': LocalFolderMessages.courseNotTransferred,
        'POST /admin/template-courses/restore/':
            LocalFolderMessages.templateCoursesNotRestored,
        'POST /integrations/github/callback/': LocalFolderMessages.githubAppUnavailable,
        'POST /auth/rotate-api-key/': LocalFolderMessages.mcpUnavailable,
      };
      for (final e in paths.entries) {
        final [method, path] = e.key.split(' ');
        final r = await callApi(c, method, path);
        expect(r.statusCode, 501, reason: e.key);
        expect(detailOf(r), e.value, reason: e.key);
      }
      for (final path in [
        '/activity/week/',
        '/planner-events/',
        '/permission-forbidden/403:/',
        '/integrations/github/status/',
      ]) {
        final r = await callApi(c, 'GET', path);
        expect(r.statusCode, 501, reason: path);
        final d = detailOf(r);
        expect(d, contains('—'));
        expect(containsSessionRejectionSentinel(d), isFalse, reason: d);
        expect(containsDeepLinkPrivateNoteMarker(d), isFalse, reason: d);
      }
    });

    test('a base URL prefix is ignored; any host is answered locally', () async {
      final (c, _) = await folderApp();
      final r = await callApi(c, 'GET', '/settings/',
          base: 'http://evil.example:8080/prefix/api/v1');
      expect(r.statusCode, 200);
      expect(r.headers['x-notechondria-backend'], 'local-folder');
      expect(r.headers['content-type'], 'application/json');
    });
  });

  group('deadlines and lock waits (2.9, 6.2 R5, T7(h))', () {
    test('a lock wait cut by the read deadline names the deadline', () async {
      final (c, _) = await folderApp();
      final release = Completer<void>();
      unawaited(c.locks.run(c.lockName, FolderLockMode.exclusive, () => release.future));
      final t = LocalFolderTransport(c, readDeadline: const Duration(milliseconds: 40));
      final r = await callApi(c, 'GET', '/notes/', client: t);
      release.complete();
      expect(r.statusCode, 503);
      expect(detailOf(r),
          LocalFolderMessages.readDeadline('/api/v1/notes/', kDeadlineCauseLockWait));
    });

    test('a full lock wait names the other tab', () async {
      final p = MemoryFolderPlatform(
          locks: MemoryFolderLocks(maxWait: const Duration(milliseconds: 30)));
      final (c, _) = await folderApp(platform: p);
      final release = Completer<void>();
      unawaited(c.locks.run(c.lockName, FolderLockMode.exclusive, () => release.future));
      final read = await callApi(c, 'GET', '/notes/');
      final write = await callApi(c, 'POST', '/notes/', json: {'title': 'x'});
      release.complete();
      expect(detailOf(read), LocalFolderMessages.lockTimeoutRead);
      expect(detailOf(write), LocalFolderMessages.lockTimeoutWrite);
    });
  });

  group('request decoding', () {
    test('multipart settings: fields are read, an avatar file is stored',
        () async {
      final (c, fs) = await folderApp();
      final fields = http.MultipartRequest('PATCH', Uri.parse('$kApiBase/settings/'))
        ..fields['motto'] = 'Local first';
      final r = await http.Response.fromStream(await c.transport.send(fields));
      expect(r.statusCode, 200, reason: r.body);
      expect(mapOf(r)['motto'], 'Local first');
      final avatar = http.MultipartRequest('PATCH', Uri.parse('$kApiBase/settings/'))
        ..files.add(http.MultipartFile.fromBytes('avatar', [1, 2, 3], filename: 'a.png'));
      final a = await http.Response.fromStream(await c.transport.send(avatar));
      expect(a.statusCode, 200, reason: a.body);
      expect('${mapOf(a)['image_url']}', startsWith('nc-folder:///assets/avatar.png?v='));
      expect(fs.paths, contains('assets/avatar.png'));
    });

    test('a handler 501 is route-scrubbed like the router\'s (P1B-4)',
        () async {
      final (c, _) = await folderApp();
      final t = LocalFolderTransport(c,
          router: LocalBackendRouter([
            LocalRoute(
                'GET',
                'later',
                (ctx) async => throw LocalHttpError(
                    501,
                    LocalFolderMessages.laterRelease(
                        'X', ctx.request.method, ctx.request.path))),
          ]));
      const base = 'https://x.example/permission/forbidden/api/v1';
      final r = await callApi(c, 'GET', '/later/', client: t, base: base);
      expect(r.statusCode, 501);
      final d = detailOf(r);
      expect(containsDeepLinkPrivateNoteMarker(d), isFalse, reason: d);
      expect(d.replaceAll('\u2060', ''),
          LocalFolderMessages.laterRelease(
              'X', 'GET', '/permission/forbidden/api/v1/later/'));
    });

    test('a body that is not JSON answers 400 with a 1.8 detail', () async {
      final (c, _) = await folderApp();
      final request = http.Request('POST', Uri.parse('$kApiBase/notes/'))
        ..headers['Content-Type'] = 'application/json'
        ..body = '{not json';
      final r = await http.Response.fromStream(await c.transport.send(request));
      expect(r.statusCode, 400);
      expect(detailOf(r), contains('Shared.LocalFolder.Backend/route — '));
    });
  });

  group('write start and failed roll-forward (2.9, 6.2 R3)', () {
    test('a write that has not started by the deadline changes nothing',
        () async {
      final (c, fs) = await folderApp();
      final t = LocalFolderTransport(c,
          writeDeadline: const Duration(milliseconds: 40),
          router: LocalBackendRouter([
            LocalRoute('POST', 'late', (ctx) async {
              await Future<void>.delayed(const Duration(milliseconds: 80));
              await ctx.writeText('profile/late.txt', 'x');
              return const LocalResponse(200, {});
            }),
            LocalRoute('POST', 'started', (ctx) async {
              await ctx.writeText('profile/a.txt', 'a');
              await Future<void>.delayed(const Duration(milliseconds: 80));
              await ctx.writeText('profile/b.txt', 'b');
              return const LocalResponse(200, {});
            }),
          ]));
      final late = await callApi(c, 'POST', '/late/', client: t);
      expect(late.statusCode, 503);
      expect(detailOf(late),
          LocalFolderMessages.writeDeadline('POST', '/api/v1/late/', kDeadlineCauseStalled));
      expect(fs.exists('profile/late.txt'), isFalse);
      // Once the first write started, the request runs to the end.
      expect((await callApi(c, 'POST', '/started/', client: t)).statusCode, 200);
      expect(fs.exists('profile/b.txt'), isTrue);
    });

    test('writes to a note a stuck record names answer the journal 503',
        () async {
      final (c, fs) = await folderApp();
      final note = await createNote(c, extra: {'client_draft_id': 'd1'});
      final other = await createNote(c, title: 'Other');
      final path = noteBodyPath(uuidHex('${note['uuid']}'));
      final before = fs.textOf(path);
      // A newer build's record cannot roll forward (FolderJournalTooNew),
      // so the paths it names stay pending (R3).
      const opId = '0000000000001-0001-deadbeef';
      await fs.writeText('$kJournalDir/$opId.json', encodeFolderJson({
        'schema_version': 2,
        'op_id': opId,
        'app': 'editor',
        'created_at': '2026-10-19T00:00:00Z',
        'writes': [{'path': path, 'text': 'from a newer build'}],
        'removals': [],
      }));
      final writes = <(String, String, Object?)>[
        ('PATCH', '/notes/${note['id']}/', {'content': 'new'}),
        ('PATCH', '/notes/uuid/${note['uuid']}/', {'content': 'new'}),
        ('DELETE', '/notes/${note['id']}/', null),
        ('POST', '/notes/', {'title': 'Again', 'client_draft_id': 'd1'}),
      ];
      for (final (method, p, json) in writes) {
        final r = await callApi(c, method, p, json: json);
        expect(r.statusCode, 503, reason: '$method $p ${r.body}');
        expect(detailOf(r), LocalFolderMessages.writeBlockedByJournal);
      }
      expect(fs.textOf(path), before);
      expect(decodeFolderManifest(fs.textOf(kManifestPath)!).counter('note'), 2,
          reason: 'the draft upsert did not create a second note');
      // Reads skip the pending note; other notes are read and written.
      expect((await callApi(c, 'GET', '/notes/${note['id']}/')).statusCode, 404);
      expect(listOf(await callApi(c, 'GET', '/notes/')).map((n) => n['id']),
          [other['id']]);
      final ok = await callApi(c, 'PATCH', '/notes/${other['id']}/',
          json: {'content': 'saved'});
      expect(ok.statusCode, 200, reason: ok.body);
    });
  });

  test('local requests skip the startup budget (main 2.7)', () async {
    final (_, fs) = await folderApp();
    final (c, _) = await folderApp(fs: fs, open: false);
    final host = _Host(c.httpClient);
    final budget = StartupRequestBudget(
        source: 'Editor.Startup/bootstrap',
        timeout: const Duration(milliseconds: 10));
    final uri = Uri.parse('$kApiBase/settings/');
    final pending = runWithStartupBudget(budget,
        () => host.send('GET', uri, () => host.httpClient.get(uri)));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await c.open();
    final r = await pending;
    expect(r.statusCode, 200);
    expect(budget.timedOut, isFalse);
  });
}
