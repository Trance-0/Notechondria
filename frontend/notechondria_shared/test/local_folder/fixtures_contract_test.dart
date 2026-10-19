import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/src/local_folder/local_folder_controller.dart';

import 'backend_harness.dart';

// Contract fixtures (design 8.4): each hand-written backend answer in
// test/fixtures/api_v1/ is compared with the folder backend's answer to the
// same request, by keys and JSON types. Keys starting with `_` are ignored,
// and `_folder_omits` lists top-level keys the folder leaves out on purpose
// (the per-device settings of F08). `backend/notes/test_api_contract.py`
// checks the same files against the Django serializers in CI (Q14).

const String _fixtureDir = 'test/fixtures/api_v1';

/// Seeds the folder as the fixture's `_setup` names; returns placeholder
/// values for `{course_id}`, `{note_id}`, and `{note_uuid}`, plus
/// `{attachment_id}`, `{version_id}`, or `{session_id}` for the setups that
/// add one. A request with `files` is sent as multipart, with its `fields`.
Future<Map<String, Object>> _setup(LocalFolderController c, String setup) async {
  if (setup == 'empty') return {};
  final course = mapOf(await callApi(c, 'POST', '/courses/',
      json: {'title': 'Contract course'}));
  final note = await createNote(c,
      title: 'Contract note',
      content: '# Contract note\n\nBody',
      extra: {'course_id': course['id']});
  if (setup == 'trashed_note') {
    expect((await callApi(c, 'DELETE', '/notes/${note['id']}/')).statusCode, 204);
  }
  final ids = <String, Object>{
    'course_id': course['id']!,
    'note_id': note['id']!,
    'note_uuid': note['uuid']!,
  };
  if (setup == 'note_with_attachment') {
    final r = await callMultipart(c, 'POST', '/notes/${note['id']}/attachments/',
        files: {'file': ('contract.png', _png)});
    ids['attachment_id'] = mapOf(r)['id']!;
  } else if (setup == 'note_with_snapshot') {
    final r = await callApi(c, 'POST', '/notes/${note['id']}/snapshot/',
        json: {'reason': 'manual'});
    ids['version_id'] = mapOf(r)['id']!;
  } else if (setup == 'note_with_session') {
    final r = await callApi(c, 'POST', '/note-sessions/',
        json: {'note_id': note['id']});
    ids['session_id'] = mapOf(r)['id']!;
  }
  return ids;
}

final List<int> _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

Object? _substitute(Object? value, Map<String, Object> ids) {
  if (value is String) {
    for (final e in ids.entries) {
      if (value == '{${e.key}}') return e.value;
      value = (value as String).replaceAll('{${e.key}}', '${e.value}');
    }
    return value;
  }
  if (value is List) return [for (final v in value) _substitute(v, ids)];
  if (value is Map) {
    return {for (final e in value.entries) '${e.key}': _substitute(e.value, ids)};
  }
  return value;
}

/// Same keys and JSON types; null on either side is compatible, and list
/// elements are compared when both lists are non-empty. [omit] holds
/// dotted key paths from the body root (`app_settings.theme_mode`).
void expectSameShape(Object? local, Object? fixture, String at,
    {Set<String> omit = const {}, String path = ''}) {
  if (fixture == null || local == null) return;
  String sub(Object k) => path.isEmpty ? '$k' : '$path.$k';
  if (fixture is Map) {
    expect(local, isA<Map>(), reason: at);
    final keys = {
      for (final k in fixture.keys)
        if (!'$k'.startsWith('_') && !omit.contains(sub(k))) '$k',
    };
    expect({for (final k in (local as Map).keys) '$k'}, keys, reason: '$at keys');
    for (final k in keys) {
      expectSameShape(local[k], fixture[k], '$at.$k', omit: omit, path: sub(k));
    }
  } else if (fixture is List) {
    expect(local, isA<List>(), reason: at);
    if (fixture.isNotEmpty && (local as List).isNotEmpty) {
      expectSameShape(local.first, fixture.first, '$at[0]',
          omit: omit, path: '$path[0]');
    }
  } else if (fixture is bool) {
    expect(local, isA<bool>(), reason: at);
  } else if (fixture is int) {
    expect(local, isA<int>(), reason: at);
  } else if (fixture is String) {
    expect(local, isA<String>(), reason: at);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final files = Directory(_fixtureDir)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('every fixture names its source', () {
    expect(files, isNotEmpty);
    for (final f in files) {
      final json = jsonDecode(f.readAsStringSync()) as Map;
      expect(json['_source'], isA<String>(), reason: f.path);
      expect(json['request'], isA<Map>(), reason: f.path);
    }
  });

  for (final file in files) {
    final name = file.uri.pathSegments.last;
    test('$name: the folder answers with the same keys and types', () async {
      final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final (c, _) = await folderApp();
      final ids = await _setup(c, '${fixture['_setup'] ?? 'empty'}');
      final request = fixture['request'] as Map<String, dynamic>;
      final path = '${_substitute(request['path'], ids)}';
      final files = request['files'] as Map<String, dynamic>?;
      final r = files == null
          ? await callApi(c, '${request['method']}',
              path.replaceFirst('/api/v1', ''),
              json: _substitute(request['body'], ids))
          : await callMultipart(
              c, '${request['method']}', path.replaceFirst('/api/v1', ''),
              fields: {
                for (final e in (request['fields'] as Map? ?? const {}).entries)
                  '${e.key}': '${e.value}',
              },
              files: {
                for (final e in files.entries)
                  e.key: (
                    '${(e.value as Map)['filename']}',
                    base64Decode('${(e.value as Map)['base64']}'),
                  ),
              });
      expect(r.statusCode, fixture['status'], reason: r.body);
      expectSameShape(bodyOf(r), fixture['body'], name, omit: {
        for (final k in fixture['_folder_omits'] as List? ?? const []) '$k',
      });
    });
  }
}
