// Attachments, covers, and the avatar (storage rules 3.6; F09, F33, F34).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/src/local_folder/folder_layout.dart';
import 'package:notechondria_shared/src/local_folder/folder_messages.dart';
import 'package:notechondria_shared/src/local_folder/handlers/attachments.dart';
import 'package:notechondria_shared/src/local_folder/note_codec.dart';

import 'backend_harness.dart';

final List<int> _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('file names', () {
    test('sanitizeFileName keeps letters, digits, dot, dash, underscore', () {
      expect(sanitizeFileName('Diagram 1 (final).png'), 'Diagram_1__final_.png');
      expect(sanitizeFileName('../../etc/passwd'), 'passwd');
      expect(sanitizeFileName('.hidden'), 'hidden');
      expect(sanitizeFileName(''), 'untitled');
      expect(sanitizeFileName('x.crswap'), 'x.crswap_');
      expect(sanitizeFileName('细胞图.png'), '细胞图.png');
      final long = sanitizeFileName('${'a' * 300}.png');
      expect(long.length, 120);
      expect(long, endsWith('.png'));
    });

    test('uniqueFileName adds -2, -3 before the extension', () {
      expect(uniqueFileName('a.png', {'a.png', 'a-2.png'}), 'a-3.png');
      expect(uniqueFileName('a', {'a'}), 'a-2');
      expect(uniqueFileName('b.png', {'a.png'}), 'b.png');
    });
  });

  group('attachments', () {
    test('upload writes the file and attachments.json; list and delete', () async {
      final (c, fs) = await folderApp();
      final note = await createNote(c, title: 'Cells');
      final hex = uuidHex('${note['uuid']}');
      final up = await callMultipart(c, 'POST', '/notes/${note['id']}/attachments/',
          files: {'file': ('Cell diagram.png', _png)});
      expect(up.statusCode, 201, reason: up.body);
      final a = mapOf(up);
      final path = '$kAssetsDir/notes/$hex/attachments/Cell_diagram.png';
      expect(a['url'], 'nc-folder:///$path');
      expect(a['original_filename'], 'Cell diagram.png');
      expect(a['file_size'], _png.length);
      expect(a['note_id'], note['id']);
      expect(a['id'], 1);
      expect(await fs.readBytes(path), _png);
      final index = jsonDecode(fs.textOf(attachmentsIndexPath(hex))!) as Map;
      expect((index['attachments'] as List).single['filename'], 'Cell_diagram.png');
      expect((await readFolderManifest(fs))!.counter('attachment'), 1);

      // A second file of the same name gets its own name; uuid routes agree.
      final up2 = await callMultipart(
          c, 'POST', '/notes/uuid/${note['uuid']}/attachments/',
          files: {'file': ('Cell diagram.png', [1, 2, 3])});
      expect(up2.statusCode, 201, reason: up2.body);
      expect(mapOf(up2)['url'], endsWith('/Cell_diagram-2.png'));
      final byId = listOf(await callApi(c, 'GET', '/notes/${note['id']}/attachments/'));
      final byUuid =
          listOf(await callApi(c, 'GET', '/notes/uuid/${note['uuid']}/attachments/'));
      expect([for (final x in byId) x['id']], [2, 1], reason: 'newest first');
      expect(byUuid, byId);

      final del = await callApi(c, 'DELETE', '/notes/${note['id']}/attachments/1/');
      expect(del.statusCode, 204);
      expect(fs.paths, isNot(contains(path)));
      final left = listOf(await callApi(c, 'GET', '/notes/${note['id']}/attachments/'));
      expect([for (final x in left) x['id']], [2]);
      final gone = await callApi(
          c, 'DELETE', '/notes/uuid/${note['uuid']}/attachments/1/');
      expect(gone.statusCode, 404);
      expect(detailOf(gone), LocalFolderMessages.attachmentNotFound(note['id'] as int, 1));
    });

    test('a request without a file part or over 20 MB answers 400', () async {
      final (c, fs) = await folderApp();
      final note = await createNote(c);
      final none = await callMultipart(c, 'POST', '/notes/${note['id']}/attachments/',
          fields: {'x': 'y'});
      expect(none.statusCode, 400);
      expect(detailOf(none),
          startsWith('Attachment not saved: Shared.LocalFolder.Backend/attachments — '));
      final big = await callMultipart(c, 'POST', '/notes/${note['id']}/attachments/',
          files: {'file': ('big.bin', List<int>.filled(kMaxAttachmentBytes + 1, 0))});
      expect(big.statusCode, 400);
      expect(detailOf(big), contains('larger than 20 MB'));
      expect(fs.paths.where((p) => p.startsWith('$kAssetsDir/')), isEmpty);
    });

    test('an unknown or trashed note answers 404', () async {
      final (c, _) = await folderApp();
      final missing = await callApi(c, 'GET', '/notes/99/attachments/');
      expect(missing.statusCode, 404);
      expect(detailOf(missing), LocalFolderMessages.noteNotFound(99));
      final note = await createNote(c);
      await callApi(c, 'DELETE', '/notes/${note['id']}/');
      final trashed = await callMultipart(
          c, 'POST', '/notes/${note['id']}/attachments/',
          files: {'file': ('a.png', _png)});
      expect(trashed.statusCode, 404);
    });

    test('empty trash removes the attachment files', () async {
      final (c, fs) = await folderApp();
      final note = await createNote(c);
      await callMultipart(c, 'POST', '/notes/${note['id']}/attachments/',
          files: {'file': ('a.png', _png)});
      await callMultipart(c, 'POST', '/notes/${note['id']}/cover/',
          files: {'cover': ('c.png', _png)});
      await callApi(c, 'DELETE', '/notes/${note['id']}/');
      expect((await callApi(c, 'DELETE', '/notes/deleted/empty/')).statusCode, 200);
      final hex = uuidHex('${note['uuid']}');
      expect(fs.paths.where((p) => p.contains(hex)), isEmpty);
    });
  });

  group('covers', () {
    test('upload, replace with another type, and clear', () async {
      final (c, fs) = await folderApp(now: () => DateTime.utc(2026, 10, 19, 12));
      final note = await createNote(c);
      final hex = uuidHex('${note['uuid']}');
      final up = await callMultipart(c, 'POST', '/notes/${note['id']}/cover/',
          files: {'cover': ('photo.PNG', _png)});
      expect(up.statusCode, 200, reason: up.body);
      final ms = DateTime.utc(2026, 10, 19, 12).millisecondsSinceEpoch;
      expect(mapOf(up)['cover_image_url'],
          'nc-folder:///$kAssetsDir/notes/$hex/cover.png?v=$ms');
      expect(mapOf(up).containsKey('content'), isFalse, reason: 'a note summary');
      expect(await fs.readBytes('$kAssetsDir/notes/$hex/cover.png'), _png);
      final listed = listOf(await callApi(c, 'GET', '/notes/'));
      expect(listed.single['cover_image_url'], mapOf(up)['cover_image_url']);

      final jpg = await callMultipart(c, 'POST', '/notes/${note['id']}/cover/',
          files: {'cover': ('photo.jpg', [1, 2])});
      expect(mapOf(jpg)['cover_image_url'], contains('/cover.jpg?v='));
      expect(fs.paths, isNot(contains('$kAssetsDir/notes/$hex/cover.png')));

      final clear = await callApi(c, 'DELETE', '/notes/${note['id']}/cover/');
      expect(clear.statusCode, 200);
      expect(mapOf(clear)['cover_image_url'], '');
      expect(fs.paths.where((p) => p.contains('/cover.')), isEmpty);
      final again = await callApi(c, 'DELETE', '/notes/${note['id']}/cover/');
      expect(again.statusCode, 200, reason: 'clearing twice is harmless');
    });

    test('a cover over 5 MB or without a cover part answers 400', () async {
      final (c, _) = await folderApp();
      final note = await createNote(c);
      final big = await callMultipart(c, 'POST', '/notes/${note['id']}/cover/',
          files: {'cover': ('a.png', List<int>.filled(kMaxCoverBytes + 1, 0))});
      expect(big.statusCode, 400);
      final wrongField = await callMultipart(c, 'POST', '/notes/${note['id']}/cover/',
          files: {'file': ('a.png', _png)});
      expect(wrongField.statusCode, 400);
      expect(detailOf(wrongField), startsWith('Cover image not set: '));
    });
  });

  group('avatar (PATCH /settings/ multipart)', () {
    test('stores assets/avatar.<ext> and replaces the old file', () async {
      final (c, fs) = await folderApp();
      final r = await callMultipart(c, 'PATCH', '/settings/',
          fields: {'motto': 'Hi'}, files: {'avatar': ('me.png', _png)});
      expect(r.statusCode, 200, reason: r.body);
      final url = '${mapOf(r)['image_url']}';
      expect(url, startsWith('$kFolderUrlPrefix$kAssetsDir/avatar.png?v='));
      expect(mapOf(r)['image_upload_url'], url);
      expect(mapOf(r)['motto'], 'Hi');
      expect(await fs.readBytes('$kAssetsDir/avatar.png'), _png);
      final again = await callMultipart(c, 'PATCH', '/settings/',
          files: {'avatar': ('me.jpg', [9, 9])});
      expect(mapOf(again)['image_url'], contains('/avatar.jpg?v='));
      expect(fs.paths, isNot(contains('$kAssetsDir/avatar.png')));
      final settings = mapOf(await callApi(c, 'GET', '/settings/'));
      expect(settings['image_url'], mapOf(again)['image_url']);
      expect(fs.textOf('profile/creator.json'), contains('avatar.jpg'));
    });

    test('an invalid field writes no avatar file', () async {
      final (c, fs) = await folderApp();
      final r = await callMultipart(c, 'PATCH', '/settings/',
          fields: {'editor_mode': 'X'}, files: {'avatar': ('me.png', _png)});
      expect(r.statusCode, 400);
      expect(fs.paths.where((p) => p.startsWith('$kAssetsDir/')), isEmpty);
    });
  });
}
