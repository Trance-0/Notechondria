import 'folder_fs.dart';
import 'folder_index.dart';
import 'folder_journal.dart';
import 'folder_layout.dart';
import 'folder_messages.dart';
import 'note_codec.dart';

// Duplicate identities, adoption, and record ids (storage rules 3.7). The
// scanner plans fixes from the index ([planIdentityFixes]) and applies each
// one as its own journaled operation inside an exclusive hold
// ([applyIdentityFix]), re-reading every file first (6.2 R2) and skipping a
// fix whose conflict is gone.

sealed class IdentityFix {
  const IdentityFix(this.path);

  /// The file that changes identity.
  final String path;
}

/// A note that claims a UUID [keeper] keeps: new UUID, id, and sidecar.
class ReassignNoteUuid extends IdentityFix {
  const ReassignNoteUuid(super.path, {required this.uuid, required this.keeper});
  final String uuid;
  final String keeper;
}

/// A note without a complete sidecar: write one, keeping [uuid] and [id]
/// when they are unique.
class AdoptNote extends IdentityFix {
  const AdoptNote(super.path, {this.uuid, this.id});
  final String? uuid;
  final int? id;
}

/// A note whose sidecar repeats another note's id.
class ReassignNoteId extends IdentityFix {
  const ReassignNoteId(super.path, {required this.id, required this.keeper});
  final int id;
  final String keeper;
}

/// A course file with a missing or repeated `id` or `client_course_id`.
class FixCourseIdentity extends IdentityFix {
  const FixCourseIdentity(super.path,
      {required this.newId, required this.newClientId, this.keeper});
  final bool newId;
  final bool newClientId;
  final String? keeper;
}

/// A `planner/*.json` file with a record that lacks an id or repeats one.
class FixRecordIds extends IdentityFix {
  const FixRecordIds(super.path);
}

class _Claim {
  _Claim(this.note, this.sidecar);
  final IndexedFile note;
  final IndexedFile? sidecar;

  /// The sidecar's UUID wins over the frontmatter's, which is regenerated on
  /// write (3.2).
  String? get uuid => sidecar?.uuid ?? note.uuid;
  bool get ownSidecarCarries => sidecar?.uuid != null && sidecar!.uuid == uuid;
  bool get stemIsUuid =>
      uuid != null && noteStemOf(note.path).toLowerCase() == uuidHex(uuid!);
}

int _byKeeperOrder(_Claim a, _Claim b) {
  int rank(_Claim c) => (c.ownSidecarCarries ? 0 : 2) + (c.stemIsUuid ? 0 : 1);
  final r = rank(a).compareTo(rank(b));
  return r != 0 ? r : a.note.path.compareTo(b.note.path);
}

/// Plans the 3.7 fixes. Keeper order for one UUID: the file whose own
/// sidecar carries it, then the file whose stem is its hex, then the
/// lexicographically first path.
List<IdentityFix> planIdentityFixes(Map<String, IndexedFile> files) {
  final fixes = <IdentityFix>[];
  final claims = [
    for (final f in files.values)
      if (f.kind == IndexedKind.note || f.kind == IndexedKind.trashNote)
        _Claim(f, files[sidecarPathForBody(f.path)]),
  ]..sort((a, b) => a.note.path.compareTo(b.note.path));

  final byUuid = <String, List<_Claim>>{};
  for (final c in claims) {
    if (c.uuid != null) (byUuid[c.uuid!] ??= []).add(c);
  }
  final losers = <String>{};
  for (final group in byUuid.values) {
    if (group.length < 2) continue;
    group.sort(_byKeeperOrder);
    for (final c in group.skip(1)) {
      losers.add(c.note.path);
      fixes.add(ReassignNoteUuid(c.note.path,
          uuid: c.uuid!, keeper: group.first.note.path));
    }
  }

  final remaining = claims.where((c) => !losers.contains(c.note.path)).toList();
  final idOwners = <int, List<_Claim>>{};
  for (final c in remaining) {
    final id = c.sidecar?.id;
    if (id != null) (idOwners[id] ??= []).add(c);
  }
  final idLosers = <String>{};
  for (final entry in idOwners.entries) {
    if (entry.value.length < 2) continue;
    entry.value.sort(_byKeeperOrder);
    for (final c in entry.value.skip(1)) {
      idLosers.add(c.note.path);
      fixes.add(ReassignNoteId(c.note.path,
          id: entry.key, keeper: entry.value.first.note.path));
    }
  }
  for (final c in remaining) {
    final sidecar = c.sidecar;
    if (sidecar != null && sidecar.uuid != null && sidecar.id != null) continue;
    final id = sidecar?.id;
    fixes.add(AdoptNote(c.note.path,
        uuid: c.uuid,
        id: id != null && !idLosers.contains(c.note.path) ? id : null));
  }

  final courses = [
    for (final f in files.values)
      if (f.kind == IndexedKind.course) f,
  ]..sort((a, b) => a.path.compareTo(b.path));
  int courseRank(IndexedFile f) =>
      f.slug != null && folderPathBasename(f.path) == '${f.slug}.json' ? 0 : 1;
  int courseOrder(IndexedFile a, IndexedFile b) {
    final r = courseRank(a).compareTo(courseRank(b));
    return r != 0 ? r : a.path.compareTo(b.path);
  }

  final idKeeper = <String, String>{};
  final clientKeeper = <String, String>{};
  for (final key in ['id', 'client']) {
    final groups = <Object, List<IndexedFile>>{};
    for (final f in courses) {
      final value = key == 'id' ? f.id : f.clientCourseId;
      if (value != null) (groups[value] ??= []).add(f);
    }
    for (final group in groups.values) {
      group.sort(courseOrder);
      for (final f in group.skip(1)) {
        (key == 'id' ? idKeeper : clientKeeper)[f.path] = group.first.path;
      }
    }
  }
  for (final f in courses) {
    final newId = f.id == null || idKeeper.containsKey(f.path);
    final newClient = clientKeeper.containsKey(f.path);
    if (newId || newClient) {
      fixes.add(FixCourseIdentity(f.path,
          newId: newId,
          newClientId: newClient,
          keeper: idKeeper[f.path] ?? clientKeeper[f.path]));
    }
  }

  for (final f in files.values) {
    if (f.kind == IndexedKind.records && f.needsIds) fixes.add(FixRecordIds(f.path));
  }
  return fixes;
}

String? _claimOf(String? mdText, NoteSidecar? sidecar) =>
    sidecar?.uuid ?? (mdText == null ? null : frontmatterUuidOf(mdText));

/// Applies one fix as a journaled operation. The caller holds the exclusive
/// lock and has rolled forward leftover records. Returns the paths it
/// changed (empty when the conflict is gone).
Future<Set<String>> applyIdentityFix(
    FolderFs fs, FolderJournal journal, IdentityFix fix) async {
  final manifest = await readFolderManifest(fs);
  if (manifest == null) return const {};
  switch (fix) {
    case ReassignNoteUuid(:final path, :final uuid, :final keeper):
      final text = await readTextOrNull(fs, path);
      final stat = await fs.stat(path);
      final sidecarText = await readTextOrNull(fs, sidecarPathForBody(path));
      final sidecar = sidecarText == null ? null : decodeSidecar(sidecarText);
      if (text == null || stat == null || _claimOf(text, sidecar) != uuid) {
        return const {};
      }
      final keeperText = await readTextOrNull(fs, keeper);
      final keeperSidecarText =
          await readTextOrNull(fs, sidecarPathForBody(keeper));
      final keeperSidecar =
          keeperSidecarText == null ? null : decodeSidecar(keeperSidecarText);
      if (_claimOf(keeperText, keeperSidecar) != uuid) return const {};
      final (updated, id) = manifest.allocate('note');
      final fresh = newUuidV4();
      final newText = replaceFrontmatterUuid(text, fresh);
      await journal.commit(journal.newRecord([
        if (newText != null)
          JournalWrite(path, newText, expect: JournalExpect.of(stat)),
        JournalWrite(sidecarPathForBody(path),
            (sidecar ?? NoteSidecar()).forCopy(id: id, uuid: fresh).encode()),
        JournalWrite(kManifestPath, updated.encode()),
      ]));
      await stampNoteSidecar(fs, path);
      journal.log(LocalFolderLogLevel.info,
          LocalFolderMessages.identityReassigned(path, uuid, keeper, fresh));
      return {path, sidecarPathForBody(path), kManifestPath};

    case AdoptNote(:final path, uuid: final keepUuid, id: final keepId):
      final stat = await fs.stat(path);
      final sidecarText = await readTextOrNull(fs, sidecarPathForBody(path));
      final sidecar = sidecarText == null ? null : decodeSidecar(sidecarText);
      if (stat == null || (sidecar?.uuid != null && sidecar?.id != null)) {
        return const {};
      }
      var next = manifest;
      final int id;
      final existing = keepId ?? sidecar?.id;
      if (existing != null) {
        id = existing;
      } else {
        final allocated = manifest.allocate('note');
        next = allocated.$1;
        id = allocated.$2;
      }
      final uuid = sidecar?.uuid ?? keepUuid ?? newUuidV4();
      await journal.commit(journal.newRecord([
        JournalWrite(
            sidecarPathForBody(path),
            (sidecar ?? NoteSidecar())
                .copyWith(
                    id: id,
                    uuid: uuid,
                    mdSize: stat.size,
                    mdLastModified: stat.lastModified)
                .encode()),
        if (!identical(next, manifest))
          JournalWrite(kManifestPath, next.encode()),
      ]));
      journal.log(LocalFolderLogLevel.info,
          LocalFolderMessages.noteAdopted(path, id, uuid));
      return {sidecarPathForBody(path), kManifestPath};

    case ReassignNoteId(:final path, :final id, :final keeper):
      final sidecarText = await readTextOrNull(fs, sidecarPathForBody(path));
      final sidecar = sidecarText == null ? null : decodeSidecar(sidecarText);
      final keeperText = await readTextOrNull(fs, sidecarPathForBody(keeper));
      final keeperId = keeperText == null ? null : decodeSidecar(keeperText)?.id;
      if (sidecar?.id != id || keeperId != id) return const {};
      final (updated, fresh) = manifest.allocate('note');
      await journal.commit(journal.newRecord([
        JournalWrite(
            sidecarPathForBody(path), sidecar!.copyWith(id: fresh).encode()),
        JournalWrite(kManifestPath, updated.encode()),
      ]));
      journal.log(LocalFolderLogLevel.info,
          LocalFolderMessages.recordIdReassigned(path, 'note', id, keeper, fresh));
      return {sidecarPathForBody(path), kManifestPath};

    case FixCourseIdentity(:final path, :final newId, :final newClientId):
      final text = await readTextOrNull(fs, path);
      final json = text == null ? null : decodeJsonObject(text);
      if (json == null) return const {};
      var next = manifest;
      final oldId = json['id'];
      if (newId) {
        final (updated, id) = manifest.allocate('course');
        next = updated;
        json['id'] = id;
      }
      if (newClientId) json['client_course_id'] = 'fld_${uuidHex(newUuidV4())}';
      await journal.commit(journal.newRecord([
        JournalWrite(path, encodeFolderJson(json)),
        JournalWrite(kManifestPath, next.encode()),
      ]));
      if (oldId is int && newId) {
        journal.log(
            LocalFolderLogLevel.info,
            LocalFolderMessages.recordIdReassigned(
                path, 'course', oldId, fix.keeper ?? path, json['id'] as int));
      }
      return {path, kManifestPath};

    case FixRecordIds(:final path):
      final kind = idKindOfRecordsFile(path);
      final text = await readTextOrNull(fs, path);
      final decoded = text == null ? null : decodeJsonValue(text);
      final records = recordListOf(decoded);
      if (kind == null || records == null) return const {};
      var next = manifest;
      final seen = <int>{};
      var changed = false;
      for (final r in records) {
        final id = r['id'];
        if (id is int && seen.add(id)) continue;
        final (updated, fresh) = next.allocate(kind);
        next = updated;
        r['id'] = fresh;
        seen.add(fresh);
        changed = true;
      }
      if (!changed) return const {};
      Object? container = records;
      if (decoded is Map) {
        container = {...decoded, recordListKeyOf(decoded)!: records};
      }
      await journal.commit(journal.newRecord([
        JournalWrite(path, encodeFolderJson(container)),
        JournalWrite(kManifestPath, next.encode()),
      ]));
      return {path, kManifestPath};
  }
}
