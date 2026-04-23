import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'local_attachment_store_io.dart'
    if (dart.library.html) 'local_attachment_store_web.dart'
    as backend;

/// A single record in the attachment store. Returned from [LocalAttachmentStore.get]
/// and [LocalAttachmentStore.list].
class LocalAttachment {
  const LocalAttachment({
    required this.noteUuid,
    required this.filename,
    required this.contentType,
    required this.sizeBytes,
    required this.createdAt,
  });

  /// The parent note's server UUID. On a local-only note (no server uuid
  /// yet) the caller may substitute the draft's client id prefixed with
  /// `local-`.
  final String noteUuid;

  /// Sanitized leaf filename; forms the last segment of the `local://`
  /// URL as well as the on-disk name.
  final String filename;

  final String contentType;
  final int sizeBytes;
  final DateTime createdAt;

  /// Canonical in-app URL embedded in note markdown. Read by the
  /// editor's markdown preview to resolve the bytes back.
  String get localUrl => 'local://$noteUuid/$filename';

  Map<String, dynamic> toMetadata() {
    return {
      'note_uuid': noteUuid,
      'filename': filename,
      'content_type': contentType,
      'size_bytes': sizeBytes,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }
}

/// Thrown from [LocalAttachmentStore] methods when a precondition is
/// violated (missing file, write rejected, unknown url). The message
/// follows the canonical AGENTS.md \u00a71.7
/// `"<consequence>: <module>/<process> \u2014 <cause>"` shape so
/// callers can surface it verbatim to the debug log and the user.
class LocalAttachmentStoreException implements Exception {
  LocalAttachmentStoreException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Platform-split local attachment store. On native (desktop /
/// mobile) attachments are written as files under
/// `<app_support>/notechondria/attachments/<note_uuid>/<filename>`.
/// On web the default backend is an in-memory map scoped to the
/// current tab (a later round will swap this for IndexedDB once the
/// web test harness is in place).
///
/// The class is a thin facade over a platform-specific backend
/// selected via conditional import. All methods are async so web
/// and native can share the same interface.
class LocalAttachmentStore {
  /// Async singleton. The first call opens/creates the native
  /// directory or initializes the web in-memory store.
  static Future<LocalAttachmentStore> open() async {
    if (_instance != null) return _instance!;
    final impl = await backend.openLocalAttachmentBackend();
    _instance = LocalAttachmentStore._(impl);
    return _instance!;
  }

  LocalAttachmentStore._(this._backend);

  final LocalAttachmentBackend _backend;
  static LocalAttachmentStore? _instance;

  /// Writes [bytes] under `(noteUuid, filename)`. Returns the
  /// canonical record. Overwrites silently when the key already
  /// exists. Size checked against [maxBytesPerAttachment] before the
  /// write hits the backend.
  Future<LocalAttachment> put({
    required String noteUuid,
    required String filename,
    required String contentType,
    required Uint8List bytes,
  }) async {
    if (bytes.lengthInBytes > maxBytesPerAttachment) {
      throw LocalAttachmentStoreException(
        'Attachment not stored: '
        'Shared.LocalAttachmentStore/put \u2014 '
        'file is ${bytes.lengthInBytes} bytes but the per-file cap '
        'is $maxBytesPerAttachment.',
      );
    }
    final saneUuid = _sanitize(noteUuid);
    final saneFilename = _sanitize(filename);
    if (saneUuid.isEmpty || saneFilename.isEmpty) {
      throw LocalAttachmentStoreException(
        'Attachment not stored: '
        'Shared.LocalAttachmentStore/put \u2014 '
        'noteUuid and filename must be non-empty after sanitization.',
      );
    }
    await _backend.write(saneUuid, saneFilename, bytes);
    final record = LocalAttachment(
      noteUuid: saneUuid,
      filename: saneFilename,
      contentType: contentType,
      sizeBytes: bytes.lengthInBytes,
      createdAt: DateTime.now().toUtc(),
    );
    await _backend.writeMetadata(
      saneUuid,
      saneFilename,
      jsonEncode(record.toMetadata()),
    );
    return record;
  }

  /// Reads the bytes for the given `local://` URL (or explicit
  /// noteUuid + filename pair). Throws if the entry doesn't exist.
  Future<Uint8List> getBytes({
    String? localUrl,
    String? noteUuid,
    String? filename,
  }) async {
    final resolved = _resolve(localUrl: localUrl, noteUuid: noteUuid, filename: filename);
    final bytes = await _backend.read(resolved.$1, resolved.$2);
    if (bytes == null) {
      throw LocalAttachmentStoreException(
        'Attachment not found: '
        'Shared.LocalAttachmentStore/get \u2014 '
        'no entry for ${resolved.$1}/${resolved.$2}.',
      );
    }
    return bytes;
  }

  /// Returns the metadata record for a stored attachment, or null
  /// when missing (does not throw, so callers that want to probe
  /// can use a null check).
  Future<LocalAttachment?> get({
    String? localUrl,
    String? noteUuid,
    String? filename,
  }) async {
    final resolved = _resolve(localUrl: localUrl, noteUuid: noteUuid, filename: filename);
    final raw = await _backend.readMetadata(resolved.$1, resolved.$2);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return LocalAttachment(
        noteUuid: decoded['note_uuid']?.toString() ?? resolved.$1,
        filename: decoded['filename']?.toString() ?? resolved.$2,
        contentType:
            decoded['content_type']?.toString() ?? 'application/octet-stream',
        sizeBytes: (decoded['size_bytes'] as num?)?.toInt() ?? 0,
        createdAt:
            DateTime.tryParse(decoded['created_at']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    } catch (_) {
      return null;
    }
  }

  /// Lists every attachment belonging to [noteUuid] in insertion
  /// order. Returns an empty list when the note has none (does not
  /// throw).
  Future<List<LocalAttachment>> listForNote(String noteUuid) async {
    final saneUuid = _sanitize(noteUuid);
    if (saneUuid.isEmpty) return const [];
    final entries = await _backend.listForNote(saneUuid);
    final out = <LocalAttachment>[];
    for (final filename in entries) {
      final record = await get(noteUuid: saneUuid, filename: filename);
      if (record != null) out.add(record);
    }
    return out;
  }

  /// Deletes the (noteUuid, filename) entry. Silently no-ops when
  /// the key is missing.
  Future<void> delete({
    String? localUrl,
    String? noteUuid,
    String? filename,
  }) async {
    final resolved = _resolve(localUrl: localUrl, noteUuid: noteUuid, filename: filename);
    await _backend.delete(resolved.$1, resolved.$2);
  }

  /// Deletes every attachment under [noteUuid]. Used after a draft
  /// promotes its queued attachments to CDN URLs on sync so the
  /// local copy doesn't linger forever.
  Future<void> deleteAllForNote(String noteUuid) async {
    final saneUuid = _sanitize(noteUuid);
    if (saneUuid.isEmpty) return;
    await _backend.deleteAllForNote(saneUuid);
  }

  /// Reports the total bytes consumed by every attachment currently
  /// stored. Clients can show this in the debug log or use it to
  /// decide when to warn users about the per-origin budget on web.
  Future<int> totalBytes() async => _backend.totalBytes();

  /// Per-file size cap. Matches the editor's existing upload cap so
  /// users see a consistent error across the sync + store paths.
  static const int maxBytesPerAttachment = 20 * 1024 * 1024;

  /// Parses a `local://<note_uuid>/<filename>` URL. Returns null when
  /// the input is not a local-attachment URL or the path shape is
  /// unexpected (missing note_uuid, missing filename, embedded
  /// subdirectories).
  static ({String noteUuid, String filename})? parseLocalUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'local') return null;
    final host = uri.host;
    final path = uri.path;
    if (host.isEmpty || path.isEmpty) return null;
    // path starts with "/", split into segments.
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length != 1) return null;
    return (noteUuid: host, filename: segments.single);
  }

  /// One-time migration: scans [drafts] for
  /// `metadata_json['queued_attachments']` entries carrying inline
  /// `bytes_base64` payloads (the old 0.1.37 format) and moves each
  /// to the store, rewriting the draft's markdown content to use the
  /// new `local://` URL scheme and stripping the base64 payload.
  ///
  /// Returns a new list of drafts with the rewrites applied. Drafts
  /// that had no queued base64 pass through untouched.
  ///
  /// [noteUuidLookup] maps a draft (by `client_draft_id` or fall
  /// back to `id` as string) to the store key to use. For drafts
  /// that don't have a server uuid yet, prefix with `local-` so the
  /// keys never collide with server uuids.
  Future<List<Map<String, dynamic>>> migrateBase64Drafts(
    List<Map<String, dynamic>> drafts, {
    String Function(Map<String, dynamic> draft)? noteUuidLookup,
  }) async {
    String defaultLookup(Map<String, dynamic> draft) {
      final serverUuid = draft['uuid']?.toString() ?? '';
      if (serverUuid.isNotEmpty) return serverUuid;
      final client =
          draft['client_draft_id']?.toString() ?? draft['id']?.toString() ?? '';
      return client.isEmpty ? 'local-unknown' : 'local-$client';
    }

    final lookup = noteUuidLookup ?? defaultLookup;
    final rewritten = <Map<String, dynamic>>[];
    for (final draft in drafts) {
      final metadataRaw = draft['metadata_json']?.toString() ?? '{}';
      Map<String, dynamic> metadata;
      try {
        final decoded = jsonDecode(metadataRaw);
        metadata = decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : <String, dynamic>{};
      } catch (_) {
        metadata = <String, dynamic>{};
      }
      final queued = List<Map<String, dynamic>>.from(
        (metadata['queued_attachments'] as List?) ?? const [],
      );
      if (queued.isEmpty) {
        rewritten.add(Map<String, dynamic>.from(draft));
        continue;
      }
      final noteUuid = lookup(draft);
      var content = draft['content']?.toString() ?? '';
      final newQueued = <Map<String, dynamic>>[];
      for (final entry in queued) {
        final base64Str = entry['bytes_base64']?.toString() ?? '';
        if (base64Str.isEmpty) {
          newQueued.add(Map<String, dynamic>.from(entry));
          continue;
        }
        final filename =
            _sanitize((entry['filename'] ?? 'attachment').toString());
        final contentType =
            entry['content_type']?.toString() ?? 'application/octet-stream';
        final Uint8List bytes;
        try {
          bytes = base64Decode(base64Str);
        } catch (_) {
          newQueued.add(Map<String, dynamic>.from(entry));
          continue;
        }
        final stored = await put(
          noteUuid: noteUuid,
          filename: filename,
          contentType: contentType,
          bytes: bytes,
        );
        // Rewrite any inline data URI in the markdown content for this
        // specific attachment to the new local:// URL. The 0.1.37 path
        // embedded `data:<ct>;base64,<base64>` so the replacement can
        // find exact matches by that substring.
        final oldDataUri = 'data:$contentType;base64,$base64Str';
        content = content.replaceAll(oldDataUri, stored.localUrl);
        final rewrittenEntry = Map<String, dynamic>.from(entry);
        rewrittenEntry.remove('bytes_base64');
        rewrittenEntry['local_url'] = stored.localUrl;
        rewrittenEntry['content_type'] = contentType;
        rewrittenEntry['size_bytes'] = bytes.lengthInBytes;
        newQueued.add(rewrittenEntry);
      }
      metadata['queued_attachments'] = newQueued;
      rewritten.add({
        ...draft,
        'content': content,
        'metadata_json': jsonEncode(metadata),
      });
    }
    return rewritten;
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  (String, String) _resolve({
    String? localUrl,
    String? noteUuid,
    String? filename,
  }) {
    if (localUrl != null) {
      final parsed = parseLocalUrl(localUrl);
      if (parsed == null) {
        throw LocalAttachmentStoreException(
          'Attachment lookup rejected: '
          'Shared.LocalAttachmentStore/resolve \u2014 '
          'not a local:// URL or malformed: $localUrl',
        );
      }
      return (parsed.noteUuid, parsed.filename);
    }
    if (noteUuid == null || filename == null) {
      throw LocalAttachmentStoreException(
        'Attachment lookup rejected: '
        'Shared.LocalAttachmentStore/resolve \u2014 '
        'either localUrl or both (noteUuid, filename) must be given.',
      );
    }
    final saneUuid = _sanitize(noteUuid);
    final saneFilename = _sanitize(filename);
    if (saneUuid.isEmpty || saneFilename.isEmpty) {
      throw LocalAttachmentStoreException(
        'Attachment lookup rejected: '
        'Shared.LocalAttachmentStore/resolve \u2014 '
        'noteUuid and filename must be non-empty after sanitization.',
      );
    }
    return (saneUuid, saneFilename);
  }
}

/// Platform backend contract. Implemented by
/// `local_attachment_store_io.dart` (native filesystem) and
/// `local_attachment_store_web.dart` (in-memory stub; IndexedDB in a
/// later round).
abstract class LocalAttachmentBackend {
  Future<void> write(String noteUuid, String filename, Uint8List bytes);
  Future<Uint8List?> read(String noteUuid, String filename);
  Future<void> writeMetadata(
      String noteUuid, String filename, String metadataJson);
  Future<String?> readMetadata(String noteUuid, String filename);
  Future<List<String>> listForNote(String noteUuid);
  Future<void> delete(String noteUuid, String filename);
  Future<void> deleteAllForNote(String noteUuid);
  Future<int> totalBytes();
}

/// Sanitizer shared with `local_archive.dart` to keep filename rules
/// consistent across the two stores.
String _sanitize(String raw) {
  final buf = StringBuffer();
  for (final codeUnit in raw.runes) {
    if (codeUnit < 0x20) continue;
    final ch = String.fromCharCode(codeUnit);
    if (ch == '/' || ch == '\\' || ch == '\u0000') {
      buf.write('_');
    } else {
      buf.write(ch);
    }
  }
  final cleaned = buf.toString().trim();
  if (cleaned.isEmpty) return '';
  if (cleaned.length > 200) return cleaned.substring(0, 200);
  return cleaned;
}
