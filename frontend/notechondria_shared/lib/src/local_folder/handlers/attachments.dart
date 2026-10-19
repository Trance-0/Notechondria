import '../folder_fs.dart';
import '../folder_index.dart' show recordListOf;
import '../folder_journal.dart';
import '../folder_layout.dart';
import '../folder_messages.dart';
import '../note_codec.dart';
import '../router.dart';
import 'lookup.dart';
import 'notes.dart' show sidecarWith;
import 'records.dart';

// Attachments (id and uuid routes), note covers, and the avatar file
// (storage rules 3.6, feature matrix F09, F33, F34). Bytes are real files
// under `assets/`; answers carry `nc-folder:///assets/...` URLs, which
// `folderAwareImageProvider` reads back. Each upload writes its bytes
// first (replace-on-close, 3.4) and then, in one journaled operation, the
// JSON that names them, so an interruption leaves at most an unreferenced
// file.

/// `_MAX_ATTACHMENT_SIZE` (`backend/notes/api.py:2456`).
const int kMaxAttachmentBytes = 20 * 1024 * 1024;

/// `_MAX_COVER_IMAGE_SIZE` (`backend/notes/api.py:2606`).
const int kMaxCoverBytes = 5 * 1024 * 1024;

/// The backend's avatar field has no size cap; the folder applies the
/// attachment cap so one upload cannot fill a synced folder.
const int kMaxAvatarBytes = kMaxAttachmentBytes;

const int _kMaxNameLength = 120;

String folderFileUrl(String path) => '$kFolderUrlPrefix$path';

/// The folder path of an `nc-folder:` URL without its query, or null.
String? folderUrlPath(String url) {
  if (!url.startsWith(kFolderUrlPrefix)) return null;
  var rest = url.substring(kFolderUrlPrefix.length);
  final cut = rest.indexOf(RegExp(r'[?#]'));
  if (cut >= 0) rest = rest.substring(0, cut);
  try {
    splitFolderPath(rest);
  } on FolderFsException {
    return null;
  }
  return rest;
}

/// A file name that is safe in a folder path, a Markdown link, and a file
/// manager: letters, digits, `.`, `_`, and `-`; no leading dot; never a
/// Chrome swap-file name; at most 120 characters with the extension kept.
String sanitizeFileName(String? name) {
  var base = folderPathBasename((name ?? '').replaceAll('\\', '/')).trim();
  base = base.replaceAll(RegExp(r'[^\p{L}\p{N}._-]', unicode: true), '_');
  base = base.replaceFirst(RegExp(r'^[._]+'), '');
  if (isSwapFileName(base)) base = '${base}_';
  if (base.isEmpty) base = 'untitled';
  final runes = base.runes.toList();
  if (runes.length > _kMaxNameLength) {
    final dot = base.lastIndexOf('.');
    final ext = dot > 0 && base.length - dot <= 16 ? base.substring(dot) : '';
    base = String.fromCharCodes(runes.take(_kMaxNameLength - ext.length)) + ext;
  }
  return base;
}

/// `<stem>-2.<ext>`, `<stem>-3.<ext>`, ... for a name already in [taken].
String uniqueFileName(String name, Set<String> taken) {
  if (!taken.contains(name)) return name;
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  for (var n = 2;; n++) {
    final candidate = '$stem-$n$ext';
    if (!taken.contains(candidate)) return candidate;
  }
}

/// The lower-case extension of [name] without the dot, or [fallback].
String extensionOf(String name, {String fallback = 'bin'}) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return fallback;
  final ext = name.substring(dot + 1).toLowerCase();
  return RegExp(r'^[a-z0-9]{1,10}$').hasMatch(ext) ? ext : fallback;
}

LocalUpload? _fileOf(LocalHandlerContext ctx, String field) {
  for (final f in ctx.request.files) {
    if (f.field == field) return f;
  }
  return null;
}

LocalHttpError _bad(String consequence, String cause) => LocalHttpError(
    400, LocalFolderMessages.invalidField(consequence, 'attachments', cause));

void _checkSize(LocalUpload f, int max, String consequence) {
  if (f.bytes.length > max) {
    throw _bad(consequence,
        "'${f.filename ?? f.field}' is larger than ${max ~/ (1024 * 1024)} MB");
  }
}

Future<NoteRecord> _noteOf(LocalHandlerContext ctx) async {
  final params = ctx.request.params;
  if (params.containsKey('uuid')) {
    final uuid = params['uuid']!;
    return await noteByUuid(ctx, uuid) ??
        (throw LocalHttpError(404, LocalFolderMessages.noteUuidNotFound(uuid)));
  }
  final id = ctx.request.intParam('id');
  return await noteById(ctx, id) ??
      (throw LocalHttpError(404, LocalFolderMessages.noteNotFound(id)));
}

String _attachmentsDir(String hex) => '$kAssetsDir/notes/$hex/attachments';

/// `assets/notes/<hex>/attachments.json`: `{"schema_version": 1,
/// "attachments": [{id, uuid, filename, original_filename, content_type,
/// size_bytes, created_at}]}` (main 3.1).
Future<List<Map<String, Object?>>> readAttachments(FolderFs fs, String hex) async {
  final text = await readTextOrNull(fs, attachmentsIndexPath(hex));
  if (text == null) return [];
  return [
    for (final r in recordListOf(decodeJsonValue(text)) ?? const [])
      if (jsonInt(r['id']) != null && jsonString(r['filename']) != null) r,
  ];
}

String encodeAttachments(List<Map<String, Object?>> records) => encodeFolderJson(
    {'schema_version': kFolderSchemaVersion, 'attachments': records});

/// `attachment_payload` (`backend/notes/api.py:2459-2468`).
Map<String, Object?> attachmentPayload(
    Map<String, Object?> r, NoteRecord note) {
  final name = jsonString(r['filename'])!;
  return {
    'id': jsonInt(r['id']),
    'note_id': note.id,
    'original_filename': jsonString(r['original_filename']) ?? name,
    'file_size': jsonInt(r['size_bytes']) ?? 0,
    'content_type': jsonString(r['content_type']) ?? '',
    'url': folderFileUrl('${_attachmentsDir(uuidHex(note.uuid))}/$name'),
    'date_created': jsonString(r['created_at']),
  };
}

/// Newest first, as `NoteAttachment.Meta.ordering` (`-date_created, -id`).
int _newestFirst(Map<String, Object?> a, Map<String, Object?> b) {
  final t = (jsonString(b['created_at']) ?? '')
      .compareTo(jsonString(a['created_at']) ?? '');
  return t != 0 ? t : (jsonInt(b['id']) ?? 0).compareTo(jsonInt(a['id']) ?? 0);
}

Future<LocalResponse> _list(LocalHandlerContext ctx) async {
  final note = await _noteOf(ctx);
  final records = await readAttachments(ctx.fs, uuidHex(note.uuid))
    ..sort(_newestFirst);
  return LocalResponse(
      200, [for (final r in records) attachmentPayload(r, note)]);
}

Future<LocalResponse> _create(LocalHandlerContext ctx) async {
  const consequence = 'Attachment not saved';
  final upload = _fileOf(ctx, 'file') ??
      (throw _bad(consequence, 'the request has no `file` part'));
  _checkSize(upload, kMaxAttachmentBytes, consequence);
  final note = await _noteOf(ctx);
  final hex = uuidHex(note.uuid);
  final manifest = await readFolderManifest(ctx.fs) ??
      (throw LocalHttpError(503,
          LocalFolderMessages.manifestMissing(ctx.folderName, importPending: false)));
  final (updated, id) = manifest.allocate('attachment');
  final dir = _attachmentsDir(hex);
  final taken = {for (final e in await listOrEmpty(ctx.fs, dir)) e.name};
  final records = await readAttachments(ctx.fs, hex);
  taken.addAll([for (final r in records) jsonString(r['filename'])!]);
  final original = (upload.filename ?? '').trim();
  final name = uniqueFileName(sanitizeFileName(original), taken);
  final record = <String, Object?>{
    'id': id,
    'uuid': newUuidV4(),
    'filename': name,
    'original_filename': original.isEmpty ? 'untitled' : original,
    'content_type': upload.contentType ?? '',
    'size_bytes': upload.bytes.length,
    'created_at': ctx.now().toUtc().toIso8601String(),
  };
  await ctx.writeBytes('$dir/$name', upload.bytes);
  await ctx.commit(ctx.journal.newRecord([
    JournalWrite(attachmentsIndexPath(hex), encodeAttachments([...records, record])),
    JournalWrite(kManifestPath, updated.encode()),
  ]));
  return LocalResponse(201, attachmentPayload(record, note));
}

Future<LocalResponse> _delete(LocalHandlerContext ctx) async {
  final note = await _noteOf(ctx);
  final aid = ctx.request.intParam('aid');
  final hex = uuidHex(note.uuid);
  final records = await readAttachments(ctx.fs, hex);
  final match = records.where((r) => jsonInt(r['id']) == aid).firstOrNull ??
      (throw LocalHttpError(
          404, LocalFolderMessages.attachmentNotFound(note.id, aid)));
  await ctx.commit(ctx.journal.newRecord([
    JournalWrite(attachmentsIndexPath(hex),
        encodeAttachments([...records.where((r) => !identical(r, match))])),
  ], [
    JournalRemoval('${_attachmentsDir(hex)}/${jsonString(match['filename'])}'),
  ]));
  return LocalResponse.noContent;
}

/// `NoteSummarySerializer` of [path] read back after a cover change.
Future<Map<String, Object?>> _summaryAfterWrite(
    LocalHandlerContext ctx, String path) async {
  final n = await readNoteAt(ctx.fs, path) ??
      (throw LocalHttpError(500, LocalFolderMessages.requestFailed(
          ctx.request.method, ctx.request.path,
          "'$path' could not be read back after the write")));
  final profile = await FolderProfile.read(ctx.fs, folderName: ctx.folderName);
  return noteSummary(n, CourseLookup(await readCourses(ctx.fs)), profile.author);
}

/// The previous cover file of [note] when it is a folder file of that note
/// other than [keep].
String? _oldCover(NoteRecord note, String? keep) {
  final path = folderUrlPath(note.sidecar.coverImageUrl);
  final dir = '$kAssetsDir/notes/${uuidHex(note.uuid)}/';
  if (path == null || path == keep || !path.startsWith(dir)) return null;
  return path;
}

/// POST `/notes/{id}/cover/` (field `cover`): `assets/notes/<hex>/cover.<ext>`
/// and the sidecar's `cover_image_url` with a `?v=` cache buster. The
/// backend also bumps `last_edit`; the folder leaves the note body alone.
Future<LocalResponse> _setCover(LocalHandlerContext ctx) async {
  const consequence = 'Cover image not set';
  final upload = _fileOf(ctx, 'cover') ??
      (throw _bad(consequence, 'the request has no `cover` file part'));
  _checkSize(upload, kMaxCoverBytes, consequence);
  final note = await _noteOf(ctx);
  final ext = extensionOf(sanitizeFileName(upload.filename), fallback: 'img');
  final path = '$kAssetsDir/notes/${uuidHex(note.uuid)}/cover.$ext';
  await ctx.writeBytes(path, upload.bytes);
  final url = '${folderFileUrl(path)}?v=${ctx.now().millisecondsSinceEpoch}';
  final old = _oldCover(note, path);
  await ctx.commit(ctx.journal.newRecord([
    JournalWrite(note.sidecarPath,
        sidecarWith(note.sidecar, {'cover_image_url': url}).encode()),
  ], [
    if (old != null) JournalRemoval(old),
  ]));
  return LocalResponse(200, await _summaryAfterWrite(ctx, note.path));
}

Future<LocalResponse> _clearCover(LocalHandlerContext ctx) async {
  final note = await _noteOf(ctx);
  if (note.sidecar.coverImageUrl.isNotEmpty) {
    final old = _oldCover(note, null);
    await ctx.commit(ctx.journal.newRecord([
      JournalWrite(note.sidecarPath,
          sidecarWith(note.sidecar, {'cover_image_url': ''}).encode()),
    ], [
      if (old != null) JournalRemoval(old),
    ]));
  }
  return LocalResponse(200, await _summaryAfterWrite(ctx, note.path));
}

/// The avatar of a multipart `PATCH /settings/` (field `avatar`, F09):
/// writes `assets/avatar.<ext>` and returns its URL with a `?v=` cache
/// buster and the previous avatar file to remove after the profile write.
Future<({String url, String? oldPath})> storeAvatar(
    LocalHandlerContext ctx, LocalUpload upload, String previousUrl) async {
  _checkSize(upload, kMaxAvatarBytes, 'Avatar not saved');
  if (upload.bytes.isEmpty) throw _bad('Avatar not saved', 'the file is empty');
  final ext = extensionOf(sanitizeFileName(upload.filename), fallback: 'img');
  final path = '$kAssetsDir/avatar.$ext';
  await ctx.writeBytes(path, upload.bytes);
  final old = folderUrlPath(previousUrl);
  return (
    url: '${folderFileUrl(path)}?v=${ctx.now().millisecondsSinceEpoch}',
    oldPath: old != null && old != path && old.startsWith('$kAssetsDir/avatar.')
        ? old
        : null,
  );
}

List<LocalRoute> attachmentRoutes() => [
      LocalRoute('GET', 'notes/{id}/attachments', _list),
      LocalRoute('POST', 'notes/{id}/attachments', _create),
      LocalRoute('DELETE', 'notes/{id}/attachments/{aid}', _delete),
      LocalRoute('GET', 'notes/uuid/{uuid}/attachments', _list),
      LocalRoute('POST', 'notes/uuid/{uuid}/attachments', _create),
      LocalRoute('DELETE', 'notes/uuid/{uuid}/attachments/{aid}', _delete),
      LocalRoute('POST', 'notes/{id}/cover', _setCover),
      LocalRoute('DELETE', 'notes/{id}/cover', _clearCover),
    ];
