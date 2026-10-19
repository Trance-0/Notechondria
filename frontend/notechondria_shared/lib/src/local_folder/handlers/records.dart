import 'dart:convert';

import '../folder_fs.dart';
import '../folder_index.dart';
import '../folder_journal.dart';
import '../folder_layout.dart';
import '../folder_messages.dart';
import '../note_codec.dart';
import '../router.dart';

// Folder records the Phase 1 handlers share, and the backend payload shapes
// they answer with: NoteSummarySerializer, NoteDetailSerializer,
// CourseSerializer, and creator_summary_payload (backend/notes/api.py).
// A handler locates notes through the in-memory index (`lookup.dart`) and
// re-reads from disk, inside its hold, the note it serves and every file it
// rewrites (6.2 R2). List summaries come from the index entries, which hold
// the summary fields (P1B-1); the index is never the base of a write.

const String kProfileCreatorPath = 'profile/creator.json';
const String kProfileSettingsPath = 'profile/settings.json';
const String kProfileSkillPath = 'profile/skill.md';

/// The username of a folder that has no `profile/creator.json` yet.
const String kFolderDefaultUsername = 'local-folder';

String isoOfMillis(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

/// A text field the backend serializes as a string (`metadata_json`,
/// `custom_meta`): strings pass, null is '', anything else is JSON.
String textField(Object? value) =>
    value == null ? '' : (value is String ? value : jsonEncode(value));

int wordCountOf(String text) =>
    text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

/// `courses/<slug>.json`.
class CourseRecord {
  CourseRecord(this.path, Map<String, Object?> json)
      : json = Map<String, Object?>.unmodifiable(json);

  final String path;
  final Map<String, Object?> json;

  int? get id => jsonInt(json['id']);
  String get slug {
    final base = folderPathBasename(path);
    return jsonString(json['slug']) ??
        (base.endsWith('.json') ? base.substring(0, base.length - 5) : base);
  }

  String get title => jsonString(json['title']) ?? slug;
  int get sortOrder => jsonInt(json['sort_order']) ?? 0;
  String? get clientCourseId {
    final v = jsonString(json['client_course_id']);
    return v == null || v.isEmpty ? null : v;
  }

  CourseRecord copyWith(Map<String, Object?> changes) =>
      CourseRecord(path, {...json, ...changes});

  String encode() =>
      encodeFolderJson({...json, 'schema_version': kFolderSchemaVersion});
}

Future<List<CourseRecord>> readCourses(FolderFs fs,
    {Set<String> skip = const {}}) async {
  final out = <CourseRecord>[];
  for (final e in await listOrEmpty(fs, kCoursesDir)) {
    if (!e.isFile || !e.name.endsWith('.json')) continue;
    final path = joinFolderPath(kCoursesDir, e.name);
    if (skip.contains(path)) continue;
    final text = await readTextOrNull(fs, path);
    final json = text == null ? null : decodeJsonObject(text);
    if (json == null) continue;
    final record = CourseRecord(path, json);
    if (record.id != null) out.add(record);
  }
  return out;
}

/// Courses by slug and id, for the `course` and `course_id` keys of notes.
class CourseLookup {
  CourseLookup(List<CourseRecord> courses)
      : bySlug = {for (final c in courses) c.slug: c},
        byId = {for (final c in courses) c.id!: c};
  final Map<String, CourseRecord> bySlug;
  final Map<int, CourseRecord> byId;
}

/// Backend course order (`course_sort_key`): a set `sort_order` first,
/// then by title. A folder has no subscriptions.
int compareCourses(CourseRecord a, CourseRecord b) {
  final ra = a.sortOrder > 0 ? 1 : 3;
  final rb = b.sortOrder > 0 ? 1 : 3;
  if (ra != rb) return ra.compareTo(rb);
  if (a.sortOrder != b.sortOrder) return a.sortOrder.compareTo(b.sortOrder);
  return a.title.toLowerCase().compareTo(b.title.toLowerCase());
}

/// A note body with its sidecar. Notes without a sidecar id are left out
/// until a scan adopts them (3.8).
class NoteRecord {
  NoteRecord({
    required this.path,
    required this.text,
    required this.stat,
    required this.note,
    required this.sidecar,
  });

  final String path;
  final String text;
  final FolderStat stat;
  final DecodedNote note;
  final NoteSidecar sidecar;

  bool get trashed => folderPathParent(path) == kTrashNotesDir;
  String get stem => noteStemOf(path);
  String get sidecarPath => sidecarPathForBody(path);
  int get id => sidecar.id!;
  String get uuid => sidecar.uuid ?? note.frontmatter.uuid!;
  NoteFrontmatter get frontmatter => note.frontmatter;
  JournalExpect get expect => JournalExpect.of(stat);
}

/// A note as the index knows it: its body entry and its sidecar entry. The
/// summary of a note read from disk is built through this type too, so a
/// list row and a detail answer cannot drift apart.
class IndexedNote {
  const IndexedNote(this.body, this.sidecar);

  /// The entries of a note just read from disk. The sidecar's size and
  /// `lastModified` are not known here and are not used by a summary.
  factory IndexedNote.of(NoteRecord n) => IndexedNote(
      indexNoteBody(n.path, n.stat, n.note),
      indexSidecar(n.sidecarPath, const FolderStat(size: 0, lastModified: 0),
          n.sidecar));

  final IndexedFile body;
  final IndexedFile sidecar;

  String? _text(IndexedFile f, String key) => jsonString(f.summary[key]);

  String get path => body.path;
  String get sidecarPath => sidecar.path;
  bool get trashed => body.kind == IndexedKind.trashNote;
  int get id => sidecar.id!;
  String get uuid => sidecar.uuid ?? body.uuid!;
  String get title => body.title ?? noteStemOf(path);
  String? get courseSlug => body.courseSlug;
  bool get isPublic => body.isPublic ?? false;
  String get editorMode => _text(body, 'editor_mode') ?? 'P';
  String? get lastEdit => _text(body, 'last_edit');
  String? get dateCreated => _text(body, 'date_created');

  /// Null for an empty body (the summary then uses the description).
  String? get excerpt => _text(body, 'excerpt');
  List<String> get previewLines => [
        for (final line in jsonList(body.summary['preview_lines']))
          if (line is String) line,
      ];
  String get description => _text(sidecar, 'description') ?? '';
  String get name => _text(sidecar, 'name') ?? '';
  String get noteType => _text(sidecar, 'note_type') ?? 'N';
  String? get sourceNoteUuid => _text(sidecar, 'source_note_uuid');
  String get coverImageUrl => _text(sidecar, 'cover_image_url') ?? '';
  String? get clientDraftId => _text(sidecar, 'client_draft_id');
  String? get deletedAt => _text(sidecar, 'deleted_at');

  /// `last_edit`, or the body's `lastModified` when the frontmatter has none.
  String get lastEditOrModified => lastEdit ?? isoOfMillis(body.lastModified);
}

/// The note at [path] with its sidecar (stat, body, sidecar: three file
/// calls), or null when either is missing, the sidecar has no id, or the
/// note has no UUID.
Future<NoteRecord?> readNoteAt(FolderFs fs, String path,
    {Set<String> skip = const {}}) async {
  final sidecarPath = sidecarPathForBody(path);
  if (skip.contains(path) || skip.contains(sidecarPath)) return null;
  final stat = await fs.stat(path);
  final text = await readTextOrNull(fs, path);
  if (stat == null || text == null) return null;
  final sidecarText = await readTextOrNull(fs, sidecarPath);
  final sidecar = sidecarText == null ? null : decodeSidecar(sidecarText);
  if (sidecar == null || sidecar.id == null) return null;
  final note = decodeNoteFile(text, path: path);
  if (sidecar.uuid == null && note.frontmatter.uuid == null) return null;
  return NoteRecord(
      path: path, text: text, stat: stat, note: note, sidecar: sidecar);
}

/// `profile/creator.json`, `profile/settings.json`, `profile/skill.md`.
class FolderProfile {
  FolderProfile({
    required this.creator,
    required this.settings,
    required this.skill,
    required this.folderName,
  });

  static Future<FolderProfile> read(FolderFs fs,
      {required String folderName}) async {
    Map<String, Object?> obj(String? text) =>
        (text == null ? null : decodeJsonObject(text)) ?? <String, Object?>{};
    return FolderProfile(
      creator: obj(await readTextOrNull(fs, kProfileCreatorPath)),
      settings: obj(await readTextOrNull(fs, kProfileSettingsPath)),
      skill: await readTextOrNull(fs, kProfileSkillPath) ?? '',
      folderName: folderName,
    );
  }

  final Map<String, Object?> creator;
  final Map<String, Object?> settings;
  final String skill;
  final String folderName;

  String field(String key, [String fallback = '']) =>
      jsonString(creator[key]) ?? fallback;

  String get username => field('username', kFolderDefaultUsername);
  String get displayName {
    final name = field('display_name').trim();
    if (name.isNotEmpty) return name;
    final full = '${field('first_name')} ${field('last_name')}'.trim();
    return full.isNotEmpty ? full : username;
  }

  String get editorMode => field('editor_mode', 'P');

  /// `creator_summary_payload`; the folder has one author, id 1.
  Map<String, Object?> get author => {
        'id': 1,
        'username': username,
        'display_name': displayName,
        'image_url': field('image_url'),
        'avatar_url': '',
      };
}

/// `NoteSummarySerializer` for a folder note, from its index entries.
Map<String, Object?> indexedNoteSummary(
    IndexedNote n, CourseLookup courses, Map<String, Object?> author) {
  final slug = n.courseSlug;
  final course = slug == null ? null : courses.bySlug[slug];
  final modified = isoOfMillis(n.body.lastModified);
  final description = n.description;
  return {
    'id': n.id,
    'uuid': n.uuid,
    'name': n.name,
    'git_path': '',
    'module': '',
    'title': n.title,
    'description': description,
    'excerpt': n.excerpt ??
        (description.length <= 220 ? description : description.substring(0, 220)),
    'preview_lines': n.previewLines,
    'editor_mode': n.editorMode,
    'note_type': n.noteType,
    'is_public': n.isPublic,
    'last_edit': n.lastEdit ?? modified,
    'date_created': n.dateCreated ?? n.lastEdit ?? modified,
    'course_id': course?.id,
    'course': course == null
        ? null
        : {'id': course.id, 'title': course.title, 'slug': course.slug},
    'author': author,
    'source_note_uuid': n.sourceNoteUuid,
    'cover_image_url': n.coverImageUrl,
  };
}

/// `NoteSummarySerializer` for a note read from disk.
Map<String, Object?> noteSummary(
        NoteRecord n, CourseLookup courses, Map<String, Object?> author) =>
    indexedNoteSummary(IndexedNote.of(n), courses, author);

/// `NoteDetailSerializer`: the summary plus the body. `blocks` is empty;
/// the apps read `content` first (editor `core/note_crud.dart:615`).
Map<String, Object?> noteDetail(
        NoteRecord n, CourseLookup courses, Map<String, Object?> author) =>
    {
      ...noteSummary(n, courses, author),
      'blocks': const <Object?>[],
      'content': n.note.body,
      'metadata_json': textField(n.sidecar.metadataJson),
      'custom_meta': textField(n.sidecar.customMeta),
    };

/// `CourseSerializer` for a folder course: no subscriptions, media, or git.
Map<String, Object?> coursePayload(CourseRecord c,
        {required List<Map<String, Object?>> recentNotes,
        required Map<String, Object?> owner}) =>
    {
      'id': c.id,
      'client_course_id': c.clientCourseId,
      'slug': c.slug,
      'title': c.title,
      'description': jsonString(c.json['description']) ?? '',
      'cover_image_url': jsonString(c.json['cover_image_url']) ?? '',
      'icon': jsonInt(c.json['icon']),
      'color_hue': jsonInt(c.json['color_hue']),
      'sort_order': c.sortOrder,
      'owner': owner,
      'subscriber_count': 0,
      'is_subscribed': false,
      'is_private_subscription': false,
      'last_opened_at': jsonString(c.json['last_opened_at']),
      'recent_notes': recentNotes,
      'media': const <Object?>[],
      'git': null,
    };

/// Notes newest first by `last_edit`, as the backend's `-last_edit`.
int byLastEditDesc(IndexedNote a, IndexedNote b) =>
    b.lastEditOrModified.compareTo(a.lastEditOrModified);

/// The live notes of the index (and, with [trashed], the trashed ones), as
/// [readNoteAt] accepts them: a body whose sidecar has an id, and a UUID;
/// none at a path of [skip]. In path order, live before trashed.
List<IndexedNote> indexedNotes(FolderIndex index,
    {bool live = true, bool trashed = false, Set<String> skip = const {}}) {
  final out = <IndexedNote>[];
  for (final f in index.files.values) {
    final wanted = f.kind == IndexedKind.note
        ? live
        : (f.kind == IndexedKind.trashNote && trashed);
    if (!wanted) continue;
    final side = index.files[sidecarPathForBody(f.path)];
    if (side == null || side.id == null || (side.uuid ?? f.uuid) == null) {
      continue;
    }
    if (skip.contains(f.path) || skip.contains(side.path)) continue;
    out.add(IndexedNote(f, side));
  }
  return out..sort((a, b) => a.path.compareTo(b.path));
}

/// Course payloads with their five newest notes (`recent_notes`), from the
/// index (P1B-1).
Future<List<Map<String, Object?>>> coursePayloads(LocalHandlerContext ctx,
    List<CourseRecord> courses) async {
  final profile = await FolderProfile.read(ctx.fs, folderName: ctx.folderName);
  final lookup = CourseLookup(courses);
  final notes = indexedNotes(ctx.index, skip: ctx.skipPaths)
    ..sort(byLastEditDesc);
  return [
    for (final c in courses)
      coursePayload(c,
          recentNotes: [
            for (final n in notes.where((n) => n.courseSlug == c.slug).take(5))
              indexedNoteSummary(n, lookup, profile.author),
          ],
          owner: profile.author),
  ];
}

/// `recycle_bin.json`: `{"schema_version": 1, "items": [...]}`, one pointer
/// per trashed note (`id`, `uuid`, `path`, `deleted_at`, `title`).
Future<List<Map<String, Object?>>> readRecycleBin(FolderFs fs) async {
  final text = await readTextOrNull(fs, kRecycleBinPath);
  if (text == null) return [];
  final list = decodeJsonValue(text);
  if (list is Map && list['items'] is List) {
    return [
      for (final item in list['items'] as List)
        if (item is Map) Map<String, Object?>.from(item),
    ];
  }
  return [];
}

String encodeRecycleBin(List<Map<String, Object?>> items) => encodeFolderJson(
    {'schema_version': kFolderSchemaVersion, 'items': items});

/// Typed reads of a request body; a wrong value answers 400 with a 1.8
/// detail naming [consequence] and [process].
class BodyFields {
  BodyFields(this.body, {required this.consequence, required this.process});

  final Map<String, Object?> body;
  final String consequence;
  final String process;

  bool has(String key) => body.containsKey(key);

  LocalHttpError bad(String cause) => LocalHttpError(
      400, LocalFolderMessages.invalidField(consequence, process, cause));

  String? string(String key, {int? maxLength, bool required = false}) {
    final v = body[key];
    if (v == null) {
      if (required) throw bad('$key is required');
      return null;
    }
    if (v is! String) throw bad('$key must be a string');
    if (required && v.trim().isEmpty) throw bad('$key must not be blank');
    if (maxLength != null && v.length > maxLength) {
      throw bad('$key is longer than $maxLength characters');
    }
    return v;
  }

  int? integer(String key) {
    final v = body[key];
    if (v == null || v == '') return null;
    if (v is int) return v;
    if (v is String && int.tryParse(v.trim()) != null) return int.parse(v.trim());
    throw bad('$key must be an integer');
  }

  bool? boolean(String key) {
    final v = body[key];
    if (v == null) return null;
    if (v is bool) return v;
    if (v == 'true' || v == 'True' || v == '1') return true;
    if (v == 'false' || v == 'False' || v == '0') return false;
    throw bad('$key must be true or false');
  }

  String? choice(String key, Set<String> allowed) {
    final v = string(key);
    if (v != null && !allowed.contains(v)) {
      throw bad('$key must be one of ${allowed.join(', ')}');
    }
    return v;
  }
}
