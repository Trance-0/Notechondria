// Harness for the transport and handler tests (not a test file): a
// controller over MemoryFolderPlatform in folder mode, opened to `active`,
// and a helper that sends one request through its transport.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:notechondria_shared/local_folder_testing.dart';
import 'package:notechondria_shared/src/local_folder/local_folder_boot.dart';
import 'package:notechondria_shared/src/local_folder/local_folder_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'folder_fixtures.dart';

const String kApiBase = 'https://notechondria.trance-0.com/api/v1';

StorageModeRecord folderRecord({String name = 'Notes', bool remember = true}) =>
    StorageModeRecord(
        folderId: kTestFolderId,
        folderName: name,
        connectedBy: 'editor',
        connectedAt: '2026-10-19T00:00:00Z',
        remember: remember);

/// An app in folder mode over [fs] (a fresh Notechondria folder by
/// default), opened to `active` unless [open] is false; its log lines go
/// to [logs] when given.
Future<(LocalFolderController, MemoryFolderFs)> folderApp({
  MemoryFolderFs? fs,
  MemoryFolderPlatform? platform,
  String app = 'editor',
  String name = 'Notes',
  bool open = true,
  DateTime Function()? now,
  List<String>? logs,
}) async {
  final folder = fs ?? await newNotechondriaFolder(name: name);
  SharedPreferences.setMockInitialValues(
      {kSharedStorageModeKey: folderRecord(name: name).encode()});
  await LocalFolderBoot.preload();
  final p = platform ?? MemoryFolderPlatform();
  p.handleStore.records[kTestFolderId] = folder;
  final c = LocalFolderController.forTest(
      app: app,
      platform: p,
      boot: LocalFolderBoot.snapshot,
      now: now,
      log: (_, message) => logs?.add(message));
  addTearDown(c.dispose);
  if (open) await c.open();
  return (c, folder);
}

/// One request through [client] (the controller's transport by default).
Future<http.Response> callApi(
  LocalFolderController c,
  String method,
  String path, {
  Object? json,
  http.Client? client,
  String base = kApiBase,
}) async {
  final request = http.Request(method, Uri.parse('$base$path'))
    ..headers['Accept'] = 'application/json'
    ..headers['Authorization'] = 'Token local-folder';
  if (json != null) {
    request
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(json);
  }
  final streamed = await (client ?? c.transport).send(request);
  return http.Response.fromStream(streamed);
}

Object? bodyOf(http.Response r) => r.body.isEmpty ? null : jsonDecode(r.body);

/// One multipart request through the controller's transport; [files] maps
/// a field to its file name and bytes.
Future<http.Response> callMultipart(
  LocalFolderController c,
  String method,
  String path, {
  Map<String, String> fields = const {},
  Map<String, (String, List<int>)> files = const {},
}) async {
  final request = http.MultipartRequest(method, Uri.parse('$kApiBase$path'))
    ..headers['Authorization'] = 'Token local-folder'
    ..fields.addAll(fields);
  files.forEach((field, f) => request.files
      .add(http.MultipartFile.fromBytes(field, f.$2, filename: f.$1)));
  return http.Response.fromStream(await c.transport.send(request));
}

Map<String, Object?> mapOf(http.Response r) =>
    Map<String, Object?>.from(bodyOf(r) as Map);

List<Map<String, Object?>> listOf(http.Response r) => [
      for (final item in bodyOf(r) as List) Map<String, Object?>.from(item as Map),
    ];

String detailOf(http.Response r) => '${mapOf(r)['detail']}';

/// Creates a note through the API and returns its detail payload.
Future<Map<String, Object?>> createNote(LocalFolderController c,
    {String title = 'Note', String content = 'Body', Object? extra}) async {
  final r = await callApi(c, 'POST', '/notes/', json: {
    'title': title,
    'content': content,
    if (extra is Map) ...extra,
  });
  expect(r.statusCode, anyOf(200, 201), reason: r.body);
  return mapOf(r);
}

/// Stands in for the network (8.5): records every request and answers a
/// handshake-shaped body, so a test can assert what left the page.
class RecordingClient extends http.BaseClient {
  final List<http.BaseRequest> requests = [];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return http.StreamedResponse(
        http.ByteStream.fromBytes(utf8.encode('{"version": "9.9.9"}')), 200,
        headers: {'content-type': 'application/json'});
  }
}
