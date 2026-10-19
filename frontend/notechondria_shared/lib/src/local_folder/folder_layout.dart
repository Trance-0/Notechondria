import 'dart:convert';
import 'dart:math';

import 'folder_fs.dart';
import 'folder_messages.dart';

// Folder tree (main 3.1) and file formats (main 3.2).

const String kFolderFormat = 'notechondria-folder';
const int kFolderLayoutVersion = 1;
const int kFolderSchemaVersion = 1;
const int kGithubSyncSchemaVersion = 1;

const String kManifestPath = 'manifest.json';
const String kReadmePath = 'README.md';
const String kNotesDir = 'notes';
const String kTrashNotesDir = 'trash/notes';
const String kCoursesDir = 'courses';
const String kPlannerDir = 'planner';
const String kHistoryDir = 'history';
const String kAssetsDir = 'assets';
const String kProfileDir = 'profile';
const String kRecycleBinPath = 'recycle_bin.json';
const String kPlannerEventsPath = 'planner/events.json';
const String kPlannerFeedsPath = 'planner/feeds.json';
const String kPlannerSessionsPath = 'planner/sessions.json';
const String kPlannerHeatmapPath = 'planner/heatmap.json';
const String kAppDataDir = '.notechondria';
const String kIndexPath = '.notechondria/index.json';
const String kImportProgressPath = '.notechondria/import.json';
const String kJournalDir = '.notechondria/journal';

/// ID kinds held in `manifest.json.id_counters` (3.7).
const List<String> kIdKinds = <String>[
  'course',
  'note',
  'version',
  'session',
  'event',
  'feed',
  'attachment',
];

bool isNoteBodyPath(String path) =>
    path.endsWith('.md') &&
    !path.endsWith('.meta.json') &&
    (folderPathParent(path) == kNotesDir ||
        folderPathParent(path) == kTrashNotesDir);

bool isSidecarPath(String path) =>
    path.endsWith('.meta.json') &&
    (folderPathParent(path) == kNotesDir ||
        folderPathParent(path) == kTrashNotesDir);

/// `notes/<stem>.md` -> `<stem>`.
String noteStemOf(String mdPath) {
  final base = folderPathBasename(mdPath);
  return base.endsWith('.md') ? base.substring(0, base.length - 3) : base;
}

String noteBodyPath(String stem, {bool trashed = false}) =>
    '${trashed ? kTrashNotesDir : kNotesDir}/$stem.md';

String sidecarPathForBody(String mdPath) =>
    '${mdPath.substring(0, mdPath.length - 3)}.meta.json';

String bodyPathForSidecar(String sidecarPath) =>
    '${sidecarPath.substring(0, sidecarPath.length - '.meta.json'.length)}.md';

String historyIndexPath(String uuidHex) => '$kHistoryDir/$uuidHex/index.json';

String historyBodyPath(String uuidHex, int versionId) =>
    '$kHistoryDir/$uuidHex/$versionId.md';

String attachmentsIndexPath(String uuidHex) =>
    '$kAssetsDir/notes/$uuidHex/attachments.json';

/// Thrown when `manifest.json` cannot be used; [message] is a 1.8 string.
class FolderLayoutException implements Exception {
  const FolderLayoutException(this.message, {this.newerLayout});

  final String message;

  /// The manifest's `layout_version` when it is newer than this build.
  final int? newerLayout;

  @override
  String toString() => message;
}

/// `manifest.json` (3.2). Unknown keys are kept in [extra] and written back.
class FolderManifest {
  FolderManifest({
    required this.folderId,
    required this.createdAt,
    required this.createdByAppVersion,
    required Map<String, int> idCounters,
    this.layoutVersion = kFolderLayoutVersion,
    this.githubSyncSchemaVersion = kGithubSyncSchemaVersion,
    this.restoredFromFolderId,
    Map<String, Object?>? extra,
  })  : idCounters = Map<String, int>.unmodifiable(idCounters),
        extra = Map<String, Object?>.unmodifiable(extra ?? const {});

  factory FolderManifest.create({
    required String folderId,
    required String appVersion,
    required DateTime now,
  }) =>
      FolderManifest(
        folderId: folderId,
        createdAt: now.toUtc().toIso8601String(),
        createdByAppVersion: appVersion,
        idCounters: {for (final kind in kIdKinds) kind: 0},
      );

  /// Validates and decodes; throws [FolderLayoutException].
  factory FolderManifest.fromJson(Map<String, Object?> json) {
    if (json['format'] != kFolderFormat) {
      throw FolderLayoutException(LocalFolderMessages.manifestInvalid(
          'format is ${jsonEncode(json['format'])}, not "$kFolderFormat"'));
    }
    final layout = json['layout_version'];
    if (layout is! int || layout < 1) {
      throw FolderLayoutException(LocalFolderMessages.manifestInvalid(
          'layout_version is ${jsonEncode(layout)}'));
    }
    if (layout > kFolderLayoutVersion) {
      throw FolderLayoutException(
          LocalFolderMessages.layoutTooNew(layout, kFolderLayoutVersion),
          newerLayout: layout);
    }
    final folderId = json['folder_id'];
    if (folderId is! String || folderId.isEmpty) {
      throw FolderLayoutException(
          LocalFolderMessages.manifestInvalid('folder_id is missing'));
    }
    final counters = <String, int>{for (final kind in kIdKinds) kind: 0};
    final rawCounters = json['id_counters'];
    if (rawCounters is Map) {
      rawCounters.forEach((key, value) {
        if (key is String && value is int && value >= 0) {
          counters[key] = value;
        }
      });
    }
    const known = {
      'format',
      'layout_version',
      'folder_id',
      'created_at',
      'created_by_app_version',
      'id_counters',
      'github_sync_schema_version',
      'restored_from_folder_id',
    };
    return FolderManifest(
      folderId: folderId,
      layoutVersion: layout,
      createdAt: '${json['created_at'] ?? ''}',
      createdByAppVersion: '${json['created_by_app_version'] ?? ''}',
      idCounters: counters,
      githubSyncSchemaVersion:
          (json['github_sync_schema_version'] as int?) ?? 1,
      restoredFromFolderId: json['restored_from_folder_id'] as String?,
      extra: {
        for (final e in json.entries)
          if (!known.contains(e.key)) e.key: e.value,
      },
    );
  }

  final String folderId;
  final int layoutVersion;
  final String createdAt;
  final String createdByAppVersion;

  /// Last ID issued per kind (0 before the first).
  final Map<String, int> idCounters;
  final int githubSyncSchemaVersion;
  final String? restoredFromFolderId;
  final Map<String, Object?> extra;

  int counter(String kind) => idCounters[kind] ?? 0;

  Map<String, Object?> toJson() => {
        ...extra,
        'format': kFolderFormat,
        'layout_version': layoutVersion,
        'folder_id': folderId,
        'created_at': createdAt,
        'created_by_app_version': createdByAppVersion,
        'id_counters': idCounters,
        'github_sync_schema_version': githubSyncSchemaVersion,
        if (restoredFromFolderId != null)
          'restored_from_folder_id': restoredFromFolderId,
      };

  String encode() => encodeFolderJson(toJson());

  FolderManifest _withCounters(Map<String, int> counters) => FolderManifest(
        folderId: folderId,
        layoutVersion: layoutVersion,
        createdAt: createdAt,
        createdByAppVersion: createdByAppVersion,
        idCounters: counters,
        githubSyncSchemaVersion: githubSyncSchemaVersion,
        restoredFromFolderId: restoredFromFolderId,
        extra: extra,
      );

  /// Issues the next ID of [kind]; returns the updated manifest and the ID.
  (FolderManifest, int) allocate(String kind) {
    final next = counter(kind) + 1;
    return (_withCounters({...idCounters, kind: next}), next);
  }

  /// Raises each counter to at least [floor] (3.7); null if none was lower.
  FolderManifest? raisedTo(Map<String, int> floor) {
    final raised = Map<String, int>.of(idCounters);
    var changed = false;
    floor.forEach((kind, value) {
      if (value > (raised[kind] ?? 0)) {
        raised[kind] = value;
        changed = true;
      }
    });
    return changed ? _withCounters(raised) : null;
  }

  FolderManifest withFolderId(String id, {String? restoredFrom}) =>
      FolderManifest(
        folderId: id,
        layoutVersion: layoutVersion,
        createdAt: createdAt,
        createdByAppVersion: createdByAppVersion,
        idCounters: idCounters,
        githubSyncSchemaVersion: githubSyncSchemaVersion,
        restoredFromFolderId: restoredFrom ?? restoredFromFolderId,
        extra: extra,
      );
}

/// Decodes `manifest.json` text; throws [FolderLayoutException].
FolderManifest decodeFolderManifest(String text) {
  final json = decodeJsonObject(text);
  if (json == null) {
    throw FolderLayoutException(
        LocalFolderMessages.manifestInvalid('it is not a JSON object'));
  }
  return FolderManifest.fromJson(json);
}

/// Reads `manifest.json`; null when the folder has none.
Future<FolderManifest?> readFolderManifest(FolderFs fs) async {
  final text = await readTextOrNull(fs, kManifestPath);
  return text == null ? null : decodeFolderManifest(text);
}

/// JSON as the folder writes it: sorted keys (like `github_sync._safe_json`),
/// two-space indent, trailing newline.
String encodeFolderJson(Object? value) =>
    '${const JsonEncoder.withIndent('  ').convert(_sortKeys(value))}\n';

Object? _sortKeys(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => '$k').toList()..sort();
    return {for (final k in keys) k: _sortKeys(value[k])};
  }
  if (value is List) return value.map(_sortKeys).toList();
  return value;
}

/// Decodes any JSON value; null when [text] is not valid JSON.
Object? decodeJsonValue(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

/// Decodes a JSON object; null when [text] is not valid JSON or not an object.
Map<String, Object?>? decodeJsonObject(String text) {
  final decoded = decodeJsonValue(text);
  return decoded is Map ? Map<String, Object?>.from(decoded) : null;
}

final Random _secureRandom = Random.secure();

/// A version-4 UUID from `Random.secure()` (3.7).
String newUuidV4([Random? random]) {
  final r = random ?? _secureRandom;
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false);
final RegExp _hexPattern = RegExp(r'^[0-9a-f]{32}$', caseSensitive: false);

bool isUuid(String? value) => value != null && _uuidPattern.hasMatch(value);

/// `<uuid>` without dashes, lower case (the `<note-uuid-hex>` of 3.1).
String uuidHex(String uuid) => uuid.replaceAll('-', '').toLowerCase();

/// The UUID a 32-hex stem spells, or null.
String? uuidFromHex(String hex) {
  if (!_hexPattern.hasMatch(hex)) return null;
  final h = hex.toLowerCase();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

const String kFolderReadmeText = '''
# Notechondria folder

This folder holds Notechondria data as plain files: notes are Markdown
files under `notes/` with a `.meta.json` sidecar each, and everything else
is JSON. `manifest.json` identifies the folder; do not delete it.
`.notechondria/` holds a cache and unfinished-change records; leave it in
place while the app is open.
''';

/// Files that turn an empty folder into a Notechondria folder, in write
/// order: `manifest.json` comes last (6.2 R4).
List<({String path, String text})> initialFolderFiles({
  required String folderId,
  required String appVersion,
  required DateTime now,
}) =>
    [
      (path: kReadmePath, text: kFolderReadmeText),
      (
        path: kManifestPath,
        text: FolderManifest.create(
                folderId: folderId, appVersion: appVersion, now: now)
            .encode(),
      ),
    ];
