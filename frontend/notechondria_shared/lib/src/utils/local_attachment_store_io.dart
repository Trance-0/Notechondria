import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'local_attachment_store.dart';

/// Native (desktop / mobile / unit-test) filesystem backend for
/// [LocalAttachmentStore]. Files live under
/// `<app_support>/notechondria/attachments/<note_uuid>/<filename>`
/// with a sibling `<filename>.meta.json` carrying the metadata
/// record.
///
/// Under `flutter test` the `path_provider` plugin isn't registered,
/// so we fall back to the OS temp directory. That keeps unit tests
/// self-contained without a mock-file-system dependency.
Future<LocalAttachmentBackend> openLocalAttachmentBackend() async {
  Directory base;
  try {
    base = await getApplicationSupportDirectory();
  } catch (_) {
    base = await Directory.systemTemp.createTemp('notechondria_attachments_');
  }
  final root = Directory('${base.path}${Platform.pathSeparator}notechondria'
      '${Platform.pathSeparator}attachments');
  if (!await root.exists()) {
    await root.create(recursive: true);
  }
  return _IoLocalAttachmentBackend(root);
}

class _IoLocalAttachmentBackend implements LocalAttachmentBackend {
  _IoLocalAttachmentBackend(this._root);
  final Directory _root;

  String _dirFor(String noteUuid) =>
      '${_root.path}${Platform.pathSeparator}$noteUuid';

  String _pathFor(String noteUuid, String filename) =>
      '${_dirFor(noteUuid)}${Platform.pathSeparator}$filename';

  @override
  Future<void> write(String noteUuid, String filename, Uint8List bytes) async {
    final dir = Directory(_dirFor(noteUuid));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await File(_pathFor(noteUuid, filename)).writeAsBytes(bytes, flush: true);
  }

  @override
  Future<Uint8List?> read(String noteUuid, String filename) async {
    final file = File(_pathFor(noteUuid, filename));
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> writeMetadata(
      String noteUuid, String filename, String metadataJson) async {
    final dir = Directory(_dirFor(noteUuid));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final path = '${_pathFor(noteUuid, filename)}.meta.json';
    await File(path).writeAsString(metadataJson, flush: true);
  }

  @override
  Future<String?> readMetadata(String noteUuid, String filename) async {
    final file = File('${_pathFor(noteUuid, filename)}.meta.json');
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<List<String>> listForNote(String noteUuid) async {
    final dir = Directory(_dirFor(noteUuid));
    if (!await dir.exists()) return const [];
    final entries = <String>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      if (name.endsWith('.meta.json')) continue;
      entries.add(name);
    }
    entries.sort();
    return entries;
  }

  @override
  Future<void> delete(String noteUuid, String filename) async {
    final blob = File(_pathFor(noteUuid, filename));
    if (await blob.exists()) {
      await blob.delete();
    }
    final meta = File('${_pathFor(noteUuid, filename)}.meta.json');
    if (await meta.exists()) {
      await meta.delete();
    }
    // Remove the parent dir when it's empty so a clean-up sweep
    // doesn't leave thousands of empty per-note directories behind.
    final dir = Directory(_dirFor(noteUuid));
    if (await dir.exists()) {
      final remaining = await dir.list().toList();
      if (remaining.isEmpty) {
        await dir.delete();
      }
    }
  }

  @override
  Future<void> deleteAllForNote(String noteUuid) async {
    final dir = Directory(_dirFor(noteUuid));
    if (!await dir.exists()) return;
    await dir.delete(recursive: true);
  }

  @override
  Future<int> totalBytes() async {
    if (!await _root.exists()) return 0;
    var total = 0;
    await for (final entity in _root.list(recursive: true)) {
      if (entity is! File) continue;
      if (entity.path.endsWith('.meta.json')) continue;
      total += await entity.length();
    }
    return total;
  }
}
