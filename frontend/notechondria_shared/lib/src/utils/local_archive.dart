import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Current `.nchron` package format version. Bumped only for
/// incompatible layout changes; additive changes (extra optional
/// files, new keys inside existing objects) keep this at 1.
const int kLocalArchivePackageVersion = 1;

/// Which frontend app produced or is consuming an archive. Used by
/// the importer to decide which optional files to expect and to
/// label exports.
enum LocalArchiveApp { editor, planner, portal }

extension LocalArchiveAppTag on LocalArchiveApp {
  String get tag {
    switch (this) {
      case LocalArchiveApp.editor:
        return 'editor';
      case LocalArchiveApp.planner:
        return 'planner';
      case LocalArchiveApp.portal:
        return 'portal';
    }
  }

  static LocalArchiveApp? fromTag(String value) {
    switch (value) {
      case 'editor':
        return LocalArchiveApp.editor;
      case 'planner':
        return LocalArchiveApp.planner;
      case 'portal':
        return LocalArchiveApp.portal;
    }
    return null;
  }
}

/// Strongly-typed payload an app hands the shared archive writer.
/// Only the first four buckets are mandatory; the app-specific ones
/// default to sensible empties for apps that don't use them.
class LocalArchiveInput {
  LocalArchiveInput({
    required this.app,
    required this.appVersion,
    required this.profile,
    required this.settings,
    required this.localSettings,
    required this.stats,
    required this.cache,
    required this.courses,
    required this.drafts,
    required this.logs,
    this.plannerEvents = const <Map<String, dynamic>>[],
    this.calendarFeeds = const <Map<String, dynamic>>[],
    this.activityWeek = const <String, dynamic>{},
    this.frontPage = const <String, dynamic>{},
  });

  final LocalArchiveApp app;

  /// App's semver from `VERSION`, e.g. `"0.1.38"`. Diagnostic only.
  final String appVersion;

  /// Read-only profile fields. Tokens and API key prefixes must be
  /// stripped by the caller before handing to this constructor.
  final Map<String, dynamic> profile;

  final Map<String, dynamic> settings;
  final Map<String, dynamic> localSettings;
  final Map<String, dynamic> stats;
  final Map<String, dynamic> cache;
  final List<Map<String, dynamic>> courses;
  final List<Map<String, dynamic>> drafts;
  final List<String> logs;
  final List<Map<String, dynamic>> plannerEvents;
  final List<Map<String, dynamic>> calendarFeeds;
  final Map<String, dynamic> activityWeek;
  final Map<String, dynamic> frontPage;
}

/// Everything the caller gets back from reading an archive. A zero
/// `packageVersion` signals a failed parse; check [errorMessage] for
/// the §1.7-shaped cause before using any other field.
class LocalArchiveOutput {
  LocalArchiveOutput({
    required this.packageVersion,
    required this.manifestApp,
    required this.manifestAppVersion,
    required this.exportedAt,
    required this.counts,
    required this.profile,
    required this.settings,
    required this.localSettings,
    required this.stats,
    required this.cache,
    required this.courses,
    required this.drafts,
    required this.logs,
    required this.plannerEvents,
    required this.calendarFeeds,
    required this.activityWeek,
    required this.frontPage,
    this.errorMessage,
  });

  final int packageVersion;
  final LocalArchiveApp? manifestApp;
  final String manifestAppVersion;
  final DateTime? exportedAt;
  final Map<String, int> counts;
  final Map<String, dynamic> profile;
  final Map<String, dynamic> settings;
  final Map<String, dynamic> localSettings;
  final Map<String, dynamic> stats;
  final Map<String, dynamic> cache;
  final List<Map<String, dynamic>> courses;
  final List<Map<String, dynamic>> drafts;
  final List<String> logs;
  final List<Map<String, dynamic>> plannerEvents;
  final List<Map<String, dynamic>> calendarFeeds;
  final Map<String, dynamic> activityWeek;
  final Map<String, dynamic> frontPage;
  final String? errorMessage;

  bool get ok => errorMessage == null;
}

/// Serializes a [LocalArchiveInput] into a `.nchron` ZIP byte
/// payload. Promotes any `queued_attachments` `bytes_base64` fields
/// inside drafts to real files under `attachments/<draft-client-id>/`
/// and rewrites the draft entry to carry a `path` pointer instead.
Uint8List writeLocalArchive(LocalArchiveInput input) {
  final archive = Archive();

  // VERSION + manifest.
  _addFile(archive, 'VERSION', '$kLocalArchivePackageVersion');

  // Walk drafts once, promoting queued attachments out to real
  // archive entries and rewriting metadata_json on the way.
  final rewrittenDrafts = <Map<String, dynamic>>[];
  var queuedCount = 0;
  for (final draft in input.drafts) {
    final metadataRaw = draft['metadata_json']?.toString() ?? '{}';
    Map<String, dynamic> metadata;
    try {
      final decoded = jsonDecode(metadataRaw);
      metadata = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      metadata = <String, dynamic>{};
    }
    final queued = List<Map<String, dynamic>>.from(
      (metadata['queued_attachments'] as List?) ?? const [],
    );
    if (queued.isEmpty) {
      rewrittenDrafts.add(Map<String, dynamic>.from(draft));
      continue;
    }
    final draftClientId =
        (draft['client_draft_id'] ?? draft['id'] ?? 'draft').toString();
    final safeDraftId = _sanitize(draftClientId);
    final usedNames = <String>{};
    final rewrittenQueued = <Map<String, dynamic>>[];
    for (var i = 0; i < queued.length; i++) {
      final entry = Map<String, dynamic>.from(queued[i]);
      final filename =
          _sanitize((entry['filename'] ?? 'attachment-$i').toString());
      final base64Str = entry['bytes_base64']?.toString() ?? '';
      if (base64Str.isEmpty) {
        rewrittenQueued.add(entry);
        continue;
      }
      var resolved = filename;
      if (usedNames.contains(resolved)) {
        resolved = '${filename}__$i';
      }
      usedNames.add(resolved);
      final archivePath = 'attachments/$safeDraftId/$resolved';
      try {
        final bytes = base64Decode(base64Str);
        archive.addFile(
          ArchiveFile(archivePath, bytes.length, bytes),
        );
        entry.remove('bytes_base64');
        entry['path'] = archivePath;
        queuedCount++;
      } catch (_) {
        // Keep the bytes_base64 in place if it can't be decoded so
        // the importer at least has something to try.
      }
      rewrittenQueued.add(entry);
    }
    metadata['queued_attachments'] = rewrittenQueued;
    rewrittenDrafts.add({
      ...draft,
      'metadata_json': jsonEncode(metadata),
    });
  }

  final manifest = <String, dynamic>{
    'app': input.app.tag,
    'exported_at': DateTime.now().toUtc().toIso8601String(),
    'app_version': input.appVersion,
    'package_version': '$kLocalArchivePackageVersion',
    'counts': <String, int>{
      'drafts': rewrittenDrafts.length,
      'courses': input.courses.length,
      'logs': input.logs.length,
      'planner_events': input.plannerEvents.length,
      'calendar_feeds': input.calendarFeeds.length,
      'queued_attachments': queuedCount,
    },
    'profile': input.profile,
  };

  _addFile(archive, 'manifest.json', jsonEncode(manifest));
  _addFile(archive, 'settings.json', jsonEncode(input.settings));
  _addFile(archive, 'local_settings.json', jsonEncode(input.localSettings));
  _addFile(archive, 'stats.json', jsonEncode(input.stats));
  _addFile(archive, 'cache.json', jsonEncode(input.cache));
  _addFile(archive, 'courses.json', jsonEncode(input.courses));
  _addFile(archive, 'drafts.json', jsonEncode(rewrittenDrafts));
  _addFile(archive, 'logs.json', jsonEncode(input.logs));

  // Optional app-specific files. Always emit when the caller has
  // non-empty data so a planner export carries its events regardless
  // of which app imports it later.
  if (input.plannerEvents.isNotEmpty ||
      input.app == LocalArchiveApp.planner) {
    _addFile(archive, 'planner_events.json',
        jsonEncode(input.plannerEvents));
  }
  if (input.calendarFeeds.isNotEmpty ||
      input.app == LocalArchiveApp.planner) {
    _addFile(archive, 'calendar_feeds.json',
        jsonEncode(input.calendarFeeds));
  }
  if (input.activityWeek.isNotEmpty ||
      input.app == LocalArchiveApp.planner) {
    _addFile(archive, 'activity_week.json',
        jsonEncode(input.activityWeek));
  }
  if (input.frontPage.isNotEmpty ||
      input.app == LocalArchiveApp.portal) {
    _addFile(archive, 'front_page.json', jsonEncode(input.frontPage));
  }

  return Uint8List.fromList(ZipEncoder().encode(archive) ?? const []);
}

/// Parses a `.nchron` ZIP payload. Returns a [LocalArchiveOutput]
/// with a non-null `errorMessage` on failure; inspects [ok] before
/// reading the bucket fields.
///
/// The caller is responsible for choosing whether to delete the
/// existing local state before applying the parsed data — this
/// function does not touch `_LocalAppStore`.
LocalArchiveOutput readLocalArchive(Uint8List bytes) {
  if (bytes.isEmpty) {
    return _errorOutput(
      'Archive rejected: Shared.LocalArchive/read \u2014 '
      'file is empty.',
    );
  }

  Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (error) {
    return _errorOutput(
      'Archive rejected: Shared.LocalArchive/read \u2014 '
      'not a readable ZIP file ($error).',
    );
  }

  final files = {
    for (final f in archive.files) f.name: f,
  };

  final versionFile = files['VERSION'];
  if (versionFile == null) {
    return _errorOutput(
      'Archive rejected: Shared.LocalArchive/read \u2014 '
      'no VERSION file at archive root (expected "1").',
    );
  }
  final versionStr =
      utf8.decode(versionFile.content as List<int>).trim();
  final parsedVersion = int.tryParse(versionStr);
  if (parsedVersion == null) {
    return _errorOutput(
      'Archive rejected: Shared.LocalArchive/read \u2014 '
      'VERSION file contains non-numeric token "$versionStr".',
    );
  }
  if (parsedVersion > kLocalArchivePackageVersion) {
    return _errorOutput(
      'Archive rejected: Shared.LocalArchive/read \u2014 '
      'package format version $parsedVersion is ahead of this '
      "build's supported version $kLocalArchivePackageVersion.",
    );
  }

  final manifestRaw = _readJson(files['manifest.json']);
  final manifest = manifestRaw is Map
      ? Map<String, dynamic>.from(manifestRaw)
      : <String, dynamic>{};
  final manifestApp =
      LocalArchiveAppTag.fromTag(manifest['app']?.toString() ?? '');
  final appVersion = manifest['app_version']?.toString() ?? '';
  DateTime? exportedAt;
  final exportedAtStr = manifest['exported_at']?.toString();
  if (exportedAtStr != null) {
    try {
      exportedAt = DateTime.parse(exportedAtStr).toUtc();
    } catch (_) {}
  }
  final counts = <String, int>{
    for (final entry
        in (manifest['counts'] as Map?)?.entries ?? const <MapEntry>[])
      entry.key.toString(): (entry.value as num?)?.toInt() ?? 0,
  };
  final profile = manifest['profile'] is Map
      ? Map<String, dynamic>.from(manifest['profile'] as Map)
      : <String, dynamic>{};

  // Read drafts and rehydrate any archived queued attachments back
  // into their base64 form so the host's existing sync path promotes
  // them without any special-case code.
  final drafts = (_readJson(files['drafts.json']) as List?) ?? const [];
  final rehydratedDrafts = <Map<String, dynamic>>[];
  for (final raw in drafts) {
    if (raw is! Map) continue;
    final draft = Map<String, dynamic>.from(raw);
    final metadataRaw = draft['metadata_json']?.toString() ?? '{}';
    Map<String, dynamic> metadata;
    try {
      final decoded = jsonDecode(metadataRaw);
      metadata = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      metadata = <String, dynamic>{};
    }
    final queued = List<Map<String, dynamic>>.from(
      (metadata['queued_attachments'] as List?) ?? const [],
    );
    if (queued.isEmpty) {
      rehydratedDrafts.add(draft);
      continue;
    }
    final rehydratedQueued = <Map<String, dynamic>>[];
    for (final entry in queued) {
      final path = entry['path']?.toString() ?? '';
      if (path.isEmpty) {
        rehydratedQueued.add(Map<String, dynamic>.from(entry));
        continue;
      }
      final file = files[path];
      if (file == null) {
        // Silently drop entries whose binary is missing; the draft
        // still imports without the attachment.
        continue;
      }
      final rebuilt = Map<String, dynamic>.from(entry);
      rebuilt.remove('path');
      rebuilt['bytes_base64'] =
          base64Encode(file.content as List<int>);
      rehydratedQueued.add(rebuilt);
    }
    metadata['queued_attachments'] = rehydratedQueued;
    draft['metadata_json'] = jsonEncode(metadata);
    rehydratedDrafts.add(draft);
  }

  return LocalArchiveOutput(
    packageVersion: parsedVersion,
    manifestApp: manifestApp,
    manifestAppVersion: appVersion,
    exportedAt: exportedAt,
    counts: counts,
    profile: profile,
    settings: _readJsonMap(files['settings.json']),
    localSettings: _readJsonMap(files['local_settings.json']),
    stats: _readJsonMap(files['stats.json']),
    cache: _readJsonMap(files['cache.json']),
    courses: _readJsonList(files['courses.json']),
    drafts: rehydratedDrafts,
    logs: _readStringList(files['logs.json']),
    plannerEvents: _readJsonList(files['planner_events.json']),
    calendarFeeds: _readJsonList(files['calendar_feeds.json']),
    activityWeek: _readJsonMap(files['activity_week.json']),
    frontPage: _readJsonMap(files['front_page.json']),
  );
}

/// Detects whether the provided payload looks like a legacy
/// `.env`-style config file produced by Notechondria builds before
/// 0.1.38. Returns the parsed key/value map when recognized;
/// otherwise null.
Map<String, String>? tryReadLegacyEnvConfig(Uint8List bytes) {
  if (bytes.isEmpty) return null;
  // ZIP magic bytes start with 0x50 0x4B (PK). A legacy .env starts
  // with text; short-circuit on the common ZIP prefix.
  if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
    return null;
  }
  String text;
  try {
    text = utf8.decode(bytes, allowMalformed: true);
  } catch (_) {
    return null;
  }
  final out = <String, String>{};
  final lineRe = RegExp(r'^\s*([A-Z0-9_]+)\s*=\s*(.*)$', multiLine: true);
  for (final match in lineRe.allMatches(text)) {
    final key = match.group(1)!;
    final value = match.group(2)!.trim();
    out[key] = value;
  }
  if (out.isEmpty) return null;
  // At minimum a legacy file carries API_BASE_URL or API_KEY_PREFIX.
  if (!(out.containsKey('API_BASE_URL') ||
      out.containsKey('API_KEY_PREFIX'))) {
    return null;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

void _addFile(Archive archive, String name, String body) {
  final bytes = utf8.encode(body);
  archive.addFile(ArchiveFile(name, bytes.length, bytes));
}

dynamic _readJson(ArchiveFile? file) {
  if (file == null) return null;
  try {
    return jsonDecode(utf8.decode(file.content as List<int>));
  } catch (_) {
    return null;
  }
}

Map<String, dynamic> _readJsonMap(ArchiveFile? file) {
  final decoded = _readJson(file);
  if (decoded is Map) return Map<String, dynamic>.from(decoded);
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _readJsonList(ArchiveFile? file) {
  final decoded = _readJson(file);
  if (decoded is! List) return const <Map<String, dynamic>>[];
  return decoded
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

List<String> _readStringList(ArchiveFile? file) {
  final decoded = _readJson(file);
  if (decoded is! List) return const <String>[];
  return decoded.map((item) => item.toString()).toList(growable: false);
}

LocalArchiveOutput _errorOutput(String message) {
  return LocalArchiveOutput(
    packageVersion: 0,
    manifestApp: null,
    manifestAppVersion: '',
    exportedAt: null,
    counts: const {},
    profile: const {},
    settings: const {},
    localSettings: const {},
    stats: const {},
    cache: const {},
    courses: const [],
    drafts: const [],
    logs: const [],
    plannerEvents: const [],
    calendarFeeds: const [],
    activityWeek: const {},
    frontPage: const {},
    errorMessage: message,
  );
}

String _sanitize(String raw) {
  final buf = StringBuffer();
  for (final codeUnit in raw.runes) {
    if (codeUnit < 0x20) continue;
    final ch = String.fromCharCode(codeUnit);
    if (ch == '/' || ch == '\\' || ch == '\u0000') {
      buf.write('_');
    } else {
      buf.write(ch);
    }
  }
  final cleaned = buf.toString().trim();
  if (cleaned.isEmpty) return 'untitled';
  if (cleaned.length > 200) return cleaned.substring(0, 200);
  return cleaned;
}
