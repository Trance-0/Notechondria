import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/notechondria_shared.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalAttachmentStore (native filesystem backend under flutter test)',
      () {
    late LocalAttachmentStore store;

    setUp(() async {
      store = await LocalAttachmentStore.open();
      // The store is a process-wide singleton, so state from prior
      // test cases within this group leaks. Wipe it before each.
      await store.deleteAllForNote('test-uuid-a');
      await store.deleteAllForNote('test-uuid-b');
      await store.deleteAllForNote('local-draft-1');
    });

    test('put + get round-trips bytes + metadata', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final record = await store.put(
        noteUuid: 'test-uuid-a',
        filename: 'one.bin',
        contentType: 'application/octet-stream',
        bytes: bytes,
      );
      expect(record.noteUuid, 'test-uuid-a');
      expect(record.filename, 'one.bin');
      expect(record.contentType, 'application/octet-stream');
      expect(record.sizeBytes, 5);
      expect(record.localUrl, 'local://test-uuid-a/one.bin');

      final fetchedBytes = await store.getBytes(localUrl: record.localUrl);
      expect(fetchedBytes, bytes);

      final fetchedMeta = await store.get(localUrl: record.localUrl);
      expect(fetchedMeta, isNotNull);
      expect(fetchedMeta!.sizeBytes, 5);
    });

    test('parseLocalUrl rejects malformed inputs', () {
      expect(LocalAttachmentStore.parseLocalUrl('local://uuid/file.png'),
          isNotNull);
      expect(LocalAttachmentStore.parseLocalUrl('https://ex.com/file.png'),
          isNull);
      expect(LocalAttachmentStore.parseLocalUrl('local://uuid/sub/nested.png'),
          isNull, reason: 'nested paths are not allowed');
      expect(LocalAttachmentStore.parseLocalUrl('local:///file.png'), isNull,
          reason: 'missing noteUuid');
      expect(LocalAttachmentStore.parseLocalUrl('local://uuid/'), isNull,
          reason: 'missing filename');
    });

    test('listForNote returns sorted entries; deleteAllForNote clears',
        () async {
      await store.put(
        noteUuid: 'test-uuid-b',
        filename: 'b.png',
        contentType: 'image/png',
        bytes: Uint8List.fromList([0]),
      );
      await store.put(
        noteUuid: 'test-uuid-b',
        filename: 'a.png',
        contentType: 'image/png',
        bytes: Uint8List.fromList([0]),
      );
      final listing = await store.listForNote('test-uuid-b');
      expect(listing.map((r) => r.filename).toList(), ['a.png', 'b.png']);

      await store.deleteAllForNote('test-uuid-b');
      expect(await store.listForNote('test-uuid-b'), isEmpty);
    });

    test('put rejects files larger than the per-attachment cap', () async {
      final oversized =
          Uint8List(LocalAttachmentStore.maxBytesPerAttachment + 1);
      expect(
        () => store.put(
          noteUuid: 'test-uuid-a',
          filename: 'big.bin',
          contentType: 'application/octet-stream',
          bytes: oversized,
        ),
        throwsA(isA<LocalAttachmentStoreException>().having(
          (e) => e.message,
          'message carries §1.7 shape',
          contains('Shared.LocalAttachmentStore/put'),
        )),
      );
    });

    test('getBytes throws a §1.7-shaped error for missing entries',
        () async {
      expect(
        () => store.getBytes(localUrl: 'local://test-uuid-a/missing.png'),
        throwsA(isA<LocalAttachmentStoreException>().having(
          (e) => e.message,
          'message',
          contains('Shared.LocalAttachmentStore/get'),
        )),
      );
    });

    test('filename sanitization strips path separators and control bytes',
        () async {
      final record = await store.put(
        noteUuid: 'test-uuid-a',
        filename: 'evil/\u0000slashes\u0001.bin',
        contentType: 'application/octet-stream',
        bytes: Uint8List.fromList([9]),
      );
      expect(record.filename.contains('/'), isFalse);
      expect(record.filename.contains('\u0000'), isFalse);
      expect(record.filename.contains('\u0001'), isFalse);
      final fetched = await store.getBytes(
        noteUuid: 'test-uuid-a',
        filename: record.filename,
      );
      expect(fetched.single, 9);
    });

    test('migrateBase64Drafts moves inline base64 into the store', () async {
      final rawBytes = Uint8List.fromList([10, 20, 30, 40]);
      final base64 = base64Encode(rawBytes);
      final oldDataUri = 'data:image/png;base64,$base64';
      final oldDraft = {
        'id': -1,
        'client_draft_id': 'draft-1',
        'title': 'With attachment',
        'content': '# hi\n\n![sample]($oldDataUri)\n\nafter',
        'metadata_json': jsonEncode({
          'queued_attachments': [
            {
              'filename': 'sample.png',
              'content_type': 'image/png',
              'bytes_base64': base64,
              'queued_at': '2026-04-19T00:00:00Z',
            },
          ],
        }),
      };

      final migrated = await store.migrateBase64Drafts([oldDraft]);
      expect(migrated.length, 1);
      final draft = migrated.single;

      // Markdown body no longer carries the base64 data URI.
      final content = draft['content'] as String;
      expect(content.contains('data:image/png;base64,'), isFalse);
      expect(content.contains('local://local-draft-1/sample.png'), isTrue);

      // queued_attachments entry now points at the store, no base64
      // payload left inline.
      final metadata =
          jsonDecode(draft['metadata_json'] as String) as Map<String, dynamic>;
      final queued = metadata['queued_attachments'] as List;
      expect(queued.length, 1);
      final entry = queued.single as Map<String, dynamic>;
      expect(entry.containsKey('bytes_base64'), isFalse);
      expect(entry['local_url'], 'local://local-draft-1/sample.png');
      expect(entry['size_bytes'], 4);

      // Store actually contains the bytes.
      final fetched = await store.getBytes(
        localUrl: 'local://local-draft-1/sample.png',
      );
      expect(fetched, rawBytes);
    });

    test('migrateBase64Drafts passes through drafts with no queue',
        () async {
      final draft = {
        'id': -2,
        'client_draft_id': 'draft-empty',
        'title': 'No attachments',
        'content': 'plain',
        'metadata_json': jsonEncode({'section': ''}),
      };
      final result = await store.migrateBase64Drafts([draft]);
      expect(result.single['content'], 'plain');
      expect(result.single['metadata_json'], draft['metadata_json']);
    });

    test('totalBytes reports the sum of stored attachment blobs',
        () async {
      // Clean slate: the singleton may carry earlier-test bytes but
      // deleteAllForNote in setUp targets a few known uuids only. The
      // test uses a fresh uuid to keep the assertion deterministic.
      await store.deleteAllForNote('total-bytes-note');
      await store.put(
        noteUuid: 'total-bytes-note',
        filename: 'a.bin',
        contentType: 'application/octet-stream',
        bytes: Uint8List.fromList(List.filled(100, 0)),
      );
      await store.put(
        noteUuid: 'total-bytes-note',
        filename: 'b.bin',
        contentType: 'application/octet-stream',
        bytes: Uint8List.fromList(List.filled(50, 0)),
      );
      final total = await store.totalBytes();
      // Other tests may have left bytes behind in the singleton; at
      // minimum we must have 150 extra.
      expect(total, greaterThanOrEqualTo(150));
      await store.deleteAllForNote('total-bytes-note');
    });
  });
}
