import 'dart:math';

import 'folder_fs.dart';
import 'folder_layout.dart';

// Journal record format and op ids (storage rules 3.4.1 step 2).

/// Size and `lastModified` of a note body as the operation read it (N15).
class JournalExpect {
  const JournalExpect({required this.size, required this.lastModified});

  factory JournalExpect.of(FolderStat stat) =>
      JournalExpect(size: stat.size, lastModified: stat.lastModified);

  final int size;
  final int lastModified;

  Map<String, Object?> toJson() => {'size': size, 'lastModified': lastModified};

  static JournalExpect? fromJson(Object? json) {
    if (json is! Map) return null;
    final size = json['size'];
    final lastModified = json['lastModified'];
    if (size is! int || lastModified is! int) return null;
    return JournalExpect(size: size, lastModified: lastModified);
  }
}

class JournalWrite {
  const JournalWrite(this.path, this.text, {this.expect});

  final String path;

  /// Full new text of the file.
  final String text;

  /// Only for note bodies (`notes/*.md`, `trash/notes/*.md`) that existed.
  final JournalExpect? expect;
}

class JournalRemoval {
  const JournalRemoval(this.path, {this.expect, this.directory = false});

  final String path;
  final JournalExpect? expect;

  /// Removed with `removeEntry(name, {recursive: true})`, after every file.
  final bool directory;
}

/// `.notechondria/journal/<op-id>.json`.
class JournalRecord {
  const JournalRecord({
    required this.opId,
    required this.app,
    required this.createdAt,
    required this.writes,
    this.removals = const [],
  });

  factory JournalRecord.fromJson(Map<String, Object?> json) => JournalRecord(
        opId: json['op_id'] as String,
        app: (json['app'] as String?) ?? '',
        createdAt: (json['created_at'] as String?) ?? '',
        writes: [
          for (final w in (json['writes'] as List?) ?? const [])
            if (w is Map)
              JournalWrite(w['path'] as String, w['text'] as String,
                  expect: JournalExpect.fromJson(w['expect'])),
        ],
        removals: [
          for (final r in (json['removals'] as List?) ?? const [])
            if (r is Map)
              JournalRemoval(r['path'] as String,
                  expect: JournalExpect.fromJson(r['expect']),
                  directory: r['directory'] == true),
        ],
      );

  final String opId;
  final String app;
  final String createdAt;
  final List<JournalWrite> writes;
  final List<JournalRemoval> removals;

  String get path => '$kJournalDir/$opId.json';

  Set<String> get touchedPaths => {
        for (final w in writes) w.path,
        for (final r in removals) r.path,
      };

  Map<String, Object?> toJson() => {
        'schema_version': kFolderSchemaVersion,
        'op_id': opId,
        'app': app,
        'created_at': createdAt,
        'writes': [
          for (final w in writes)
            {
              'path': w.path,
              'text': w.text,
              if (w.expect != null) 'expect': w.expect!.toJson(),
            },
        ],
        'removals': [
          for (final r in removals)
            {
              'path': r.path,
              if (r.expect != null) 'expect': r.expect!.toJson(),
              if (r.directory) 'directory': true,
            },
        ],
      };
}

/// `<UTC ms, 13 digits>-<4-digit per-tab sequence>-<8 random hex>`, so
/// lexical order is creation order.
class JournalOpIds {
  JournalOpIds({Random? random}) : _random = random ?? Random.secure();

  final Random _random;
  int _sequence = 0;

  String next(DateTime now) {
    final ms = now.toUtc().millisecondsSinceEpoch.toString().padLeft(13, '0');
    final seq = (_sequence++ % 10000).toString().padLeft(4, '0');
    final hex = List.generate(4, (_) => _random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '$ms-$seq-$hex';
  }
}
