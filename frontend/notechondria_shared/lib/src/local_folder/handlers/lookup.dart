import '../folder_fs.dart';
import '../folder_index.dart';
import '../folder_layout.dart';
import '../router.dart';
import 'records.dart';

// Index-backed note lookups (6.2 R2, phase 1b review P1B-1). The in-memory
// index locates a note and holds the fields of the list summaries; a
// handler re-reads from disk only the notes it serves or rewrites, so a
// single-note request costs a few file calls instead of a read of every
// note inside the lock hold (R4). The index lacks notes that another tab or
// an outside program added since this tab's last scan, so a lookup that
// misses lists `notes/` (and `trash/notes/`), indexes the files it lacks,
// and tries again; the list routes run the same listing first.

/// Reads in flight at once where a route reads many files (a search, or a
/// listing that finds many new notes). Chromium's folder backend answers
/// parallel reads faster than reads one after another.
const int kFolderReadBatch = 32;

/// [read] for every item, [kFolderReadBatch] at a time, in item order.
Future<List<T>> readInBatches<S, T>(
    List<S> items, Future<T> Function(S item) read) async {
  final out = <T>[];
  for (var i = 0; i < items.length; i += kFolderReadBatch) {
    out.addAll(await Future.wait(
        [for (final item in items.skip(i).take(kFolderReadBatch)) read(item)]));
  }
  return out;
}

/// The skip set of a lookup. Reads skip the paths of a pending record that
/// failed to roll forward (6.2 R3). Writes look notes up without it, so the
/// write itself is refused with `writeBlockedByJournal` instead of a 404
/// or a second note for the same draft (P1B-3).
Set<String> lookupSkip(LocalHandlerContext ctx) =>
    ctx.request.isRead ? ctx.skipPaths : const <String>{};

/// Lists `notes/` (and, with [trashed], `trash/notes/`; without [live],
/// only that): drops index entries whose file is gone and indexes files
/// the index lacks, reading only those. Paths in [skip] are not read. True
/// when the index changed.
Future<bool> refreshNoteListing(LocalHandlerContext ctx,
    {bool live = true, bool trashed = false, Set<String> skip = const {}}) async {
  final index = ctx.index;
  final changes = <String, IndexedFile?>{};
  for (final dir in [if (live) kNotesDir, if (trashed) kTrashNotesDir]) {
    final listed = <String>{
      for (final e in await listOrEmpty(ctx.fs, dir))
        if (e.isFile) joinFolderPath(dir, e.name),
    };
    for (final path in index.files.keys) {
      if (folderPathParent(path) == dir && !listed.contains(path)) {
        changes[path] = null;
      }
    }
    final fresh = [
      for (final path in listed)
        if (!index.files.containsKey(path) && !skip.contains(path)) path,
    ];
    final entries = await readInBatches(fresh, (String path) async {
      final stat = await ctx.fs.stat(path);
      if (stat == null) return null;
      final text =
          indexReadsContent(path) ? await readTextOrNull(ctx.fs, path) : null;
      return indexFile(path, stat, text);
    });
    for (var i = 0; i < fresh.length; i++) {
      final entry = entries[i];
      if (entry != null) changes[fresh[i]] = entry;
    }
  }
  if (changes.isNotEmpty) ctx.updateIndex(changes);
  return changes.isNotEmpty;
}

/// Re-reads [n] from disk. A note that is gone, or is no longer a note, is
/// dropped from the index (a later listing or scan indexes it again); a
/// body that changed since it was indexed gets fresh entries.
Future<NoteRecord?> rereadNote(LocalHandlerContext ctx, IndexedNote n,
    {Set<String> skip = const {}}) async {
  final record = await readNoteAt(ctx.fs, n.path, skip: skip);
  if (record == null) {
    ctx.updateIndex({n.path: null, n.sidecarPath: null});
    return null;
  }
  if (!record.stat.sameAs(n.body.size, n.body.lastModified)) {
    final sidecarStat = await ctx.fs.stat(record.sidecarPath);
    ctx.updateIndex({
      record.path: indexNoteBody(record.path, record.stat, record.note),
      if (sidecarStat != null)
        record.sidecarPath:
            indexSidecar(record.sidecarPath, sidecarStat, record.sidecar),
    });
  }
  return record;
}

/// Notes the index places where [where] holds, re-read from disk and kept
/// when [verify] holds for what is on disk, in [indexedNotes] order (live
/// before trashed). Stops after [limit] notes. Paths re-read are added to
/// [tried], and paths already in it are not re-read. When nothing is found
/// and [refreshOnMiss] is set, the listing is refreshed and the new
/// candidates are tried. The skip set is [lookupSkip].
Future<List<NoteRecord>> findNotes(
  LocalHandlerContext ctx, {
  required bool Function(IndexedNote n) where,
  required bool Function(NoteRecord n) verify,
  bool live = true,
  bool trashed = false,
  int? limit,
  Set<String>? tried,
  bool refreshOnMiss = true,
}) async {
  final skip = lookupSkip(ctx);
  final seen = tried ?? <String>{};
  final found = <NoteRecord>[];
  Future<void> pass() async {
    for (final n in indexedNotes(ctx.index,
        live: live, trashed: trashed, skip: skip)) {
      if (limit != null && found.length >= limit) return;
      if (seen.contains(n.path) || !where(n)) continue;
      seen.add(n.path);
      final record = await rereadNote(ctx, n, skip: skip);
      if (record != null && verify(record)) found.add(record);
    }
  }

  await pass();
  if (found.isEmpty &&
      refreshOnMiss &&
      await refreshNoteListing(ctx, live: live, trashed: trashed, skip: skip)) {
    await pass();
  }
  return found;
}

/// The note with sidecar id [id], re-read from disk, or null.
Future<NoteRecord?> noteById(LocalHandlerContext ctx, int id,
        {bool live = true, bool trashed = false}) async =>
    (await findNotes(ctx,
            where: (n) => n.id == id,
            verify: (n) => n.id == id,
            live: live,
            trashed: trashed,
            limit: 1))
        .firstOrNull;

/// The note with UUID [uuid], re-read from disk, or null.
Future<NoteRecord?> noteByUuid(LocalHandlerContext ctx, String uuid,
        {bool live = true, bool trashed = false}) async =>
    (await findNotes(ctx,
            where: (n) => n.uuid == uuid,
            verify: (n) => n.uuid == uuid,
            live: live,
            trashed: trashed,
            limit: 1))
        .firstOrNull;
