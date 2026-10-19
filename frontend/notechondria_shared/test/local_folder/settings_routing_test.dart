import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/src/local_folder/folder_messages.dart';
import 'package:notechondria_shared/src/local_folder/handlers/auth_settings.dart';
import 'package:notechondria_shared/src/local_folder/handlers/records.dart';
import 'package:notechondria_shared/src/local_folder/local_folder_boot.dart';
import 'package:notechondria_shared/src/local_folder/storage_mode_client.dart';
import 'package:notechondria_shared/src/utils/ping_backend.dart';

import 'backend_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('settings, session, and auth answers (F05, F08, 8.4)', () {
    test('every per-device key is dropped from the files and the answer',
        () async {
      final (c, fs) = await folderApp();
      final device = {for (final k in kPerDeviceSettingKeys) k: 'device-$k'};
      final r = await callApi(c, 'PATCH', '/settings/', json: {
        ...device,
        'motto': 'kept',
        'editor_mode': 'G',
        'app_settings': {...device, 'deadline_time_weight': 3, 'github_token': 'ghp_x'},
        'last_seen_versions': {'editor': '0.1.200'},
        'mcp_skill_md': '# skill',
      });
      expect(r.statusCode, 200, reason: r.body);
      final body = mapOf(r);
      final files = [
        fs.textOf(kProfileCreatorPath)!,
        fs.textOf(kProfileSettingsPath)!,
        r.body,
      ];
      for (final key in kPerDeviceSettingKeys) {
        expect(body.containsKey(key), isFalse, reason: key);
        expect((body['app_settings'] as Map).containsKey(key), isFalse, reason: key);
        for (final text in files) {
          expect(text, isNot(contains('device-$key')), reason: key);
        }
      }
      expect(body['motto'], 'kept');
      expect(body['editor_mode'], 'G');
      expect(body['app_settings'], {'deadline_time_weight': 3});
      expect(body['last_seen_versions'], {'editor': '0.1.200'});
      expect(body['mcp_skill_md'], '# skill');
      expect(fs.textOf(kProfileSkillPath), '# skill');
      expect(fs.textOf(kProfileSettingsPath), isNot(contains('ghp_x')));
      expect((await callApi(c, 'PATCH', '/settings/', json: {'editor_mode': 'X'})).statusCode,
          400);
    });

    test('a PATCH of only per-device keys writes nothing', () async {
      final (c, fs) = await folderApp();
      await callApi(c, 'PATCH', '/settings/',
          json: {'theme_preset': 'rose', 'api_base_url': 'https://x.example/api/v1'});
      expect(fs.exists(kProfileCreatorPath), isFalse);
      expect(fs.exists(kProfileSettingsPath), isFalse);
    });

    test('session, logout, Casdoor config, and handshake shapes', () async {
      final (c, _) = await folderApp();
      final session = mapOf(await callApi(c, 'GET', '/auth/session/'));
      expect(session['authenticated'], isTrue);
      expect(session['token'], 'local-folder');
      final user = Map<String, Object?>.from(session['user'] as Map);
      expect(user['is_local_folder'], isTrue);
      expect(user['username'], kFolderDefaultUsername);
      expect(mapOf(await callApi(c, 'POST', '/auth/logout/')), isEmpty);
      expect(mapOf(await callApi(c, 'GET', '/auth/casdoor/config/')), {'configured': false});
      final hs = mapOf(await callApi(c, 'GET', '/handshake/'));
      expect(hs['version'], 'test');
      expect(hs['min_frontend_version'], '');
      expect(hs['api_version'], 'v1');
    });
  });

  group('StorageModeClient routing (2.8)', () {
    test('browserOrCloud forwards unchanged; folder answers in the page',
        () async {
      final inner = RecordingClient();
      var mode = StorageMode.browserOrCloud;
      final (c, _) = await folderApp();
      final client = StorageModeClient(mode: () => mode, local: c.transport, inner: inner);
      await callApi(c, 'GET', '/settings/', client: client);
      expect(inner.requests.single.headers['Authorization'], 'Token local-folder');
      expect(client.routesLocally('GET', Uri.parse('$kApiBase/settings/')), isFalse);
      mode = StorageMode.folder;
      final r = await callApi(c, 'GET', '/settings/', client: client,
          base: 'https://anything.example/api/v1');
      expect(r.headers['x-notechondria-backend'], 'local-folder');
      expect(inner.requests, hasLength(1));
      expect(client.routesLocally('GET', Uri.parse('$kApiBase/handshake/')), isTrue);
    });

    test('the one passthrough: a bare handshake inside runCloudVersionCheck',
        () async {
      final (c, _) = await folderApp();
      final inner = RecordingClient();
      final client = StorageModeClient(
          mode: () => StorageMode.folder, local: c.transport, inner: inner);
      await runCloudVersionCheck(kApiBase, () async {
        expect(client.routesLocally('GET', Uri.parse('$kApiBase/handshake/')), isFalse);
        await callApi(c, 'GET', '/handshake/', client: client);
        final patch = await callApi(c, 'PATCH', '/notes/1/', client: client, json: {'a': 1});
        expect(patch.headers['x-notechondria-backend'], 'local-folder');
        await callApi(c, 'GET', '/handshake/?x=1', client: client);
        await callApi(c, 'GET', '/handshake/', client: client,
            base: 'https://other.example/api/v1');
        await callApi(c, 'GET', '/handshake/', client: client,
            base: 'http://notechondria.trance-0.com/api/v1');
      });
      await callApi(c, 'GET', '/handshake/', client: client);
      expect(inner.requests, hasLength(1));
      final sent = inner.requests.single;
      expect(sent.url.toString(), '$kApiBase/handshake/');
      expect(sent.headers.keys.map((k) => k.toLowerCase()), ['accept']);
    });

    test('loopback http passes; the saved prefix must match', () {
      bool pass(String url, String base) => isVersionCheckPassthrough(
          'GET', Uri.parse(url), bodyLength: 0, savedApiBase: normalizeApiBaseUrl(base));
      expect(pass('http://127.0.0.1:9068/api/v1/handshake/', 'http://127.0.0.1:9068/'), isTrue);
      expect(pass('http://127.0.0.1:9068/api/v1/handshake/', 'http://127.0.0.1:9000/'), isFalse);
      expect(pass('https://h.example/p/api/v1/handshake/', 'https://h.example/p/api/v1'), isTrue);
      expect(pass('https://h.example/api/v1/handshake/', 'https://h.example/p/api/v1'), isFalse);
      expect(pass('https://u:p@h.example/api/v1/handshake/', 'https://h.example'), isFalse);
    });

    test('Check for updates and ping send nothing else to the network',
        () async {
      final inner = RecordingClient();
      final (c, _) = await folderApp();
      final client = StorageModeClient(
          mode: () => StorageMode.folder, local: c.transport, inner: inner);
      final check = await checkCloudVersion(client: client, apiBaseUrl: kApiBase);
      expect(check.ok, isTrue);
      expect(check.version, '9.9.9');
      expect(check.message,
          LocalFolderMessages.versionChecked('https://notechondria.trance-0.com', '9.9.9'));
      final ping = await pingBackend(kApiBase, client: client);
      expect(ping.ok, isTrue);
      expect(ping.detail, 'pong from notechondria-local-folder');
      expect(inner.requests, hasLength(1));
    });
  });
}
