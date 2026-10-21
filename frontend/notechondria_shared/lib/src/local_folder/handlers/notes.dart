import '../folder_fs.dart';
import '../folder_journal.dart';
import '../folder_layout.dart';
import '../folder_messages.dart';
import '../folder_snapshots.dart';
import '../note_codec.dart';
import '../router.dart';
import '../search_score.dart';
import 'activity.dart' show heatmapWithCreatedNote, localDay;
import 'lookup.dart';
import 'records.dart';

// Note and uuid routes (4.1 "Notes"): list, create with the
// `client_draft_id` upsert, detail, update with the 3.8 snapshot check,
// and delete to the trash with comment privatization (3.5). Notes are
// located through the index and re-read one by one (`lookup.dart`, P1B-1).

String _now(LocalHandlerContext ctx) => ctx.now().toUtc().toIso8601String();

NoteFrontmatter frontmatterWith(
  NoteFrontmatter fm, {
  String? title,
  String? uuid,
  Object? courseSlug = _keep,
  bool? isPublic,
  String? editorMode,
  String? lastEdit,
  String? dateCreated,
}) =>
    NoteFrontmatter(
      title: title ?? fm.title,
      uuid: uuid ?? fm.uuid,
      courseSlug: identical(courseSlug, _keep) ? fm.courseSlug : courseSlug as String?,
      isPublic: isPublic ?? fm.isPublic,
      editorMode: editorMode ?? fm.editorMode,
      lastEdit: lastEdit ?? fm.lastEdit,
      dateCreated: dateCreated ?? fm.dateCreated,
    );

const Object _keep = Object();

/// A sidecar with [changes] applied to its JSON; a null value removes the
/// key (for example `deleted_at` on restore).
NoteSidecar sidecarWith(NoteSidecar s, Map<String, Object?> changes) {
  final json = {...s.toJson()};
  changes.forEach((k, v) => v == null ? json.remove(k) : json[k] = v);
  return NoteSidecar.fromJson(json);
}

/// The 3.8 check before a note body is overwritten (T7(j)): the plan of the
/// one `external_edit` or `concurrent_edit` snapshot to journal with the
/// write, or null.
Future<SnapshotPlan?> overwriteSnapshot(
    LocalHandlerContext ctx, NoteRecord n) async {
  final reason = overwriteSnapshotReason(
    disk: n.stat,
    sidecarSize: n.sidecar.mdSize,
    sidecarLastModified: n.sidecar.mdLastModified,
    servedLastModified: ctx.servedLastModified[n.uuid],
  );
  if (reason == null) return null;
  return FolderSnapshotWriter(ctx.fs, now: ctx.now)
      .plan(noteUuid: n.uuid, reason: reason, text: n.text, notePath: n.path);
}

List<JournalWrite> snapshotWrites(SnapshotPlan? plan) => plan == null
    ? const []
    : [
        JournalWrite(kManifestPath, plan.manifestText),
        JournalWrite(plan.bodyPath, plan.bodyText),
        JournalWrite(plan.indexPath, plan.indexText),
      ];

List<JournalRemoval> snapshotRemovals(SnapshotPlan? plan) =>
    [for (final p in plan?.prunedBodies ?? const <String>[]) JournalRemoval(p)];

/// Re-reads [path] after a write, records the served `lastModified`, and
/// answers with the detail payload.
Future<Map<String, Object?>> servedDetail(
    LocalHandlerContext ctx, String path) async {
  final n = await readNoteAt(ctx.fs, path);
  if (n == null) {
    throw LocalHttpError(500,
        LocalFolderMessages.requestFailed(ctx.request.method, ctx.request.path,
            "'$path' could not be read back after the write"));
  }
  ctx.servedLastModified[n.uuid] = n.stat.lastModified;
  final profile = await FolderProfile.read(ctx.fs, folderName: ctx.folderName);
  return noteDetail(n, CourseLookup(await readCourses(ctx.fs)), profile.author);
}

Future<NoteRecord> _liveById(LocalHandlerContext ctx) async {
  final id = ctx.request.intParam('id');
  return await noteById(ctx, id) ??
      (throw LocalHttpError(404, LocalFolderMessages.noteNotFound(id)));
}

Future<NoteRecord> _liveByUuid(LocalHandlerContext ctx) async {
  final uuid = ctx.request.params['uuid']!;
  return await noteByUuid(ctx, uuid) ??
      (throw LocalHttpError(404, LocalFolderMessages.noteUuidNotFound(uuid)));
}

Future<LocalResponse> _detail(LocalHandlerContext ctx, NoteRecord n) async {
  ctx.servedLastModified[n.uuid] = n.stat.lastModified;
  final profile = await FolderProfile.read(ctx.fs, folderName: ctx.folderName);
  final courses = CourseLookup(await readCourses(ctx.fs, skip: ctx.skipPaths));
  return LocalResponse(
      200, {...noteDetail(n, courses, profile.author), 'can_edit': true});
}

const Map<String, int> _windowDays = {'3': 3, '7': 7, '30': 30, '365': 365};

Future<LocalResponse> _list(LocalHandlerContext ctx) async {
  final q = ctx.request.query;
  final body = BodyFields(q, consequence: 'Notes not listed', process: 'notes');
  final limit = body.integer('limit');
  final offset = body.integer('offset') ?? 0;
  final scope = (q['scope'] ?? 'personal').trim().toLowerCase();
  final sort = (q['sort'] ?? 'newest').trim().toLowerCase();
  final query = (q['q'] ?? '').trim().toLowerCase();
  final courseParam = (q['course_id'] ?? '').trim().toLowerCase();
  final courses = CourseLookup(await readCourses(ctx.fs, skip: ctx.skipPaths));
  await refreshNoteListing(ctx, skip: ctx.skipPaths);
  var notes = indexedNotes(ctx.index, skip: ctx.skipPaths);
  final days = _windowDays[(q['window'] ?? 'all').trim().toLowerCase()];
  if (days != null) {
    final since = ctx.now().toUtc().subtract(Duration(days: days)).toIso8601String();
    notes = notes.where((n) => (n.dateCreated ?? since).compareTo(since) >= 0).toList();
  }
  if (scope == 'private') notes = notes.where((n) => !n.isPublic).toList();
  if (scope == 'public') notes = notes.where((n) => n.isPublic).toList();
  if (scope == 'all') ctx.log(LocalFolderLogLevel.info, LocalFolderMessages.publicNotesNotSearched);
  if (courseParam.isNotEmpty) {
    if (const {'none', 'null', 'uncategorized'}.contains(courseParam)) {
      notes = notes.where((n) => !courses.bySlug.containsKey(n.courseSlug)).toList();
    } else {
      final slug = courses.byId[int.tryParse(courseParam)]?.slug;
      notes = notes.where((n) => slug != null && n.courseSlug == slug).toList();
    }
  }
  int created(IndexedNote a, IndexedNote b) {
    final c = (a.dateCreated ?? '').compareTo(b.dateCreated ?? '');
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  if (query.isNotEmpty) {
    // F25: the backend's note_search_score (search_score.dart). Every
    // score reads the note's content, so each body is read, in parallel
    // batches; order is score, then newest last_edit, then title.
    final texts = await readInBatches(
        notes, (IndexedNote n) => readTextOrNull(ctx.fs, n.path));
    final ranked = <(double, int, IndexedNote)>[];
    for (var i = 0; i < notes.length; i++) {
      final n = notes[i];
      final text = texts[i];
      if (text == null) continue;
      final score = noteSearchScore(
          title: n.title,
          description: n.description,
          content: decodeNoteFile(text, path: n.path).body,
          query: q['q'] ?? '');
      if (score == null) continue;
      final edited = DateTime.tryParse(n.lastEditOrModified)
              ?.millisecondsSinceEpoch ??
          n.body.lastModified;
      ranked.add((score.$1, edited, n));
    }
    ranked.sort((a, b) {
      final s = b.$1.compareTo(a.$1);
      if (s != 0) return s;
      final t = b.$2.compareTo(a.$2);
      return t != 0
          ? t
          : a.$3.title.toLowerCase().compareTo(b.$3.title.toLowerCase());
    });
    notes = [for (final r in ranked) r.$3];
  } else if (sort == 'oldest') {
    notes.sort(created);
  } else {
    notes.sort((a, b) => created(b, a));
  }
  final profile = await FolderProfile.read(ctx.fs, folderName: ctx.folderName);
  List<Map<String, Object?>> rows(Iterable<IndexedNote> list) =>
      [for (final n in list) indexedNoteSummary(n, courses, profile.author)];
  if (limit == null) return LocalResponse(200, rows(notes));
  final size = limit.clamp(1, 100);
  final start = offset < 0 ? 0 : offset;
  return LocalResponse(200, {
    'results': rows(notes.skip(start).take(size)),
    'total': notes.length,
    'offset': start,
    'limit': size,
    'has_more': start + size < notes.length,
  });
}

/// The body text of a write: `content`, else `markdown`, else the text of
/// `blocks`, else [fallback].
String? _bodyText(BodyFields b, String? fallback) {
  final content = b.string('content');
  if (content != null && content.isNotEmpty) return content;
  final markdown = b.string('markdown');
  if (markdown != null && markdown.isNotEmpty) return markdown;
  if (content != null || markdown != null) return '';
  final blocks = b.body['blocks'];
  if (blocks is List) {
    return [
      for (final block in blocks)
        if (block is Map && block['text'] is String) block['text'] as String,
    ].join('\n\n');
  }
  return fallback;
}

Future<CourseRecord?> _courseFor(LocalHandlerContext ctx, int? id) async {
  if (id == null) return null;
  final course = CourseLookup(await readCourses(ctx.fs)).byId[id];
  if (course == null) throw LocalHttpError(404, LocalFolderMessages.courseNotFound(id));
  return course;
}

Future<LocalResponse> _create(LocalHandlerContext ctx) async {
  final b = BodyFields(ctx.request.body, consequence: 'Note not saved', process: 'notes');
  final title = b.string('title', maxLength: 100, required: true)!;
  final course = await _courseFor(ctx, b.integer('course_id'));
  final description = b.string('description') ?? '';
  final content = _bodyText(b, '') ?? '';
  final isPublic = b.boolean('is_public') ?? false;
  final draftId = b.string('client_draft_id', maxLength: 64);
  final clientDraftId = draftId == null || draftId.isEmpty ? null : draftId;
  final profile = await FolderProfile.read(ctx.fs, folderName: ctx.folderName);
  final editorMode = b.choice('editor_mode', const {'G', 'B', 'P'}) ?? profile.editorMode;
  final noteType = b.choice('note_type', const {'N', 'C'}) ?? 'N';
  final sourceUuid = b.string('source_note_uuid');
  if (sourceUuid != null && !isUuid(sourceUuid)) throw b.bad('source_note_uuid must be a UUID');
  final now = _now(ctx);
  // Live notes come before trashed ones and the last match wins, as with
  // the full read of 0.1.200. No skip set: a note a stuck journal record
  // names is found, and the write is refused (P1B-3), not duplicated.
  final existing = clientDraftId == null
      ? null
      : (await findNotes(ctx,
              where: (n) => n.clientDraftId == clientDraftId,
              verify: (n) => n.sidecar.clientDraftId == clientDraftId,
              trashed: true))
          .lastOrNull;
  if (existing != null) {
    final n = existing;
    final livePath = noteBodyPath(n.stem);
    final fm = frontmatterWith(n.frontmatter,
        title: title, courseSlug: course?.slug, isPublic: isPublic,
        editorMode: editorMode, lastEdit: now);
    final sidecar = sidecarWith(n.sidecar, {
      'description': description,
      'metadata_json': b.string('metadata_json') ?? '',
      if (b.has('custom_meta')) 'custom_meta': b.string('custom_meta') ?? '',
      'word_count': wordCountOf(content),
      'deleted_at': null,
    });
    final plan = n.trashed ? null : await overwriteSnapshot(ctx, n);
    final writes = [
      JournalWrite(livePath, encodeNoteFile(fm, content, path: livePath),
          expect: n.trashed ? null : n.expect),
      JournalWrite(sidecarPathForBody(livePath), sidecar.encode()),
      ...snapshotWrites(plan),
    ];
    final removals = [...snapshotRemovals(plan)];
    if (n.trashed) {
      final bin = await readRecycleBin(ctx.fs);
      writes.add(JournalWrite(kRecycleBinPath,
          encodeRecycleBin([...bin.where((i) => i['id'] != n.id)])));
      removals
        ..add(JournalRemoval(n.path, expect: n.expect))
        ..add(JournalRemoval(n.sidecarPath));
    }
    await ctx.commit(ctx.journal.newRecord(writes, removals));
    return LocalResponse(200, await servedDetail(ctx, livePath));
  }
  final manifest = await readFolderManifest(ctx.fs);
  if (manifest == null) {
    throw LocalHttpError(503, LocalFolderMessages.manifestMissing(ctx.folderName, importPending: false));
  }
  final (updated, id) = manifest.allocate('note');
  final uuid = newUuidV4();
  final path = noteBodyPath(uuidHex(uuid));
  var source = sourceUuid?.toLowerCase();
  if (source != null && await noteByUuid(ctx, source) == null) {
    source = null;
  }
  final fm = NoteFrontmatter(
      title: title, uuid: uuid, courseSlug: course?.slug, isPublic: isPublic,
      editorMode: editorMode, lastEdit: now, dateCreated: now);
  final sidecar = NoteSidecar(
    id: id,
    uuid: uuid,
    sharingId: uuidHex(newUuidV4()).substring(0, 12),
    metadataJson: b.string('metadata_json') ?? '',
    customMeta: b.string('custom_meta') ?? '',
    clientDraftId: clientDraftId,
    noteType: noteType,
    sourceNoteUuid: source,
    description: description,
    wordCount: wordCountOf(content),
  );
  // F38: `record_note_activity(note, note_word_count(note), CREATED)`; the
  // backend counts the blocks built from content, else description, else
  // title.
  final heatmap = await heatmapWithCreatedNote(
      ctx,
      localDay(ctx.now()),
      wordCountOf(content.isNotEmpty
          ? content
          : (description.isNotEmpty ? description : title)));
  await ctx.commit(ctx.journal.newRecord([
    JournalWrite(path, encodeNoteFile(fm, content, path: path)),
    JournalWrite(sidecarPathForBody(path), sidecar.encode()),
    JournalWrite(kManifestPath, updated.encode()),
    if (heatmap != null) JournalWrite(kPlannerHeatmapPath, heatmap),
  ]));
  return LocalResponse(201, await servedDetail(ctx, path));
}

Future<LocalResponse> _update(LocalHandlerContext ctx, NoteRecord n,
    {bool canEdit = false}) async {
  final b = BodyFields(ctx.request.body, consequence: 'Note not saved', process: 'notes');
  final title = b.has('title') ? b.string('title', maxLength: 100, required: true) : null;
  final course = b.has('course_id') ? await _courseFor(ctx, b.integer('course_id')) : null;
  final body = _bodyText(b, null) ?? n.note.body;
  final fm = frontmatterWith(n.frontmatter,
      title: title,
      courseSlug: b.has('course_id') ? course?.slug : _keep,
      isPublic: b.boolean('is_public'),
      editorMode: b.choice('editor_mode', const {'G', 'B', 'P'}),
      lastEdit: _now(ctx));
  final sidecar = sidecarWith(n.sidecar, {
    if (b.has('description')) 'description': b.string('description') ?? '',
    if (b.has('metadata_json')) 'metadata_json': b.string('metadata_json') ?? '',
    if (b.has('custom_meta')) 'custom_meta': b.string('custom_meta') ?? '',
    'word_count': wordCountOf(body),
  });
  final plan = await overwriteSnapshot(ctx, n);
  await ctx.commit(ctx.journal.newRecord([
    JournalWrite(n.path, encodeNoteFile(fm, body, path: n.path), expect: n.expect),
    JournalWrite(n.sidecarPath, sidecar.encode()),
    ...snapshotWrites(plan),
  ], snapshotRemovals(plan)));
  final detail = await servedDetail(ctx, n.path);
  return LocalResponse(200, canEdit ? {...detail, 'can_edit': true} : detail);
}

/// 3.5 delete: one journaled move to `trash/notes/` with `is_public:
/// false` and `deleted_at`, comment notes made private, the recycle-bin
/// pointer, and the live files removed last.
Future<LocalResponse> _delete(LocalHandlerContext ctx, NoteRecord n) async {
  final now = _now(ctx);
  final trashPath = noteBodyPath(n.stem, trashed: true);
  final fm = frontmatterWith(n.frontmatter, isPublic: false, lastEdit: now);
  final writes = [
    JournalWrite(trashPath, encodeNoteFile(fm, n.note.body, path: trashPath)),
    JournalWrite(sidecarPathForBody(trashPath),
        sidecarWith(n.sidecar, {'deleted_at': now}).encode()),
  ];
  // `source_note_uuid` is set only at creation, so the index may select by
  // it; `is_public` can change in any tab and is checked on disk (L2A-4).
  final comments = await findNotes(ctx,
      where: (c) => c.sourceNoteUuid == n.uuid,
      verify: (c) =>
          c.sidecar.sourceNoteUuid == n.uuid && c.frontmatter.isPublic);
  for (final c in comments) {
    writes.add(JournalWrite(c.path,
        encodeNoteFile(frontmatterWith(c.frontmatter, isPublic: false), c.note.body,
            path: c.path),
        expect: c.expect));
  }
  final bin = await readRecycleBin(ctx.fs);
  final course = CourseLookup(await readCourses(ctx.fs)).bySlug[n.frontmatter.courseSlug];
  writes.add(JournalWrite(kRecycleBinPath, encodeRecycleBin([
    ...bin.where((i) => i['id'] != n.id),
    {
      'id': n.id,
      'uuid': n.uuid,
      'item_type': 'note',
      'path': trashPath,
      'deleted_at': now,
      'title': n.frontmatter.title,
      'course_id': course?.id,
    },
  ])));
  await ctx.commit(ctx.journal.newRecord(writes, [
    JournalRemoval(n.path, expect: n.expect),
    JournalRemoval(n.sidecarPath),
  ]));
  ctx.servedLastModified.remove(n.uuid);
  return LocalResponse.noContent;
}

List<LocalRoute> noteRoutes() => [
      LocalRoute('GET', 'notes', _list),
      LocalRoute('POST', 'notes', _create),
      LocalRoute('GET', 'notes/{id}', (ctx) async => _detail(ctx, await _liveById(ctx))),
      LocalRoute('PATCH', 'notes/{id}', (ctx) async => _update(ctx, await _liveById(ctx))),
      LocalRoute('DELETE', 'notes/{id}', (ctx) async => _delete(ctx, await _liveById(ctx))),
      LocalRoute('GET', 'notes/uuid/{uuid}',
          (ctx) async => _detail(ctx, await _liveByUuid(ctx))),
      LocalRoute('PATCH', 'notes/uuid/{uuid}',
          (ctx) async => _update(ctx, await _liveByUuid(ctx), canEdit: true)),
      LocalRoute('DELETE', 'notes/uuid/{uuid}',
          (ctx) async => _delete(ctx, await _liveByUuid(ctx))),
    ];
