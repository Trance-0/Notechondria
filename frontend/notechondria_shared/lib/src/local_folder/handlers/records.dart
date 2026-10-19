import 'dart:convert';

import '../folder_fs.dart';
import '../folder_journal.dart';
import '../folder_layout.dart';
import '../folder_messages.dart';
import '../note_codec.dart';
import '../router.dart';

// Folder records the Phase 1 handlers share, and the backend payload shapes
// they answer with: NoteSummarySerializer, NoteDetailSerializer,
// CourseSerializer, and creator_summary_payload (backend/notes/api.py).
// Handlers read from disk inside their hold (6.2 R2); the in-memory index
// is never the base of an answer that a write follows.

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

Future<List<NoteRecord>> readNotes(FolderFs fs,
    {bool trashed = false, Set<String> skip = const {}}) async {
  final dir = trashed ? kTrashNotesDir : kNotesDir;
  final out = <NoteRecord>[];
  for (final e in await listOrEmpty(fs, dir)) {
    if (!e.isFile || !e.name.endsWith('.md')) continue;
    final record = await readNoteAt(fs, joinFolderPath(dir, e.name), skip: skip);
    if (record != null) out.add(record);
  }
  return out;
}

/// Live and trashed notes, for lookups that may hit either.
Future<List<NoteRecord>> readAllNotes(FolderFs fs,
        {Set<String> skip = const {}}) async =>
    [
      ...await readNotes(fs, skip: skip),
      ...await readNotes(fs, trashed: true, skip: skip),
    ];

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

/// The backend's `excerpt` (NoteSummarySerializer.get_excerpt).
String noteExcerpt(String content, String description) {
  if (content.isNotEmpty) {
    var lines = content.trim();
    if (lines.startsWith('# ')) {
      final i = lines.indexOf('\n');
      lines = i < 0 ? '' : lines.substring(i + 1).trim();
    }
    return lines.length <= 220 ? lines : lines.substring(0, 220);
  }
  return description.length <= 220 ? description : description.substring(0, 220);
}

/// `note_preview_lines` (backend/notes/services.py:309).
List<String> notePreviewLines(String content, {int limit = 3}) {
  final lines = [
    for (final l in content.split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ];
  if (lines.isNotEmpty && lines.first.startsWith('# ')) lines.removeAt(0);
  return lines.take(limit).toList();
}

/// `NoteSummarySerializer` for a folder note.
Map<String, Object?> noteSummary(
    NoteRecord n, CourseLookup courses, Map<String, Object?> author) {
  final fm = n.frontmatter;
  final course = fm.courseSlug == null ? null : courses.bySlug[fm.courseSlug];
  final modified = isoOfMillis(n.stat.lastModified);
  final description = n.sidecar.description ?? '';
  return {
    'id': n.id,
    'uuid': n.uuid,
    'name': jsonString(n.sidecar.extra['name']) ?? '',
    'git_path': '',
    'module': '',
    'title': fm.title,
    'description': description,
    'excerpt': noteExcerpt(n.note.body, description),
    'preview_lines': notePreviewLines(n.note.body),
    'editor_mode': fm.editorMode,
    'note_type': jsonString(n.sidecar.noteType) ?? 'N',
    'is_public': fm.isPublic,
    'last_edit': fm.lastEdit ?? modified,
    'date_created': fm.dateCreated ?? fm.lastEdit ?? modified,
    'course_id': course?.id,
    'course': course == null
        ? null
        : {'id': course.id, 'title': course.title, 'slug': course.slug},
    'author': author,
    'source_note_uuid': n.sidecar.sourceNoteUuid,
    'cover_image_url': n.sidecar.coverImageUrl,
  };
}

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
int byLastEditDesc(NoteRecord a, NoteRecord b) {
  final ea = a.frontmatter.lastEdit ?? isoOfMillis(a.stat.lastModified);
  final eb = b.frontmatter.lastEdit ?? isoOfMillis(b.stat.lastModified);
  return eb.compareTo(ea);
}

/// Course payloads with their five newest notes (`recent_notes`).
Future<List<Map<String, Object?>>> coursePayloads(LocalHandlerContext ctx,
    List<CourseRecord> courses) async {
  final profile = await FolderProfile.read(ctx.fs, folderName: ctx.folderName);
  final lookup = CourseLookup(courses);
  final notes = await readNotes(ctx.fs, skip: ctx.skipPaths)
    ..sort(byLastEditDesc);
  return [
    for (final c in courses)
      coursePayload(c,
          recentNotes: [
            for (final n
                in notes.where((n) => n.frontmatter.courseSlug == c.slug).take(5))
              noteSummary(n, lookup, profile.author),
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
