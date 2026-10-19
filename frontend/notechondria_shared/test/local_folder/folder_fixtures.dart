// Shared fixtures for the local folder unit tests (not a test file).
import 'package:notechondria_shared/local_folder_testing.dart';
import 'package:notechondria_shared/src/local_folder/folder_fs.dart';
import 'package:notechondria_shared/src/local_folder/folder_journal.dart';
import 'package:notechondria_shared/src/local_folder/folder_layout.dart';
import 'package:notechondria_shared/src/local_folder/note_codec.dart';

const String kTestFolderId = 'f0000000-0000-4000-8000-000000000001';

/// A folder initialized the way Connect does (README.md, manifest.json).
Future<MemoryFolderFs> newNotechondriaFolder(
    {String name = 'Notes', String folderId = kTestFolderId}) async {
  final fs = MemoryFolderFs(name: name);
  for (final file in initialFolderFiles(
      folderId: folderId, appVersion: 'test', now: DateTime.utc(2026, 10, 19))) {
    await fs.writeText(file.path, file.text);
  }
  return fs;
}

/// Note text as the codec writes it.
String noteText(String uuid, String title, String body,
        {bool trashed = false}) =>
    encodeNoteFile(NoteFrontmatter(title: title, uuid: uuid), body,
        path: noteBodyPath(uuidHex(uuid), trashed: trashed));

/// "Create a note" as a handler builds it (3.4.1): re-read the manifest,
/// allocate the id, journal `.md`, sidecar, and manifest. The caller holds
/// the exclusive lock.
Future<({int id, String uuid})> createNoteOp(
  FolderFs fs,
  FolderJournal journal, {
  String title = 'Note',
  String body = 'Body',
  String? uuid,
}) async {
  final manifest = (await readFolderManifest(fs))!;
  final (updated, id) = manifest.allocate('note');
  final u = uuid ?? newUuidV4();
  final path = noteBodyPath(uuidHex(u));
  await journal.commit(journal.newRecord([
    JournalWrite(path, noteText(u, title, body)),
    JournalWrite(sidecarPathForBody(path), NoteSidecar(id: id, uuid: u).encode()),
    JournalWrite(kManifestPath, updated.encode()),
  ]));
  return (id: id, uuid: u);
}

/// The journal record of "move a note to the trash" (3.5): trash copy and
/// sidecar, recycle bin pointer, then the removals of the live files.
Future<JournalRecord> trashNoteRecord(
    FolderFs fs, FolderJournal journal, String uuid) async {
  final path = noteBodyPath(uuidHex(uuid));
  final trashPath = noteBodyPath(uuidHex(uuid), trashed: true);
  final text = await fs.readText(path);
  final stat = (await fs.stat(path))!;
  final decoded = decodeNoteFile(text, path: path);
  final sidecar = decodeSidecar(await fs.readText(sidecarPathForBody(path)))!;
  final trashedSidecar = NoteSidecar.fromJson(
      {...sidecar.toJson(), 'deleted_at': '2026-10-19T00:00:00Z'});
  return journal.newRecord([
    JournalWrite(
        trashPath,
        encodeNoteFile(decoded.frontmatter.copyWith(isPublic: false),
            decoded.body,
            path: trashPath)),
    JournalWrite(sidecarPathForBody(trashPath), trashedSidecar.encode()),
    JournalWrite(kRecycleBinPath,
        encodeFolderJson({'schema_version': 1, 'notes': [uuid]})),
  ], [
    JournalRemoval(path, expect: JournalExpect.of(stat)),
    JournalRemoval(sidecarPathForBody(path)),
  ]);
}

/// Every file except the journal directory, as path -> text.
Map<String, String> folderTexts(MemoryFolderFs fs) => {
      for (final p in fs.paths)
        if (!p.startsWith('$kJournalDir/')) p: fs.textOf(p)!,
    };
