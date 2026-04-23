import 'dart:typed_data';

import 'local_attachment_store.dart';

/// Web backend for [LocalAttachmentStore]. This commit ships an
/// in-memory Map keyed by `(noteUuid, filename)` that survives for
/// the tab's lifetime but not across page reloads. A later round
/// swaps the implementation for an `idb_shim`-backed IndexedDB
/// store; the public contract stays unchanged.
///
/// The in-memory backend is a deliberate placeholder — it lets the
/// editor wiring round land without blocking on IndexedDB plumbing.
/// When a user reloads the page, the draft body still carries
/// `local://` URLs but the bytes are gone; the editor surfaces that
/// as a broken image tile with a `Shared.LocalAttachmentStore/get`
/// error the debug log + SnackBar pick up.
Future<LocalAttachmentBackend> openLocalAttachmentBackend() async {
  return _WebLocalAttachmentBackend();
}

class _WebLocalAttachmentBackend implements LocalAttachmentBackend {
  final Map<String, Uint8List> _blobs = {};
  final Map<String, String> _metas = {};

  String _key(String noteUuid, String filename) => '$noteUuid/$filename';

  @override
  Future<void> write(String noteUuid, String filename, Uint8List bytes) async {
    _blobs[_key(noteUuid, filename)] = bytes;
  }

  @override
  Future<Uint8List?> read(String noteUuid, String filename) async {
    return _blobs[_key(noteUuid, filename)];
  }

  @override
  Future<void> writeMetadata(
      String noteUuid, String filename, String metadataJson) async {
    _metas[_key(noteUuid, filename)] = metadataJson;
  }

  @override
  Future<String?> readMetadata(String noteUuid, String filename) async {
    return _metas[_key(noteUuid, filename)];
  }

  @override
  Future<List<String>> listForNote(String noteUuid) async {
    final prefix = '$noteUuid/';
    final names = _blobs.keys
        .where((k) => k.startsWith(prefix))
        .map((k) => k.substring(prefix.length))
        .toList();
    names.sort();
    return names;
  }

  @override
  Future<void> delete(String noteUuid, String filename) async {
    _blobs.remove(_key(noteUuid, filename));
    _metas.remove(_key(noteUuid, filename));
  }

  @override
  Future<void> deleteAllForNote(String noteUuid) async {
    final prefix = '$noteUuid/';
    _blobs.removeWhere((k, _) => k.startsWith(prefix));
    _metas.removeWhere((k, _) => k.startsWith(prefix));
  }

  @override
  Future<int> totalBytes() async {
    var total = 0;
    for (final bytes in _blobs.values) {
      total += bytes.lengthInBytes;
    }
    return total;
  }
}
