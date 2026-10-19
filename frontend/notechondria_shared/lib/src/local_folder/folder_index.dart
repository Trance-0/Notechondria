import 'folder_fs.dart';
import 'folder_layout.dart';
import 'note_codec.dart';

// `.notechondria/index.json`, the derived read cache (3.8, 6.2 R2). It is
// never the base of a write and is safe to delete. Design review 3 T7(e)
// left its schema to the implementer:
//
// {
//   "schema_version": 1,          // this file's format; other values -> rescan
//   "layout_version": 1,          // manifest layout it was built from
//   "folder_id": "<uuid>",        // a copied index of another folder is ignored
//   "generated_at": "<RFC 3339>",
//   "files": {
//     "<path>": {"size": n, "last_modified": ms, "kind": "<kind>", ...}
//   }
// }
//
// Kinds and their extra keys: `note` and `trash_note` (uuid, title,
// course_slug, is_public), `sidecar` (uuid, id), `course` (id, slug, title,
// client_course_id), `records` (planner/*.json: max_id, needs_ids),
// `history` and `attachments` (max_id), and `file` (anything else).

const int kFolderIndexSchemaVersion = 1;

enum IndexedKind {
  note,
  trashNote,
  sidecar,
  course,
  records,
  history,
  attachments,
  file,
}

const Map<IndexedKind, String> _kindNames = {
  IndexedKind.note: 'note',
  IndexedKind.trashNote: 'trash_note',
  IndexedKind.sidecar: 'sidecar',
  IndexedKind.course: 'course',
  IndexedKind.records: 'records',
  IndexedKind.history: 'history',
  IndexedKind.attachments: 'attachments',
  IndexedKind.file: 'file',
};

/// The kind a path is indexed as.
IndexedKind indexedKindOf(String path) {
  final parent = folderPathParent(path);
  final name = folderPathBasename(path);
  if (isNoteBodyPath(path)) {
    return parent == kNotesDir ? IndexedKind.note : IndexedKind.trashNote;
  }
  if (isSidecarPath(path)) return IndexedKind.sidecar;
  if (parent == kCoursesDir && name.endsWith('.json')) return IndexedKind.course;
  if (parent == kPlannerDir && name.endsWith('.json') && name != 'heatmap.json') {
    return IndexedKind.records;
  }
  if (path.startsWith('$kHistoryDir/') && name == 'index.json') {
    return IndexedKind.history;
  }
  if (path.startsWith('$kAssetsDir/notes/') && name == 'attachments.json') {
    return IndexedKind.attachments;
  }
  return IndexedKind.file;
}

/// The manifest counter a `records`, `history`, or `attachments` file feeds.
String? idKindOfRecordsFile(String path) => switch (folderPathBasename(path)) {
      'events.json' => 'event',
      'feeds.json' => 'feed',
      'sessions.json' => 'session',
      'index.json' => 'version',
      'attachments.json' => 'attachment',
      _ => null,
    };

class IndexedFile {
  const IndexedFile({
    required this.path,
    required this.size,
    required this.lastModified,
    required this.kind,
    this.uuid,
    this.id,
    this.title,
    this.courseSlug,
    this.isPublic,
    this.slug,
    this.clientCourseId,
    this.maxId,
    this.needsIds = false,
  });

  factory IndexedFile.fromJson(String path, Map<String, Object?> json) {
    final kindName = json['kind'];
    final kind = _kindNames.entries
        .firstWhere((e) => e.value == kindName,
            orElse: () => const MapEntry(IndexedKind.file, 'file'))
        .key;
    return IndexedFile(
      path: path,
      size: json['size'] as int,
      lastModified: json['last_modified'] as int,
      kind: kind,
      uuid: json['uuid'] as String?,
      id: json['id'] as int?,
      title: json['title'] as String?,
      courseSlug: json['course_slug'] as String?,
      isPublic: json['is_public'] as bool?,
      slug: json['slug'] as String?,
      clientCourseId: json['client_course_id'] as String?,
      maxId: json['max_id'] as int?,
      needsIds: json['needs_ids'] == true,
    );
  }

  final String path;
  final int size;
  final int lastModified;
  final IndexedKind kind;
  final String? uuid;
  final int? id;
  final String? title;
  final String? courseSlug;
  final bool? isPublic;
  final String? slug;
  final String? clientCourseId;

  /// Largest record id in a `records`, `history`, or `attachments` file.
  final int? maxId;

  /// A record in the file has no id or repeats one (3.7).
  final bool needsIds;

  Map<String, Object?> toJson() => {
        'size': size,
        'last_modified': lastModified,
        'kind': _kindNames[kind],
        if (uuid != null) 'uuid': uuid,
        if (id != null) 'id': id,
        if (title != null) 'title': title,
        if (courseSlug != null) 'course_slug': courseSlug,
        if (isPublic != null) 'is_public': isPublic,
        if (slug != null) 'slug': slug,
        if (clientCourseId != null) 'client_course_id': clientCourseId,
        if (maxId != null) 'max_id': maxId,
        if (needsIds) 'needs_ids': true,
      };
}

/// Folder counts and bytes for the status card (F48).
class FolderCounts {
  const FolderCounts({
    required this.notes,
    required this.trashedNotes,
    required this.courses,
    required this.files,
    required this.bytes,
  });

  final int notes;
  final int trashedNotes;
  final int courses;
  final int files;
  final int bytes;
}

class FolderIndex {
  FolderIndex({
    required this.folderId,
    required this.generatedAt,
    required Map<String, IndexedFile> files,
    this.layoutVersion = kFolderLayoutVersion,
  }) : files = Map<String, IndexedFile>.unmodifiable(files);

  /// Null unless [text] is a current-schema index of [folderId] built from
  /// this layout version; any other index is ignored and the folder is
  /// scanned in full.
  static FolderIndex? tryDecode(String text, {required String folderId}) {
    final json = decodeJsonObject(text);
    if (json == null ||
        json['schema_version'] != kFolderIndexSchemaVersion ||
        json['layout_version'] != kFolderLayoutVersion ||
        json['folder_id'] != folderId) {
      return null;
    }
    final raw = json['files'];
    if (raw is! Map) return null;
    try {
      return FolderIndex(
        folderId: folderId,
        generatedAt: '${json['generated_at'] ?? ''}',
        files: {
          for (final e in raw.entries)
            if (e.value is Map)
              '${e.key}': IndexedFile.fromJson(
                  '${e.key}', Map<String, Object?>.from(e.value as Map)),
        },
      );
    } on TypeError {
      return null;
    }
  }

  final String folderId;
  final int layoutVersion;
  final String generatedAt;
  final Map<String, IndexedFile> files;

  Iterable<IndexedFile> ofKind(IndexedKind kind) =>
      files.values.where((f) => f.kind == kind);

  FolderCounts get counts => FolderCounts(
        notes: ofKind(IndexedKind.note).length,
        trashedNotes: ofKind(IndexedKind.trashNote).length,
        courses: ofKind(IndexedKind.course).length,
        files: files.length,
        bytes: files.values.fold(0, (sum, f) => sum + f.size),
      );

  /// Largest id seen per manifest counter kind (3.7 "never fall behind").
  Map<String, int> get maxIds {
    final out = <String, int>{};
    void see(String kind, int? id) {
      if (id != null && id > (out[kind] ?? 0)) out[kind] = id;
    }

    for (final f in files.values) {
      switch (f.kind) {
        case IndexedKind.sidecar:
          see('note', f.id);
        case IndexedKind.course:
          see('course', f.id);
        case IndexedKind.records:
        case IndexedKind.history:
        case IndexedKind.attachments:
          final kind = idKindOfRecordsFile(f.path);
          if (kind != null) see(kind, f.maxId);
        default:
          break;
      }
    }
    return out;
  }

  String encode() => encodeFolderJson({
        'schema_version': kFolderIndexSchemaVersion,
        'layout_version': layoutVersion,
        'folder_id': folderId,
        'generated_at': generatedAt,
        'files': {for (final e in files.entries) e.key: e.value.toJson()},
      });
}

Future<FolderIndex?> readFolderIndex(FolderFs fs,
    {required String folderId}) async {
  final text = await readTextOrNull(fs, kIndexPath);
  return text == null ? null : FolderIndex.tryDecode(text, folderId: folderId);
}

/// The record list of a `planner/*.json`, `attachments.json`, or history
/// index: a top-level list, or the first list under a known key.
List<Map<String, Object?>>? recordListOf(Object? json) {
  final list = json is Map ? json[recordListKeyOf(json)] : json;
  if (list is! List) return null;
  return [
    for (final item in list)
      if (item is Map) Map<String, Object?>.from(item),
  ];
}

/// The key of the record list inside an object-shaped records file.
String? recordListKeyOf(Map<dynamic, dynamic> json) {
  for (final key in const [
    'events',
    'feeds',
    'sessions',
    'attachments',
    'versions',
    'records',
    'items',
  ]) {
    if (json[key] is List) return key;
  }
  return null;
}

/// Parses one file into its index entry.
IndexedFile indexFile(String path, FolderStat stat, String? text) {
  final kind = indexedKindOf(path);
  IndexedFile plain([IndexedKind k = IndexedKind.file]) => IndexedFile(
      path: path, size: stat.size, lastModified: stat.lastModified, kind: k);
  if (text == null) return plain();
  switch (kind) {
    case IndexedKind.note:
    case IndexedKind.trashNote:
      final note = decodeNoteFile(text, path: path).frontmatter;
      return IndexedFile(
        path: path,
        size: stat.size,
        lastModified: stat.lastModified,
        kind: kind,
        uuid: note.uuid,
        title: note.title,
        courseSlug: note.courseSlug,
        isPublic: note.isPublic,
      );
    case IndexedKind.sidecar:
      final sidecar = decodeSidecar(text);
      return IndexedFile(
        path: path,
        size: stat.size,
        lastModified: stat.lastModified,
        kind: kind,
        uuid: sidecar?.uuid,
        id: sidecar?.id,
      );
    case IndexedKind.course:
      final json = decodeJsonObject(text);
      if (json == null) return plain(kind);
      // Course files may be edited by hand: wrong types read as absent.
      final client = jsonString(json['client_course_id']);
      return IndexedFile(
        path: path,
        size: stat.size,
        lastModified: stat.lastModified,
        kind: kind,
        id: jsonInt(json['id']),
        slug: jsonString(json['slug']),
        title: jsonString(json['title']),
        clientCourseId: client != null && client.isNotEmpty ? client : null,
      );
    case IndexedKind.records:
    case IndexedKind.history:
    case IndexedKind.attachments:
      final records = recordListOf(decodeJsonValue(text));
      var maxId = 0;
      var needsIds = false;
      final seen = <int>{};
      for (final r in records ?? const <Map<String, Object?>>[]) {
        final id = r['id'];
        if (id is! int) {
          needsIds = true;
          continue;
        }
        if (!seen.add(id)) needsIds = true;
        if (id > maxId) maxId = id;
      }
      return IndexedFile(
        path: path,
        size: stat.size,
        lastModified: stat.lastModified,
        kind: kind,
        maxId: maxId,
        needsIds: kind == IndexedKind.records && needsIds,
      );
    case IndexedKind.file:
      return plain();
  }
}

/// Whether [path] must be read to index it (other files are only stat-ed).
bool indexReadsContent(String path) => indexedKindOf(path) != IndexedKind.file;
