import 'folder_fs.dart';
import 'folder_layout.dart';

// Note `.md` frontmatter, the `.meta.json` sidecar, and attachment link
// rewriting (main 3.1, 3.2, 3.6).

/// The `nc-folder:` URL prefix the app uses for folder files (3.6).
const String kFolderUrlPrefix = 'nc-folder:///';

/// Frontmatter keys in the order `github_sync._note_files` writes them.
const List<String> kFrontmatterKeys = <String>[
  'title',
  'uuid',
  'course_slug',
  'is_public',
  'editor_mode',
  'last_edit',
  'date_created',
];

/// System frontmatter of a note. On read only [title], [courseSlug],
/// [isPublic], and the body are authoritative; the rest is regenerated.
class NoteFrontmatter {
  const NoteFrontmatter({
    required this.title,
    this.uuid,
    this.courseSlug,
    this.isPublic = false,
    this.editorMode = 'P',
    this.lastEdit,
    this.dateCreated,
  });

  final String title;
  final String? uuid;
  final String? courseSlug;
  final bool isPublic;
  final String editorMode;
  final String? lastEdit;
  final String? dateCreated;

  NoteFrontmatter copyWith({String? uuid, bool? isPublic, String? title}) =>
      NoteFrontmatter(
        title: title ?? this.title,
        uuid: uuid ?? this.uuid,
        courseSlug: courseSlug,
        isPublic: isPublic ?? this.isPublic,
        editorMode: editorMode,
        lastEdit: lastEdit,
        dateCreated: dateCreated,
      );

  Map<String, Object?> _values() => {
        'title': title,
        'uuid': uuid,
        'course_slug': courseSlug,
        'is_public': isPublic,
        'editor_mode': editorMode,
        'last_edit': lastEdit,
        'date_created': dateCreated,
      };
}

/// A decoded note file. [body] is in app form (`nc-folder:` links).
class DecodedNote {
  const DecodedNote({
    required this.frontmatter,
    required this.body,
    required this.hasFrontmatter,
    this.rawFrontmatter = const {},
  });

  final NoteFrontmatter frontmatter;
  final String body;
  final bool hasFrontmatter;

  /// Every frontmatter key as read, including custom keys `github_sync`
  /// spreads after the system keys. Not written back (3.2).
  final Map<String, Object?> rawFrontmatter;
}

/// Encodes a note file: the `github_sync` quoted-scalar frontmatter, a blank
/// line, the body with links rewritten to disk form, and a trailing newline.
String encodeNoteFile(NoteFrontmatter frontmatter, String appBody,
    {required String path}) {
  final lines = <String>['---'];
  frontmatter._values().forEach((key, value) {
    if (value == null) {
      lines.add('$key: null');
    } else if (value is bool) {
      lines.add('$key: ${value ? 'true' : 'false'}');
    } else {
      final escaped = '$value'
          .replaceAll('\r\n', ' ')
          .replaceAll('\n', ' ')
          .replaceAll('\\', r'\\')
          .replaceAll('"', r'\"');
      lines.add('$key: "$escaped"');
    }
  });
  lines.add('---');
  return '${lines.join('\n')}\n\n${rewriteLinksToDisk(appBody, path: path)}\n';
}

/// Decodes a note file. A file without frontmatter is a hand-added note:
/// the whole text is the body and the title is its first `#` heading or
/// the file stem.
DecodedNote decodeNoteFile(String text, {required String path}) {
  final parsed = _splitFrontmatter(text);
  if (parsed == null) {
    return DecodedNote(
      frontmatter: NoteFrontmatter(title: _fallbackTitle(text, path)),
      body: rewriteLinksToApp(text, path: path),
      hasFrontmatter: false,
    );
  }
  final raw = parsed.values;
  String? str(String key) {
    final v = raw[key];
    return v == null ? null : '$v';
  }

  final isPublic = raw['is_public'];
  final title = str('title');
  return DecodedNote(
    frontmatter: NoteFrontmatter(
      title: (title == null || title.isEmpty)
          ? _fallbackTitle(parsed.body, path)
          : title,
      uuid: isUuid(str('uuid')) ? str('uuid')!.toLowerCase() : null,
      courseSlug: (str('course_slug')?.isEmpty ?? true) ? null : str('course_slug'),
      isPublic: isPublic == true || isPublic == 'true',
      editorMode: str('editor_mode') ?? 'P',
      lastEdit: str('last_edit'),
      dateCreated: str('date_created'),
    ),
    body: rewriteLinksToApp(parsed.body, path: path),
    hasFrontmatter: true,
    rawFrontmatter: raw,
  );
}

/// The frontmatter `uuid` of a note file's text, if any.
String? frontmatterUuidOf(String text) {
  final parsed = _splitFrontmatter(text);
  final value = parsed?.values['uuid'];
  return value is String && isUuid(value) ? value.toLowerCase() : null;
}

({Map<String, Object?> values, String body})? _splitFrontmatter(String text) {
  final lines = text.split('\n');
  if (lines.isEmpty || lines.first.trimRight() != '---') return null;
  final values = <String, Object?>{};
  var end = -1;
  for (var i = 1; i < lines.length; i++) {
    final line = lines[i].trimRight();
    if (line == '---') {
      end = i;
      break;
    }
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    final key = line.substring(0, colon).trim();
    values[key] = _parseScalar(line.substring(colon + 1).trim());
  }
  if (end < 0) return null;
  var body = lines.sublist(end + 1).join('\n');
  if (body.startsWith('\r\n')) {
    body = body.substring(2);
  } else if (body.startsWith('\n')) {
    body = body.substring(1);
  }
  if (body.endsWith('\n')) body = body.substring(0, body.length - 1);
  return (values: values, body: body);
}

Object? _parseScalar(String raw) {
  if (raw.isEmpty || raw == 'null' || raw == '~') return null;
  if (raw == 'true') return true;
  if (raw == 'false') return false;
  if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
    final inner = raw.substring(1, raw.length - 1);
    final out = StringBuffer();
    for (var i = 0; i < inner.length; i++) {
      final c = inner[i];
      if (c == '\\' && i + 1 < inner.length) {
        final next = inner[i + 1];
        if (next == '"' || next == '\\') {
          out.write(next);
          i++;
          continue;
        }
      }
      out.write(c);
    }
    return out.toString();
  }
  if (raw.length >= 2 && raw.startsWith("'") && raw.endsWith("'")) {
    return raw.substring(1, raw.length - 1).replaceAll("''", "'");
  }
  return raw;
}

String _fallbackTitle(String body, String path) {
  for (final line in body.split('\n')) {
    final t = line.trim();
    if (t.startsWith('# ')) return t.substring(2).trim();
  }
  return noteStemOf(path);
}

/// `../assets/` from `notes/x.md`, `../../assets/` from `trash/notes/x.md`.
String _diskAssetsPrefix(String path) {
  final depth = splitFolderPath(path).length - 1;
  return '${'../' * depth}$kAssetsDir/';
}

/// Starts of a link target: Markdown `](` (optionally `](<`) and HTML
/// `src="` / `href="` (either quote).
final RegExp _linkTarget = RegExp(r'''(\]\(\s*<?|\b(?:src|href)\s*=\s*["'])''');

/// Replaces [from] with [to] where it starts a link target.
String _rewrite(String body, String from, String to) {
  final out = StringBuffer();
  var last = 0;
  for (final m in _linkTarget.allMatches(body)) {
    if (m.end < last) continue;
    out.write(body.substring(last, m.end));
    last = m.end;
    if (body.startsWith(from, m.end)) {
      out.write(to);
      last = m.end + from.length;
    }
  }
  out.write(body.substring(last));
  return out.toString();
}

/// Disk form to app form: `](../assets/...` becomes `](nc-folder:///assets/...`.
String rewriteLinksToApp(String diskBody, {required String path}) =>
    _rewrite(diskBody, _diskAssetsPrefix(path), '$kFolderUrlPrefix$kAssetsDir/');

/// App form to disk form, relative to the note file at [path].
String rewriteLinksToDisk(String appBody, {required String path}) =>
    _rewrite(appBody, '$kFolderUrlPrefix$kAssetsDir/', _diskAssetsPrefix(path));

/// The `.meta.json` sidecar (3.2). Unknown keys survive in [extra].
class NoteSidecar {
  NoteSidecar({
    this.id,
    this.uuid,
    this.sharingId,
    this.metadataJson,
    this.customMeta,
    this.clientDraftId,
    this.noteType,
    this.sourceNoteUuid,
    this.coverImageUrl = '',
    this.description,
    this.wordCount,
    this.mdSize,
    this.mdLastModified,
    this.deletedAt,
    Map<String, Object?>? extra,
  }) : extra = Map<String, Object?>.unmodifiable(extra ?? const {});

  factory NoteSidecar.fromJson(Map<String, Object?> json) {
    const known = {
      'schema_version',
      'id',
      'uuid',
      'sharing_id',
      'metadata_json',
      'custom_meta',
      'client_draft_id',
      'note_type',
      'source_note_uuid',
      'cover_image_url',
      'description',
      'word_count',
      'md_size',
      'md_last_modified',
      'deleted_at',
    };
    // Sidecars may be edited by hand (3.8): a wrong-typed value reads as
    // absent, so one bad field never stops a scan.
    final uuid = json['uuid'];
    return NoteSidecar(
      id: jsonInt(json['id']),
      uuid: uuid is String && isUuid(uuid) ? uuid.toLowerCase() : null,
      sharingId: json['sharing_id'],
      metadataJson: json['metadata_json'],
      customMeta: json['custom_meta'],
      clientDraftId: jsonString(json['client_draft_id']),
      noteType: json['note_type'],
      sourceNoteUuid: jsonString(json['source_note_uuid']),
      coverImageUrl: jsonString(json['cover_image_url']) ?? '',
      description: jsonString(json['description']),
      wordCount: jsonInt(json['word_count']),
      mdSize: jsonInt(json['md_size']),
      mdLastModified: jsonInt(json['md_last_modified']),
      deletedAt: jsonString(json['deleted_at']),
      extra: {
        for (final e in json.entries)
          if (!known.contains(e.key)) e.key: e.value,
      },
    );
  }

  final int? id;
  final String? uuid;
  final Object? sharingId;
  final Object? metadataJson;
  final Object? customMeta;
  final String? clientDraftId;
  final Object? noteType;
  final String? sourceNoteUuid;
  final String coverImageUrl;
  final String? description;
  final int? wordCount;

  /// Size and `lastModified` of the `.md` at the app's last write (3.8).
  final int? mdSize;
  final int? mdLastModified;

  /// Set while the note is in `trash/notes/` (3.5).
  final String? deletedAt;
  final Map<String, Object?> extra;

  NoteSidecar copyWith({
    int? id,
    String? uuid,
    int? mdSize,
    int? mdLastModified,
  }) =>
      NoteSidecar(
        id: id ?? this.id,
        uuid: uuid ?? this.uuid,
        sharingId: sharingId,
        metadataJson: metadataJson,
        customMeta: customMeta,
        clientDraftId: clientDraftId,
        noteType: noteType,
        sourceNoteUuid: sourceNoteUuid,
        coverImageUrl: coverImageUrl,
        description: description,
        wordCount: wordCount,
        mdSize: mdSize ?? this.mdSize,
        mdLastModified: mdLastModified ?? this.mdLastModified,
        deletedAt: deletedAt,
        extra: extra,
      );

  /// The sidecar of a copied note that gets its own identity (3.7): new id
  /// and UUID, and no server sharing id or draft id shared with the original
  /// (`client_draft_id` becomes `fld_<uuid-hex>`).
  NoteSidecar forCopy({required int id, required String uuid}) => NoteSidecar(
        id: id,
        uuid: uuid,
        metadataJson: metadataJson,
        customMeta: customMeta,
        clientDraftId: 'fld_${uuidHex(uuid)}',
        noteType: noteType,
        sourceNoteUuid: sourceNoteUuid,
        coverImageUrl: coverImageUrl,
        description: description,
        wordCount: wordCount,
        deletedAt: deletedAt,
        extra: extra,
      );

  Map<String, Object?> toJson() => {
        ...extra,
        'schema_version': kFolderSchemaVersion,
        'id': id,
        'uuid': uuid,
        'sharing_id': sharingId,
        'metadata_json': metadataJson,
        'custom_meta': customMeta,
        'client_draft_id': clientDraftId,
        'note_type': noteType,
        'source_note_uuid': sourceNoteUuid,
        'cover_image_url': coverImageUrl,
        if (description != null) 'description': description,
        if (wordCount != null) 'word_count': wordCount,
        if (mdSize != null) 'md_size': mdSize,
        if (mdLastModified != null) 'md_last_modified': mdLastModified,
        if (deletedAt != null) 'deleted_at': deletedAt,
      };

  String encode() => encodeFolderJson(toJson());
}

/// Decodes a sidecar; null when the text is not a JSON object.
NoteSidecar? decodeSidecar(String text) {
  final json = decodeJsonObject(text);
  return json == null ? null : NoteSidecar.fromJson(json);
}

/// Rewrites only the value of the frontmatter `uuid:` line, so the rest of
/// a user's file stays byte-identical. Null when [text] has no frontmatter
/// `uuid` line.
String? replaceFrontmatterUuid(String text, String uuid) {
  final lines = text.split('\n');
  if (lines.isEmpty || lines.first.trimRight() != '---') return null;
  for (var i = 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.trimRight() == '---') return null;
    if (line.startsWith('uuid:')) {
      final cr = line.endsWith('\r') ? '\r' : '';
      lines[i] = 'uuid: "$uuid"$cr';
      return lines.join('\n');
    }
  }
  return null;
}

/// After a write of a note body, records its size and `lastModified` in the
/// sidecar (`md_size`, `md_last_modified`, 3.8). A journal record cannot
/// carry them, because `lastModified` is known only after the write. The
/// caller still holds the exclusive lock. A missing sidecar is left alone.
Future<void> stampNoteSidecar(FolderFs fs, String mdPath) async {
  final stat = await fs.stat(mdPath);
  final sidecarPath = sidecarPathForBody(mdPath);
  final text = await readTextOrNull(fs, sidecarPath);
  if (stat == null || text == null) return;
  final sidecar = decodeSidecar(text);
  if (sidecar == null || stat.sameAs(sidecar.mdSize, sidecar.mdLastModified)) {
    return;
  }
  await fs.writeText(
      sidecarPath,
      sidecar
          .copyWith(mdSize: stat.size, mdLastModified: stat.lastModified)
          .encode());
}
