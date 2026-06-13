import 'dart:async';
import 'dart:typed_data';

import 'package:idb_shim/idb_shim.dart' as idb;

import 'local_attachment_store.dart';

const _dbName = 'notechondria_attachments';
const _dbVersion = 1;
const _storeName = 'entries';

/// Web backend for [LocalAttachmentStore] backed by IndexedDB via
/// `idb_shim`. Replaces the earlier in-memory stub so attachments
/// survive page reloads within the same browser origin.
///
/// Database: `notechondria_attachments` (version 1)
///   Object store: `entries` keyed by `key` (String).
///     Value shape: `{key, bytes, metadataJson}`
///
/// The `metadataJson` field holds the JSON-serialized record written
/// by `LocalAttachmentStore.put` / `writeMetadata` (content type,
/// size, creation time — see [LocalAttachment.toMetadata]).
Future<LocalAttachmentBackend> openLocalAttachmentBackend() async {
  final factory = idb.idbFactoryNative;
  final db =
      await factory.open(_dbName, version: _dbVersion, onUpgradeNeeded: (ev) {
    final database = ev.database;
    if (!database.objectStoreNames.contains(_storeName)) {
      database.createObjectStore(_storeName, keyPath: 'key');
    }
  });
  return _WebLocalAttachmentBackend(db);
}

class _WebLocalAttachmentBackend implements LocalAttachmentBackend {
  final idb.Database _db;

  _WebLocalAttachmentBackend(this._db);

  String _key(String noteUuid, String filename) =>
      'local://$noteUuid/$filename';

  @override
  Future<void> write(String noteUuid, String filename, Uint8List bytes) async {
    final tx = _db.transaction(_storeName, idb.idbModeReadWrite);
    final store = tx.objectStore(_storeName);
    await store.put(<String, dynamic>{
      'key': _key(noteUuid, filename),
      'bytes': bytes,
    });
    await tx.completed;
  }

  @override
  Future<Uint8List?> read(String noteUuid, String filename) async {
    final tx = _db.transaction(_storeName, idb.idbModeReadOnly);
    final store = tx.objectStore(_storeName);
    final result = await store.getObject(_key(noteUuid, filename));
    if (result == null) return null;
    return (result as Map<String, dynamic>)['bytes'] as Uint8List?;
  }

  @override
  Future<void> writeMetadata(
      String noteUuid, String filename, String metadataJson) async {
    final key = _key(noteUuid, filename);
    final tx = _db.transaction(_storeName, idb.idbModeReadWrite);
    final store = tx.objectStore(_storeName);
    final existing = await store.getObject(key);
    if (existing != null) {
      final record = existing as Map<String, dynamic>;
      record['metadataJson'] = metadataJson;
      await store.put(record);
    } else {
      await store.put(<String, dynamic>{
        'key': key,
        'metadataJson': metadataJson,
      });
    }
    await tx.completed;
  }

  @override
  Future<String?> readMetadata(String noteUuid, String filename) async {
    final tx = _db.transaction(_storeName, idb.idbModeReadOnly);
    final store = tx.objectStore(_storeName);
    final result = await store.getObject(_key(noteUuid, filename));
    if (result == null) return null;
    return (result as Map<String, dynamic>)['metadataJson']?.toString();
  }

  @override
  Future<List<String>> listForNote(String noteUuid) async {
    final prefix = 'local://$noteUuid/';
    final names = <String>[];
    final tx = _db.transaction(_storeName, idb.idbModeReadOnly);
    final store = tx.objectStore(_storeName);
    await for (final cursor in store.openCursor()) {
      final key = cursor.key as String;
      if (key.startsWith(prefix)) {
        names.add(key.substring(prefix.length));
      }
    }
    await tx.completed;
    names.sort();
    return names;
  }

  @override
  Future<void> delete(String noteUuid, String filename) async {
    final tx = _db.transaction(_storeName, idb.idbModeReadWrite);
    final store = tx.objectStore(_storeName);
    await store.delete(_key(noteUuid, filename));
    await tx.completed;
  }

  @override
  Future<void> deleteAllForNote(String noteUuid) async {
    final prefix = 'local://$noteUuid/';
    final tx = _db.transaction(_storeName, idb.idbModeReadWrite);
    final store = tx.objectStore(_storeName);
    final keysToDelete = <String>[];
    await for (final cursor in store.openCursor()) {
      final key = cursor.key as String;
      if (key.startsWith(prefix)) {
        keysToDelete.add(key);
      }
    }
    for (final key in keysToDelete) {
      await store.delete(key);
    }
    await tx.completed;
  }

  @override
  Future<int> totalBytes() async {
    var total = 0;
    final tx = _db.transaction(_storeName, idb.idbModeReadOnly);
    final store = tx.objectStore(_storeName);
    await for (final cursor in store.openCursor()) {
      final record = cursor.value as Map<String, dynamic>;
      final bytes = record['bytes'] as Uint8List?;
      if (bytes != null) {
        total += bytes.lengthInBytes;
      }
    }
    await tx.completed;
    return total;
  }
}
