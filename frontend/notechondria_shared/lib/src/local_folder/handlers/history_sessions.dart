import '../folder_fs.dart';
import '../folder_index.dart' show recordListKeyOf, recordListOf;
import '../folder_journal.dart';
import '../folder_layout.dart';
import '../folder_messages.dart';
import '../folder_snapshots.dart';
import '../note_codec.dart';
import '../router.dart';
import 'lookup.dart';
import 'notes.dart'
    show frontmatterWith, servedDetail, sidecarWith, snapshotRemovals, snapshotWrites;
import 'records.dart';

// History, snapshots, version restore (F23, storage rules 3.8) and study
// sessions (F24, `planner/sessions.json`). A snapshot is the note file as
// it was on disk (`history/<hex>/<id>.md`) plus its index entry, which also
// keeps the sidecar's `description` and `metadata_json`. Both pools of 3.8
// are pruned by `pruneHistory` through `FolderSnapshotWriter.plan`.

Future<NoteRecord> _liveNote(LocalHandlerContext ctx) async {
  final id = ctx.request.intParam('id');
  return await noteById(ctx, id) ??
      (throw LocalHttpError(404, LocalFolderMessages.noteNotFound(id)));
}

/// `NoteVersionSerializer` (`backend/notes/api.py:573-581`) of [e], whose
/// snapshot file is [text]; decoded relative to the note at [notePath], so
/// attachment links come back as `nc-folder:` URLs.
Map<String, Object?> versionPayload(
    HistoryEntry e, String text, String notePath) {
  final decoded = decodeNoteFile(text, path: notePath);
  return {
    'id': e.id,
    'title': decoded.frontmatter.title,
    'description': jsonString(e.extra['description']) ?? '',
    'content': decoded.body,
    'metadata_json': textField(e.extra['metadata_json']),
    'editor_mode': decoded.frontmatter.editorMode,
    'reason': e.reason,
    'label': e.label,
    'date_created': e.createdAt,
  };
}

/// Newest first, as `NoteVersion.Meta.ordering` (`-date_created, -id`).
List<HistoryEntry> _newestFirst(List<HistoryEntry> versions) => [...versions]
  ..sort((a, b) {
    final t = b.createdAt.compareTo(a.createdAt);
    return t != 0 ? t : b.id.compareTo(a.id);
  });

/// GET `/notes/{id}/history/`: both pools in one list, newest first (3.8).
/// The backend answers its 12 newest; the folder keeps at most 12 per pool.
Future<LocalResponse> _history(LocalHandlerContext ctx) async {
  final n = await _liveNote(ctx);
  final hex = uuidHex(n.uuid);
  final index = await FolderSnapshotWriter(ctx.fs).readIndex(hex);
  final versions = _newestFirst(index?.versions ?? const []);
  final texts = await readInBatches(versions,
      (HistoryEntry v) => readTextOrNull(ctx.fs, historyBodyPath(hex, v.id)));
  return LocalResponse(200, [
    for (var i = 0; i < versions.length; i++)
      if (texts[i] != null) versionPayload(versions[i], texts[i]!, n.path),
  ]);
}

Map<String, Object?> _sidecarExtra(NoteRecord n) => {
      'description': n.sidecar.description ?? '',
      'metadata_json': textField(n.sidecar.metadataJson),
    };

/// POST `/notes/{id}/snapshot/` with `reason` (default `manual`).
Future<LocalResponse> _snapshot(LocalHandlerContext ctx) async {
  final n = await _liveNote(ctx);
  final b = BodyFields(ctx.request.body,
      consequence: 'Snapshot not saved', process: 'notes');
  final reason = b.string('reason', maxLength: 32);
  final plan = await FolderSnapshotWriter(ctx.fs, now: ctx.now).plan(
    noteUuid: n.uuid,
    reason: reason == null || reason.trim().isEmpty ? 'manual' : reason.trim(),
    text: n.text,
    notePath: n.path,
    extra: _sidecarExtra(n),
  );
  await ctx.commit(
      ctx.journal.newRecord(snapshotWrites(plan), snapshotRemovals(plan)));
  return LocalResponse(201, versionPayload(plan.entry, n.text, n.path));
}

/// POST `/notes/{id}/restore/{version}/`: a `before_restore` snapshot of the
/// disk version, then the version's title, editor mode, body, description,
/// and metadata, in one journaled operation (`backend/notes/api.py:1903-1921`).
Future<LocalResponse> _restore(LocalHandlerContext ctx) async {
  final n = await _liveNote(ctx);
  final vid = ctx.request.intParam('version');
  final hex = uuidHex(n.uuid);
  final index = await FolderSnapshotWriter(ctx.fs).readIndex(hex);
  final entry = index?.versions.where((v) => v.id == vid).firstOrNull;
  final text = entry == null
      ? null
      : await readTextOrNull(ctx.fs, historyBodyPath(hex, vid));
  if (entry == null || text == null) {
    throw LocalHttpError(404, LocalFolderMessages.versionNotFound(n.id, vid));
  }
  final version = decodeNoteFile(text, path: n.path);
  final plan = await FolderSnapshotWriter(ctx.fs, now: ctx.now).plan(
    noteUuid: n.uuid,
    reason: 'before_restore',
    text: n.text,
    notePath: n.path,
    extra: _sidecarExtra(n),
  );
  final fm = frontmatterWith(n.frontmatter,
      title: version.frontmatter.title,
      editorMode: version.frontmatter.editorMode,
      lastEdit: ctx.now().toUtc().toIso8601String());
  final sidecar = sidecarWith(n.sidecar, {
    // A folder-only snapshot (external or concurrent edit) has no sidecar
    // fields; the note keeps its own.
    if (entry.extra.containsKey('description'))
      'description': jsonString(entry.extra['description']) ?? '',
    if (entry.extra.containsKey('metadata_json'))
      'metadata_json': textField(entry.extra['metadata_json']),
    'word_count': wordCountOf(version.body),
  });
  await ctx.commit(ctx.journal.newRecord([
    JournalWrite(n.path, encodeNoteFile(fm, version.body, path: n.path),
        expect: n.expect),
    JournalWrite(n.sidecarPath, sidecar.encode()),
    ...snapshotWrites(plan),
  ], snapshotRemovals(plan)));
  return LocalResponse(200, await servedDetail(ctx, n.path));
}

// --- Study sessions (F24) ---

/// `planner/sessions.json`: the container (null for a bare list or a
/// missing file) and its records `{id, note_id, note_uuid, title, summary,
/// started_at, ended_at}`.
Future<(Map<String, Object?>?, List<Map<String, Object?>>)> readSessions(
    FolderFs fs) async {
  final text = await readTextOrNull(fs, kPlannerSessionsPath);
  if (text == null) return (null, <Map<String, Object?>>[]);
  final json = decodeJsonValue(text);
  final records = [
    for (final r in recordListOf(json) ?? const <Map<String, Object?>>[])
      if (jsonInt(r['id']) != null) r,
  ];
  return (json is Map ? Map<String, Object?>.from(json) : null, records);
}

String _encodeSessions(
    Map<String, Object?>? container, List<Map<String, Object?>> records) {
  final key = container == null ? null : recordListKeyOf(container);
  return encodeFolderJson({
    ...?container,
    'schema_version': kFolderSchemaVersion,
    key ?? 'sessions': records,
  });
}

/// `note_session_payload` (`backend/notes/services.py:367-378`); the course
/// comes from the note when the session is answered (3.5).
Map<String, Object?> sessionPayload(
    Map<String, Object?> r, int? courseId) {
  final started = jsonString(r['started_at']) ?? '';
  final ended = jsonString(r['ended_at']) ??
      (DateTime.tryParse(started)
              ?.toUtc()
              .add(const Duration(minutes: 15))
              .toIso8601String() ??
          started);
  return {
    'id': jsonInt(r['id']),
    'title': jsonString(r['title']) ?? '',
    'kind': 'note_session',
    'note_id': jsonInt(r['note_id']),
    'course_id': courseId,
    'summary': jsonString(r['summary']) ?? '',
    'starts_at': started,
    'ends_at': ended,
  };
}

/// The course id of the note a session names, from the index.
Future<int? Function(Map<String, Object?>)> sessionCourseLookup(
    LocalHandlerContext ctx) async {
  final courses = CourseLookup(await readCourses(ctx.fs, skip: ctx.skipPaths));
  final notes = indexedNotes(ctx.index, trashed: true, skip: ctx.skipPaths);
  final byUuid = {for (final n in notes) n.uuid: n};
  final byId = {for (final n in notes) n.id: n};
  return (r) {
    final n = byUuid[jsonString(r['note_uuid'])] ?? byId[jsonInt(r['note_id'])];
    return n == null ? null : courses.bySlug[n.courseSlug]?.id;
  };
}

/// An ISO 8601 date-time field as UTC ISO text; null when absent or null.
String? _dateTime(BodyFields b, String key) {
  final v = b.string(key);
  if (v == null || v.trim().isEmpty) return null;
  final t = DateTime.tryParse(v.trim()) ??
      (throw b.bad('$key must be an ISO 8601 date and time'));
  return t.toUtc().toIso8601String();
}

String _clip(String text, int max) {
  final runes = text.runes.toList();
  return runes.length <= max ? text : String.fromCharCodes(runes.take(max));
}

Future<LocalResponse> _listSessions(LocalHandlerContext ctx) async {
  final q = ctx.request.query;
  final (_, records) = await readSessions(ctx.fs);
  final noteId = int.tryParse((q['note_id'] ?? '').trim());
  var limit = int.tryParse((q['limit'] ?? '').trim()) ?? 50;
  if (limit > 200) limit = 200;
  final rows = [
    for (final r in records)
      if (noteId == null || jsonInt(r['note_id']) == noteId) r,
  ]..sort((a, b) {
      final t = (jsonString(b['started_at']) ?? '')
          .compareTo(jsonString(a['started_at']) ?? '');
      return t != 0 ? t : jsonInt(b['id'])!.compareTo(jsonInt(a['id'])!);
    });
  final course = await sessionCourseLookup(ctx);
  return LocalResponse(200, [
    for (final r in rows.take(limit < 0 ? 0 : limit))
      sessionPayload(r, course(r)),
  ]);
}

Future<LocalResponse> _startSession(LocalHandlerContext ctx) async {
  final b = BodyFields(ctx.request.body,
      consequence: 'Study session not saved', process: 'planner');
  final noteId = b.integer('note_id') ?? (throw b.bad('note_id is required'));
  final title = b.string('title', maxLength: 120);
  final summary = b.string('summary', maxLength: 255);
  final started = _dateTime(b, 'started_at') ??
      ctx.now().toUtc().toIso8601String();
  final ended = _dateTime(b, 'ended_at');
  // The backend looks the note up without its trash filter.
  final n = await noteById(ctx, noteId, trashed: true) ??
      (throw LocalHttpError(404, LocalFolderMessages.noteNotFound(noteId)));
  final manifest = await readFolderManifest(ctx.fs) ??
      (throw LocalHttpError(503,
          LocalFolderMessages.manifestMissing(ctx.folderName, importPending: false)));
  final (updated, id) = manifest.allocate('session');
  final (container, records) = await readSessions(ctx.fs);
  final record = <String, Object?>{
    'id': id,
    'note_id': n.id,
    'note_uuid': n.uuid,
    'title': title == null || title.isEmpty
        ? _clip(n.frontmatter.title, 120)
        : title,
    'summary': summary == null || summary.isEmpty
        ? _clip(n.sidecar.description ?? '', 255)
        : summary,
    'started_at': started,
    'ended_at': ended,
  };
  await ctx.commit(ctx.journal.newRecord([
    JournalWrite(kPlannerSessionsPath,
        _encodeSessions(container, [...records, record])),
    JournalWrite(kManifestPath, updated.encode()),
  ]));
  final course = await sessionCourseLookup(ctx);
  return LocalResponse(201, sessionPayload(record, course(record)));
}

Future<LocalResponse> _updateSession(LocalHandlerContext ctx) async {
  final id = ctx.request.intParam('id');
  final b = BodyFields(ctx.request.body,
      consequence: 'Study session not saved', process: 'planner');
  final title = b.string('title', maxLength: 120);
  final summary = b.string('summary', maxLength: 255);
  final started = b.has('started_at') ? _dateTime(b, 'started_at') : null;
  final ended = b.has('ended_at') ? _dateTime(b, 'ended_at') : null;
  final (container, records) = await readSessions(ctx.fs);
  final at = records.indexWhere((r) => jsonInt(r['id']) == id);
  if (at < 0) throw LocalHttpError(404, LocalFolderMessages.sessionNotFound(id));
  final record = {
    ...records[at],
    if (title != null) 'title': title,
    if (summary != null) 'summary': summary,
    // `started_at` is required by the model; a null leaves it as it was.
    if (started != null) 'started_at': started,
    if (b.has('ended_at')) 'ended_at': ended,
  };
  final next = [...records]..[at] = record;
  await ctx.writeText(kPlannerSessionsPath, _encodeSessions(container, next));
  final course = await sessionCourseLookup(ctx);
  return LocalResponse(200, sessionPayload(record, course(record)));
}

List<LocalRoute> historySessionRoutes() => [
      LocalRoute('GET', 'notes/{id}/history', _history),
      LocalRoute('POST', 'notes/{id}/snapshot', _snapshot),
      LocalRoute('POST', 'notes/{id}/restore/{version}', _restore),
      LocalRoute('GET', 'note-sessions', _listSessions),
      LocalRoute('POST', 'note-sessions', _startSession),
      LocalRoute('PATCH', 'note-sessions/{id}', _updateSession),
    ];
