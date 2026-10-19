import '../folder_fs.dart';
import '../folder_index.dart';
import '../folder_journal.dart';
import '../folder_layout.dart';
import '../folder_messages.dart';
import '../note_codec.dart';
import '../router.dart';
import 'lookup.dart';
import 'notes.dart' show frontmatterWith, servedDetail, sidecarWith;
import 'records.dart';

// Trash routes (4.1 "Trash", 3.5): the list, restore (journaled, removals
// last, `is_public` stays false), and empty trash with the cascade over
// history, assets, sessions, and comment links, one trashed note per chunk.

Future<LocalResponse> _list(LocalHandlerContext ctx) async {
  await refreshNoteListing(ctx, live: false, trashed: true, skip: ctx.skipPaths);
  final trashed =
      indexedNotes(ctx.index, live: false, trashed: true, skip: ctx.skipPaths);
  final profile = await FolderProfile.read(ctx.fs, folderName: ctx.folderName);
  final courses = CourseLookup(await readCourses(ctx.fs, skip: ctx.skipPaths));
  String deletedAt(IndexedNote n) =>
      n.deletedAt ?? isoOfMillis(n.body.lastModified);
  trashed.sort((a, b) => deletedAt(b).compareTo(deletedAt(a)));
  return LocalResponse(200, [
    for (final n in trashed)
      {
        ...indexedNoteSummary(n, courses, profile.author),
        'deleted_at': deletedAt(n),
        'recycle_bin_entry_id': n.id,
      },
  ]);
}

Future<LocalResponse> _restore(LocalHandlerContext ctx) async {
  final id = ctx.request.intParam('id');
  final n = await noteById(ctx, id, live: false, trashed: true);
  if (n == null) {
    throw LocalHttpError(404, LocalFolderMessages.trashedNoteNotFound(id));
  }
  final livePath = noteBodyPath(n.stem);
  if (await ctx.fs.stat(livePath) != null) {
    throw LocalHttpError(
        409,
        LocalFolderMessages.invalidField('Note not restored', 'notes',
            "'$livePath' already exists in the folder"));
  }
  final fm = frontmatterWith(n.frontmatter,
      isPublic: false, lastEdit: ctx.now().toUtc().toIso8601String());
  final bin = await readRecycleBin(ctx.fs);
  await ctx.commit(ctx.journal.newRecord([
    JournalWrite(livePath, encodeNoteFile(fm, n.note.body, path: livePath)),
    JournalWrite(sidecarPathForBody(livePath),
        sidecarWith(n.sidecar, {'deleted_at': null}).encode()),
    JournalWrite(kRecycleBinPath,
        encodeRecycleBin([...bin.where((i) => i['id'] != n.id)])),
  ], [
    JournalRemoval(n.path, expect: n.expect),
    JournalRemoval(n.sidecarPath),
  ]));
  return LocalResponse(200, await servedDetail(ctx, livePath));
}

/// `planner/sessions.json` without the records of [n], or null when the
/// file has none of them.
Future<String?> _sessionsWithout(FolderFs fs, NoteRecord n) async {
  final text = await readTextOrNull(fs, kPlannerSessionsPath);
  if (text == null) return null;
  final json = decodeJsonValue(text);
  final records = recordListOf(json);
  bool names(Map<String, Object?> r) =>
      r['note_uuid'] == n.uuid || r['note_id'] == n.id;
  if (records == null || !records.any(names)) return null;
  final kept = [...records.where((r) => !names(r))];
  final key = json is Map ? recordListKeyOf(json) : null;
  return encodeFolderJson(key == null ? kept : {...(json as Map), key: kept});
}

/// One trashed note, permanently (3.5): its files, `history/<hex>/`,
/// `assets/notes/<hex>/`, its sessions, its pointer, and the
/// `source_note_uuid` of its comment notes.
Future<void> _purge(LocalHandlerContext ctx, NoteRecord n) async {
  final hex = uuidHex(n.uuid);
  final writes = <JournalWrite>[];
  final sessions = await _sessionsWithout(ctx.fs, n);
  if (sessions != null) writes.add(JournalWrite(kPlannerSessionsPath, sessions));
  final comments = await findNotes(ctx,
      where: (c) => c.path != n.path && c.sourceNoteUuid == n.uuid,
      verify: (c) => c.sidecar.sourceNoteUuid == n.uuid,
      trashed: true,
      refreshOnMiss: false);
  for (final c in comments) {
    writes.add(JournalWrite(
        c.sidecarPath, sidecarWith(c.sidecar, {'source_note_uuid': null}).encode()));
  }
  final bin = await readRecycleBin(ctx.fs);
  if (bin.any((i) => i['id'] == n.id)) {
    writes.add(JournalWrite(
        kRecycleBinPath, encodeRecycleBin([...bin.where((i) => i['id'] != n.id)])));
  }
  await ctx.commit(ctx.journal.newRecord(writes, [
    JournalRemoval(n.path, expect: n.expect),
    JournalRemoval(n.sidecarPath),
    JournalRemoval('$kHistoryDir/$hex', directory: true),
    JournalRemoval('$kAssetsDir/notes/$hex', directory: true),
  ]));
}

/// One trashed note per chunk (R4). The first chunk refreshes the listing of
/// both note directories; each chunk then takes the next trashed note of
/// the index and re-reads it (P1B-1).
Future<LocalResponse> _empty(LocalHandlerContext ctx) async {
  final total = await ctx.chunk(() async {
    await refreshNoteListing(ctx, trashed: true);
    return indexedNotes(ctx.index, live: false, trashed: true).length;
  });
  var count = 0;
  final seen = <String>{};
  try {
    while (await ctx.chunk(() async {
      final next = await findNotes(ctx,
          where: (_) => true,
          verify: (_) => true,
          live: false,
          trashed: true,
          limit: 1,
          tried: seen,
          refreshOnMiss: false);
      if (next.isEmpty) return false;
      final n = next.single;
      await _purge(ctx, n);
      count++;
      ctx.setBusy(LocalFolderMessages.folderBusy('write', 'Emptying the trash',
          count, total < count ? count : total));
      return true;
    })) {}
  } finally {
    ctx.setBusy(null);
  }
  return LocalResponse(200, {'count': count, 'deleted_count': count});
}

List<LocalRoute> trashRoutes() => [
      LocalRoute('GET', 'notes/deleted', _list),
      LocalRoute('DELETE', 'notes/deleted/empty', _empty, chunked: true),
      LocalRoute('POST', 'notes/{id}/restore', _restore),
    ];
