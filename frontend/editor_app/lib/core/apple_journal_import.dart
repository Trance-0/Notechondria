part of notechondria_frontend;

class _AppleJournalEntry {
  const _AppleJournalEntry({
    required this.sourcePath,
    required this.title,
    required this.body,
    required this.metadata,
    required this.mediaPaths,
    this.createdAt,
    this.updatedAt,
  });

  final String sourcePath;
  final String title;
  final String body;
  final Map<String, dynamic> metadata;
  final List<String> mediaPaths;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

class _AppleJournalImportTarget {
  const _AppleJournalImportTarget.existing(this.courseId) : newTitle = null;

  const _AppleJournalImportTarget.create(this.newTitle) : courseId = null;

  final int? courseId;
  final String? newTitle;
}

extension _AppShellAppleJournalImportX on _AppShellState {
  Future<void> _importAppleJournalArchive() async {
    const source = 'Editor.LocalStore/apple_journal_import';
    try {
      log(
        level: DebugLogLevel.info,
        source: source,
        message:
            'Apple Journal import started: $source - waiting for ZIP picker.',
      );
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Apple Journal export ZIP', extensions: ['zip']),
        ],
      );
      if (file == null) {
        log(
          level: DebugLogLevel.info,
          source: source,
          message: 'Apple Journal import canceled: $source - no ZIP selected.',
        );
        return;
      }

      final archive = await timed(
        '$source.decode_zip',
        () async => ZipDecoder().decodeBytes(await file.readAsBytes()),
      );
      final entries = _parseAppleJournalEntries(archive);
      if (entries.isEmpty) {
        log(
          level: DebugLogLevel.warning,
          source: source,
          message: 'Apple Journal import did not start: $source - selected ZIP '
              'contained no readable Markdown or JSON journal entries.',
        );
        showMessage(
          'Apple Journal import did not start: '
          'Editor.LocalStore/apple_journal_import — '
          'selected ZIP contained no readable journal entries.',
        );
        return;
      }
      log(
        level: DebugLogLevel.info,
        source: source,
        message:
            'Apple Journal ZIP parsed: $source - ${entries.length} readable '
            'entr${entries.length == 1 ? 'y' : 'ies'} found.',
      );

      final target = await _chooseAppleJournalImportTarget(entries.length);
      if (target == null) {
        log(
          level: DebugLogLevel.info,
          source: source,
          message:
              'Apple Journal import canceled: $source - category selection '
              'closed before import.',
        );
        return;
      }

      Map<String, dynamic>? createdCourse;
      var courseId = target.courseId;
      if (courseId == null) {
        createdCourse = _buildLocalCourse(
          title: target.newTitle ?? 'Apple Journal',
          description: 'Imported from Apple Journal; cloud sync is manual.',
        );
        courseId = (createdCourse['id'] as num?)?.toInt();
        _localCourses = [createdCourse, ..._localCourses];
      }
      log(
        level: DebugLogLevel.info,
        source: source,
        message: courseId == null
            ? 'Apple Journal import target missing: $source - local category '
                'creation did not return an id.'
            : 'Apple Journal import target selected: $source - saving local '
                'drafts under category id $courseId; cloud sync remains paused.',
      );

      final filesByPath = _archiveFilesByPath(archive);
      final store = await LocalAttachmentStore.open();
      final importedDrafts = <Map<String, dynamic>>[];
      var attachmentCount = 0;
      var skippedAttachmentCount = 0;

      for (final entry in entries) {
        final clientDraftId = _LocalAppStore.newDraftId();
        final queued = <Map<String, dynamic>>[];
        final mediaEmbeds = <String>[];
        for (final mediaPath in entry.mediaPaths) {
          final mediaFile = _findArchiveFile(filesByPath, mediaPath);
          if (mediaFile == null || !mediaFile.isFile) continue;
          final bytes = _archiveFileBytes(mediaFile);
          final filename = _basename(mediaFile.name);
          final contentType = _appleJournalContentType(filename, bytes);
          try {
            final record = await store.put(
              noteUuid: clientDraftId,
              filename: filename,
              contentType: contentType,
              bytes: bytes,
            );
            queued.add({
              'filename': record.filename,
              'content_type': record.contentType,
              'size_bytes': record.sizeBytes,
              'local_url': record.localUrl,
              'note_uuid': record.noteUuid,
              'queued_at': record.createdAt.toIso8601String(),
              'source_path': mediaFile.name,
            });
            mediaEmbeds.add(_appleJournalMediaEmbed(record, contentType));
            attachmentCount += 1;
          } catch (error) {
            skippedAttachmentCount += 1;
            log(
              level: DebugLogLevel.warning,
              source: source,
              message: 'Apple Journal media skipped: '
                  'Editor.LocalStore/apple_journal_import — '
                  '"${mediaFile.name}" was not stored locally: '
                  '${error.toString().replaceFirst('Exception: ', '')}.',
            );
          }
        }

        final metadata = <String, dynamic>{
          ...entry.metadata,
          'source': 'apple-journal-import',
          'source_path': entry.sourcePath,
          'course_id': courseId,
          'cloud_sync': 'paused_until_manual_push',
          'imported_at': DateTime.now().toUtc().toIso8601String(),
          if (entry.createdAt != null)
            'created': entry.createdAt!.toIso8601String(),
          if (entry.updatedAt != null)
            'updated': entry.updatedAt!.toIso8601String(),
          if (queued.isNotEmpty) 'queued_attachments': queued,
          if (queued.isNotEmpty)
            'media': queued.map((item) => item['local_url']).toList(),
        };
        final markdown = _appleJournalMarkdown(entry, metadata, mediaEmbeds);
        final draft = _buildLocalDraft(
          title: entry.title,
          content: markdown,
          editorMode: 'G',
          clientDraftId: clientDraftId,
          createdAt: entry.createdAt?.toIso8601String(),
          metadataJson: jsonEncode(metadata),
        );
        importedDrafts.add({
          ...draft,
          'course_id': courseId,
        });
      }

      _localDrafts = [...importedDrafts, ..._localDrafts];
      if (createdCourse != null) {
        _selectedCourse = createdCourse;
      } else {
        _selectedCourse = _localCourses.firstWhere(
          (course) => (course['id'] as num?)?.toInt() == courseId,
          orElse: () => _selectedCourse ?? const <String, dynamic>{},
        );
      }
      _localStats = {
        ..._localStats,
        'local_drafts_created':
            ((_localStats['local_drafts_created'] as num?)?.toInt() ?? 0) +
                importedDrafts.length,
        if (createdCourse != null)
          'local_courses_created':
              ((_localStats['local_courses_created'] as num?)?.toInt() ?? 0) +
                  1,
        'last_apple_journal_import_at':
            DateTime.now().toUtc().toIso8601String(),
      };
      await persistLocalCourses();
      await persistLocalDrafts();
      await persistLocalStats();
      await _persistLocalCache();
      refreshState();

      final suffix = skippedAttachmentCount > 0
          ? ', $skippedAttachmentCount media file(s) skipped'
          : '';
      final message =
          'Apple Journal imported: Editor.LocalStore/apple_journal_import — '
          '${importedDrafts.length} draft(s) and $attachmentCount media '
          'file(s) saved locally; cloud sync paused until manual push$suffix.';
      log(
        level: DebugLogLevel.info,
        source: source,
        message: message,
      );
      showMessage(message);
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      showMessage(
        'Apple Journal import failed: '
        'Editor.LocalStore/apple_journal_import — $cause.',
      );
      log(
        level: DebugLogLevel.error,
        source: source,
        message: 'Apple Journal import failed: '
            'Editor.LocalStore/apple_journal_import — $cause.',
      );
    }
  }

  Future<_AppleJournalImportTarget?> _chooseAppleJournalImportTarget(
      int entryCount) async {
    final localCourses = List<Map<String, dynamic>>.from(_localCourses);
    final titleController = TextEditingController(text: 'Apple Journal');
    var createNew = localCourses.isEmpty;
    int? selectedCourseId = localCourses.isEmpty
        ? null
        : (localCourses.first['id'] as num?)?.toInt();
    final result = await showDialog<_AppleJournalImportTarget>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Import Apple Journal'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$entryCount entr${entryCount == 1 ? 'y' : 'ies'} will be '
                'created as local drafts. Cloud sync will wait until '
                'you manually push local data.',
              ),
              const SizedBox(height: 16),
              if (localCourses.isNotEmpty)
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('Existing'),
                      icon: Icon(Icons.folder_outlined),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('New'),
                      icon: Icon(Icons.create_new_folder_outlined),
                    ),
                  ],
                  selected: {createNew},
                  onSelectionChanged: (selection) =>
                      setDialogState(() => createNew = selection.first),
                ),
              const SizedBox(height: 12),
              if (!createNew && localCourses.isNotEmpty)
                DropdownButtonFormField<int>(
                  value: selectedCourseId,
                  decoration: const InputDecoration(
                    labelText: 'Local category',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final course in localCourses)
                      DropdownMenuItem<int>(
                        value: (course['id'] as num?)?.toInt(),
                        child: Text(course['title']?.toString() ?? 'Category'),
                      ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => selectedCourseId = value),
                )
              else
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'New local category',
                    border: OutlineInputBorder(),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (createNew || localCourses.isEmpty) {
                  final title = titleController.text.trim();
                  if (title.isEmpty) return;
                  Navigator.of(ctx).pop(
                    _AppleJournalImportTarget.create(title),
                  );
                } else if (selectedCourseId != null) {
                  Navigator.of(ctx).pop(
                    _AppleJournalImportTarget.existing(selectedCourseId),
                  );
                }
              },
              child: const Text('Import'),
            ),
          ],
        ),
      ),
    );
    titleController.dispose();
    return result;
  }
}

List<_AppleJournalEntry> _parseAppleJournalEntries(Archive archive) {
  final filesByPath = _archiveFilesByPath(archive);
  final entries = <_AppleJournalEntry>[];
  for (final file in archive) {
    if (!file.isFile) continue;
    final lower = file.name.toLowerCase();
    if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
      final raw = utf8.decode(_archiveFileBytes(file), allowMalformed: true);
      final parsed = _parseAppleJournalMarkdown(raw);
      final title = parsed.title ?? _titleFromPath(file.name);
      entries.add(
        _AppleJournalEntry(
          sourcePath: file.name,
          title: title,
          body: parsed.body,
          metadata: {
            if (parsed.description != null) 'description': parsed.description,
          },
          mediaPaths: _mediaPathsFromText(parsed.body, filesByPath),
        ),
      );
    } else if (lower.endsWith('.json')) {
      final raw = utf8.decode(_archiveFileBytes(file), allowMalformed: true);
      dynamic decoded;
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        continue;
      }
      for (final object in _journalObjects(decoded)) {
        final entry = _entryFromJournalJson(object, file.name, filesByPath);
        if (entry != null) entries.add(entry);
      }
    }
  }
  entries.sort((a, b) {
    final left = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final right = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return left.compareTo(right);
  });
  return entries;
}

Map<String, ArchiveFile> _archiveFilesByPath(Archive archive) {
  return {
    for (final file in archive)
      if (file.isFile) file.name.replaceAll('\\', '/'): file,
  };
}

Iterable<Map<String, dynamic>> _journalObjects(dynamic decoded) sync* {
  if (decoded is List) {
    for (final item in decoded) {
      yield* _journalObjects(item);
    }
  } else if (decoded is Map) {
    final map = Map<String, dynamic>.from(decoded);
    const containerKeys = ['entries', 'journals', 'items', 'records'];
    final hasContainer = containerKeys.any((key) => map[key] is List);
    if (!hasContainer &&
        (_journalBodyFromMap(map).trim().isNotEmpty ||
            _journalMediaPaths(map, const {}).isNotEmpty)) {
      yield map;
    }
    for (final key in containerKeys) {
      final value = map[key];
      if (value is List) yield* _journalObjects(value);
    }
  }
}

_AppleJournalEntry? _entryFromJournalJson(
  Map<String, dynamic> object,
  String sourcePath,
  Map<String, ArchiveFile> filesByPath,
) {
  final body = _journalBodyFromMap(object).trim();
  final mediaPaths = _journalMediaPaths(object, filesByPath);
  if (body.isEmpty && mediaPaths.isEmpty) return null;
  final createdAt = _dateFromJournalMap(object, const [
    'created',
    'createdAt',
    'createdDate',
    'creationDate',
    'date',
    'startDate',
  ]);
  final updatedAt = _dateFromJournalMap(object, const [
    'updated',
    'updatedAt',
    'updatedDate',
    'modifiedDate',
  ]);
  final title = _firstStringForKeys(object, const [
        'title',
        'headline',
        'name',
      ]) ??
      (createdAt == null
          ? _titleFromPath(sourcePath)
          : 'Journal ${createdAt.toLocal().toIso8601String().split('T').first}');
  final metadata = <String, dynamic>{
    if (_tagsFromJournalMap(object).isNotEmpty)
      'tags': _tagsFromJournalMap(object),
    if (object['location'] is Map)
      'location': Map<String, dynamic>.from(object['location'] as Map),
    if (object['weather'] != null) 'weather': object['weather'],
    if (object['mood'] != null) 'mood': object['mood'],
  };
  return _AppleJournalEntry(
    sourcePath: sourcePath,
    title: title,
    body: body,
    metadata: metadata,
    mediaPaths: mediaPaths,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

String _journalBodyFromMap(Map<String, dynamic> object) {
  final direct = _firstStringForKeys(object, const [
    'markdown',
    'body',
    'content',
    'text',
    'entryText',
    'note',
  ]);
  if (direct != null && direct.trim().isNotEmpty) return direct;
  final candidates = <String>[];
  void visit(dynamic value, String key) {
    if (value is Map) {
      value.forEach((nestedKey, nestedValue) {
        visit(nestedValue, nestedKey.toString());
      });
    } else if (value is List) {
      for (final item in value) {
        visit(item, key);
      }
    } else if (value is String &&
        (key.toLowerCase().contains('text') ||
            key.toLowerCase().contains('body'))) {
      candidates.add(value);
    }
  }

  object.forEach((key, value) => visit(value, key));
  return candidates.join('\n\n').trim();
}

String? _firstStringForKeys(Map<String, dynamic> object, List<String> keys) {
  for (final key in keys) {
    final value = object[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

DateTime? _dateFromJournalMap(Map<String, dynamic> object, List<String> keys) {
  final raw = _firstStringForKeys(object, keys);
  if (raw == null) return null;
  return DateTime.tryParse(raw)?.toUtc();
}

List<String> _tagsFromJournalMap(Map<String, dynamic> object) {
  final raw = object['tags'] ?? object['keywords'];
  if (raw is List) {
    return raw
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  if (raw is String && raw.trim().isNotEmpty) {
    return raw
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  return const [];
}

List<String> _journalMediaPaths(
  Map<String, dynamic> object,
  Map<String, ArchiveFile> filesByPath,
) {
  final candidates = <String>{};
  void visit(dynamic value) {
    if (value is Map) {
      value.values.forEach(visit);
    } else if (value is List) {
      value.forEach(visit);
    } else if (value is String && _looksLikeMediaPath(value)) {
      candidates.add(value);
    }
  }

  visit(object);
  return candidates
      .where((path) =>
          filesByPath.isEmpty || _findArchiveFile(filesByPath, path) != null)
      .toList(growable: false);
}

List<String> _mediaPathsFromText(
  String body,
  Map<String, ArchiveFile> filesByPath,
) {
  final paths = <String>{};
  final pattern = RegExp(r'!?\[[^\]]*\]\(([^)]+)\)');
  for (final match in pattern.allMatches(body)) {
    final path = match.group(1)?.trim() ?? '';
    if (_looksLikeMediaPath(path) &&
        _findArchiveFile(filesByPath, path) != null) {
      paths.add(path);
    }
  }
  return paths.toList(growable: false);
}

bool _looksLikeMediaPath(String value) {
  final lower = value.toLowerCase();
  return lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.heic') ||
      lower.endsWith('.heif') ||
      lower.endsWith('.m4a') ||
      lower.endsWith('.mp3') ||
      lower.endsWith('.wav') ||
      lower.endsWith('.mp4') ||
      lower.endsWith('.mov') ||
      lower.endsWith('.pdf');
}

ArchiveFile? _findArchiveFile(
  Map<String, ArchiveFile> filesByPath,
  String candidate,
) {
  final normalized = candidate.replaceAll('\\', '/');
  if (filesByPath.containsKey(normalized)) return filesByPath[normalized];
  final base = _basename(normalized);
  for (final entry in filesByPath.entries) {
    if (entry.key.endsWith('/$normalized') || _basename(entry.key) == base) {
      return entry.value;
    }
  }
  return null;
}

Uint8List _archiveFileBytes(ArchiveFile file) {
  final content = file.content;
  if (content is Uint8List) return content;
  if (content is List<int>) return Uint8List.fromList(content);
  return Uint8List(0);
}

String _appleJournalContentType(String filename, Uint8List bytes) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.heic')) return 'image/heic';
  if (lower.endsWith('.heif')) return 'image/heif';
  if (lower.endsWith('.m4a')) return 'audio/mp4';
  if (lower.endsWith('.mp3')) return 'audio/mpeg';
  if (lower.endsWith('.wav')) return 'audio/wav';
  if (lower.endsWith('.mp4')) return 'video/mp4';
  if (lower.endsWith('.mov')) return 'video/quicktime';
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  return 'application/octet-stream';
}

String _appleJournalMediaEmbed(LocalAttachment record, String contentType) {
  if (contentType.startsWith('image/')) {
    return '![${record.filename}](${record.localUrl})';
  }
  return '[${record.filename}](${record.localUrl})';
}

String _appleJournalMarkdown(
  _AppleJournalEntry entry,
  Map<String, dynamic> metadata,
  List<String> mediaEmbeds,
) {
  final buffer = StringBuffer();
  buffer.writeln('---');
  buffer.writeln(
      'id: ${_yamlScalar(metadata['source_path']?.toString() ?? entry.sourcePath)}');
  if (metadata['created'] != null) {
    buffer.writeln('created: ${metadata['created']}');
  }
  if (metadata['updated'] != null) {
    buffer.writeln('updated: ${metadata['updated']}');
  }
  buffer.writeln('source: apple-journal-import');
  final tags = metadata['tags'];
  if (tags is List && tags.isNotEmpty) {
    buffer.writeln(
        'tags: [${tags.map((tag) => _yamlScalar(tag.toString())).join(', ')}]');
  }
  if (mediaEmbeds.isNotEmpty) {
    buffer.writeln('media:');
    for (final queued
        in (metadata['queued_attachments'] as List?) ?? const []) {
      final localUrl = (queued as Map)['local_url']?.toString() ?? '';
      if (localUrl.isNotEmpty) buffer.writeln('  - $localUrl');
    }
  }
  buffer.writeln('---');
  buffer.writeln();
  if (entry.body.trim().isNotEmpty) {
    buffer.writeln(entry.body.trim());
  }
  if (mediaEmbeds.isNotEmpty) {
    buffer.writeln();
    buffer.writeln('## Media');
    for (final embed in mediaEmbeds) {
      buffer.writeln();
      buffer.writeln(embed);
    }
  }
  return buffer.toString().trim();
}

_ImportedMarkdown _parseAppleJournalMarkdown(String content) {
  final lines = content.split('\n');
  if (lines.isEmpty || lines.first.trim() != '---') {
    return _ImportedMarkdown(body: content);
  }
  final closingIndex = lines.indexWhere((line) => line.trim() == '---', 1);
  if (closingIndex < 0) return _ImportedMarkdown(body: content);
  final headerLines = lines.sublist(1, closingIndex);
  String? title;
  String? description;
  for (final line in headerLines) {
    final idx = line.indexOf(':');
    if (idx <= 0) continue;
    final key = line.substring(0, idx).trim().toLowerCase();
    final value = line.substring(idx + 1).trim().replaceAll('"', '');
    if (key == 'title') title = value;
    if (key == 'description') description = value;
  }
  return _ImportedMarkdown(
    title: title,
    description: description,
    body: lines.sublist(closingIndex + 1).join('\n').trimLeft(),
  );
}

String _titleFromPath(String path) {
  final base = _basename(path)
      .replaceAll(RegExp(r'\.(md|markdown|json)$', caseSensitive: false), '')
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .trim();
  return base.isEmpty ? 'Apple Journal entry' : base;
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/');
  return parts.isEmpty ? normalized : parts.last;
}

String _yamlScalar(String value) {
  final escaped = value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  return '"$escaped"';
}
