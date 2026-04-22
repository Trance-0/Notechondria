part of notechondria_frontend;

/// Note CRUD orchestration: create, save, upload attachments, import
/// from disk, export to markdown/zip, fetch history, and snapshot /
/// restore versions. `_promoteQueuedAttachments` is the offline-only
/// cleanup that uploads pending images when connectivity returns.
/// Yaml frontmatter helpers `_frontmatterForNote`, `_yamlEscape`, and
/// `_noteMarkdownBody` feed the export path. State mutations route
/// through `_refresh()` since extensions can't call `setState`
/// directly. Extracted from `app_shell.dart` so that file stays
/// closer to the AGENTS.md §1.5 1000-line ceiling.
extension _AppShellNoteCrudX on _AppShellState {
  Future<Map<String, dynamic>> _createNote({
    String? markdown,
    String? title,
    String? description,
    String? clientDraftId,
  }) async {
    final token = _token;
    final mode = _settings?['editor_mode']?.toString() ??
        _profile?['editor_mode']?.toString() ??
        'P';
    final initialMarkdown =
        (markdown ?? '# ${title ?? 'Untitled note'}\n\n').trim();
    if (token == null || token.isEmpty) {
      final draft = _buildLocalDraft(
        title: title ?? _extractTitleFromMarkdown(initialMarkdown),
        content: initialMarkdown,
        description: description ?? '',
        editorMode: mode,
        clientDraftId: clientDraftId,
      );
      _localDrafts = [draft, ..._localDrafts];
      _localStats = {
        ..._localStats,
        'local_drafts_created':
            ((_localStats['local_drafts_created'] as num?)?.toInt() ?? 0) + 1,
      };
      await _persistLocalDrafts();
      await _persistLocalStats();
        _selectedNote = draft;
        _selectedIndex = 1;
      _refresh();
      return draft;
    }
    final payload = <String, dynamic>{
      'title': title ?? _extractTitleFromMarkdown(initialMarkdown),
      'description':
          description ?? _excerptFromMarkdown(initialMarkdown),
      'content': initialMarkdown,
      'editor_mode': mode,
      'metadata_json': jsonEncode({'section': '', 'autosave': false}),
      if (clientDraftId != null) 'client_draft_id': clientDraftId,
    };
    try {
      final created = await widget.client.createNote(token, payload);
      await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
        _selectedNote = created;
        _selectedIndex = 1;
      _refresh();
      final uuid = created['uuid']?.toString();
      if (uuid != null) _pushNoteUrl(uuid);
      return created;
    } catch (error) {
      final draft = _storeLocalDraft(
        _buildOfflineFallbackDraft(payload: payload),
        incrementCreated: true,
      );
      await _persistLocalDrafts();
      await _persistLocalStats();
      final cause = error.toString().replaceFirst('Exception: ', '');
        _selectedNote = draft;
        _selectedIndex = 1;
      _refresh();
      _log(
        level: DebugLogLevel.warning,
        source: 'Editor.Sync.Notes/create',
        message:
            'Note saved locally, cloud create deferred: '
            'Editor.Sync.Notes/create \u2014 $cause.',
      );
      _showMessage(
        'Note saved locally: Editor.Sync.Notes/create \u2014 '
        'backend unavailable ($cause); kept as draft for next sync.',
      );
      return draft;
    }
  }

  Future<Map<String, dynamic>> _saveNote(
      int noteId, Map<String, dynamic> payload) async {
    if (noteId < 0) {
      final existing = _localDrafts.firstWhere(
        (item) => item['id'] == noteId,
        orElse: () => <String, dynamic>{},
      );
      if (existing.isEmpty) throw Exception('Local draft not found.');
      final updated = _buildLocalDraft(
        id: noteId,
        title: payload['title']?.toString() ??
            existing['title']?.toString() ??
            'Untitled note',
        description: payload['description']?.toString() ??
            existing['description']?.toString() ??
            '',
        content: payload['content']?.toString() ??
            existing['content']?.toString() ??
            '',
        editorMode: payload['editor_mode']?.toString() ??
            existing['editor_mode']?.toString() ??
            'P',
        clientDraftId: existing['client_draft_id']?.toString(),
        createdAt: existing['date_created']?.toString(),
        metadataJson: payload['metadata_json']?.toString() ??
            existing['metadata_json']?.toString() ??
            '{}',
      );
      _localDrafts = _localDrafts
          .map((item) => item['id'] == noteId ? updated : item)
          .toList(growable: false);
      await _persistLocalDrafts();
      _selectedNote = updated;

      _refresh();
      return updated;
    }
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception('Sign in to save cloud notes.');
    }
    try {
      final updated = await widget.client.updateNote(token, noteId, payload);
      await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
      _selectedNote = updated;

      _refresh();
      final uuid = updated['uuid']?.toString();
      if (uuid != null) _replaceNoteUrl(uuid);
      return updated;
    } catch (error) {
      final sourceNote = _selectedNote?['id'] == noteId
          ? Map<String, dynamic>.from(_selectedNote!)
          : null;
      final fallbackDraft = _storeLocalDraft(
        _buildOfflineFallbackDraft(sourceNote: sourceNote, payload: payload),
      );
      await _persistLocalDrafts();
      final cause = error.toString().replaceFirst('Exception: ', '');
      _selectedNote = fallbackDraft;

      _refresh();
      _log(
        level: DebugLogLevel.warning,
        source: 'Editor.Sync.Notes/save',
        message:
            'Note save deferred to local draft: '
            'Editor.Sync.Notes/save \u2014 $cause.',
      );
      _showMessage(
        'Note saved locally: Editor.Sync.Notes/save \u2014 '
        'backend unavailable ($cause); changes kept as a local draft.',
      );
      return fallbackDraft;
    }
  }

  Future<Map<String, dynamic>> _uploadNoteAttachment(
      int noteId, XFile file) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception(
        'Attachment not uploaded: '
        'Editor.Sync.Notes/attachment.upload \u2014 '
        'no cloud session; sign in first.',
      );
    }
    return widget.client.uploadNoteAttachment(token, noteId, file);
  }

  /// Promote any attachments the editor queued into the draft's
  /// `metadata_json['queued_attachments']` list to real CDN uploads
  /// against the freshly-synced cloud note id.
  ///
  /// Reads bytes from `LocalAttachmentStore` (keyed by
  /// `local://<note_uuid>/<filename>`), streams them through
  /// `widget.client.uploadNoteAttachment`, rewrites every
  /// `local://...` URL in the note body to the CDN-issued URL, and
  /// deletes the local blob on success so the device storage
  /// eventually frees.
  ///
  /// Legacy compatibility: drafts that still carry
  /// `bytes_base64` payloads from the 0.1.37 era fall back to the old
  /// decode-and-upload path so a user with pre-migration drafts
  /// still sees their attachments promoted.
  Future<Map<String, dynamic>> _promoteQueuedAttachments(
    Map<String, dynamic> note,
    Map<String, dynamic> metadata,
  ) async {
    final queued = List<Map<String, dynamic>>.from(
      (metadata['queued_attachments'] as List?) ?? const [],
    );
    if (queued.isEmpty) return note;
    final noteId = (note['id'] as num?)?.toInt();
    final token = _token;
    if (noteId == null || noteId < 0 || token == null || token.isEmpty) {
      return note;
    }
    var content = note['content']?.toString() ?? '';
    final store = await LocalAttachmentStore.open();
    final promotedLocalUrls = <String>[];
    for (final entry in queued) {
      final filename = entry['filename']?.toString() ?? 'attachment';
      final contentType =
          entry['content_type']?.toString() ?? 'application/octet-stream';
      final localUrl = entry['local_url']?.toString() ?? '';
      final base64Str = entry['bytes_base64']?.toString() ?? '';

      Uint8List? bytes;
      if (localUrl.isNotEmpty) {
        try {
          bytes = await store.getBytes(localUrl: localUrl);
        } catch (error) {
          _log(
            level: DebugLogLevel.warning,
            source: 'Editor.Sync.Notes/attachment.promote',
            message:
                'Queued attachment not uploaded: '
                'Editor.Sync.Notes/attachment.promote \u2014 '
                '"$filename" missing from local store '
                '(${error.toString().replaceFirst('Exception: ', '')}).',
          );
          continue;
        }
      } else if (base64Str.isNotEmpty) {
        try {
          bytes = base64Decode(base64Str);
        } catch (_) {
          continue;
        }
      } else {
        continue;
      }

      try {
        final xfile = XFile.fromData(bytes,
            name: filename, mimeType: contentType);
        final attachment =
            await widget.client.uploadNoteAttachment(token, noteId, xfile);
        final url = attachment['url']?.toString() ?? '';
        if (url.isNotEmpty) {
          if (localUrl.isNotEmpty) {
            content = content.replaceAll(localUrl, url);
            promotedLocalUrls.add(localUrl);
          } else if (base64Str.isNotEmpty) {
            final dataUri = 'data:$contentType;base64,$base64Str';
            content = content.replaceAll(dataUri, url);
          }
        }
      } catch (error) {
        _log(
          level: DebugLogLevel.warning,
          source: 'Editor.Sync.Notes/attachment.promote',
          message:
              'Queued attachment not uploaded: '
              'Editor.Sync.Notes/attachment.promote \u2014 '
              '"$filename" dropped after upload failure '
              '(${error.toString().replaceFirst('Exception: ', '')}).',
        );
      }
    }
    // Drop the queue regardless so the draft doesn't retry failed
    // entries forever.
    metadata.remove('queued_attachments');

    // Free successfully-promoted local blobs. A failure here is
    // harmless (device storage just holds an unused file until the
    // user clears local data).
    for (final url in promotedLocalUrls) {
      try {
        await store.delete(localUrl: url);
      } catch (_) {}
    }

    Map<String, dynamic> latest = note;
    if (content != note['content']) {
      try {
        latest = await widget.client.updateNote(token, noteId, {
          'content': content,
          'metadata_json': jsonEncode(metadata),
        });
        _log(
          level: DebugLogLevel.info,
          source: 'Editor.Sync.Notes/attachment.promote',
          message:
              'Queued attachments promoted: '
              'Editor.Sync.Notes/attachment.promote \u2014 '
              '${queued.length} queued item(s) replaced with server URLs '
              'on note $noteId.',
        );
      } catch (_) {
        // Note content was not patched; body still carries
        // `local://...` URLs that the editor's custom image builder
        // can resolve from the store until the user retries.
      }
    } else {
      // No URL substitution happened but strip the queue anyway.
      try {
        latest = await widget.client.updateNote(token, noteId, {
          'metadata_json': jsonEncode(metadata),
        });
      } catch (_) {}
    }
    return latest;
  }

  Future<List<Map<String, dynamic>>> _getNoteHistory(int noteId) async {
    final token = _token;
    if (token == null || token.isEmpty || noteId < 0) return const [];
    return widget.client.getNoteHistory(token, noteId);
  }

  Future<Map<String, dynamic>> _snapshotNote(int noteId,
      {String reason = 'manual'}) async {
    final token = _token;
    if (token == null || token.isEmpty || noteId < 0) {
      return {'id': noteId, 'reason': reason};
    }
    return widget.client.snapshotNote(token, noteId, reason: reason);
  }

  Future<Map<String, dynamic>> _restoreNoteVersion(
      int noteId, int versionId) async {
    final token = _token;
    if (token == null || token.isEmpty || noteId < 0) {
      throw Exception('Sign in to restore notes.');
    }
    final restored =
        await widget.client.restoreNoteVersion(token, noteId, versionId);
    await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
    _selectedNote = restored;

    _refresh();
    return restored;
  }

  /// Imports one or more notes from a markdown file or a zip archive. Mirrors
  /// the export flow: each note may carry a YAML frontmatter block whose
  /// `title`/`description`/`category` fields are round-tripped back into the
  /// created note. Zip archives iterate every `.md` entry at any depth so a
  /// recursive export can be re-imported in one step.
  Future<void> _importMarkdownNote() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
              label: 'Markdown or zip',
              extensions: ['md', 'markdown', 'txt', 'zip']),
        ],
      );
      if (file == null) return;
      final name = file.name.toLowerCase();
      if (name.endsWith('.zip')) {
        await _importNotesFromZip(file);
      } else {
        final contents = await file.readAsString();
        final parsed = _parseImportedMarkdown(contents);
        final created = await _createNote(
          markdown: parsed.body,
          title: parsed.title ?? _extractTitleFromMarkdown(parsed.body),
          description: parsed.description ?? '',
        );
        _showMessage("Imported '${created['title']}'.");
      }
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Decodes a zip archive and creates one note per `.md` entry.
  Future<void> _importNotesFromZip(XFile file) async {
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    int importedCount = 0;
    int skippedCount = 0;
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final lowerName = entry.name.toLowerCase();
      if (!(lowerName.endsWith('.md') || lowerName.endsWith('.markdown'))) {
        // Non-markdown entries (media, .metadata) are skipped — the current
        // import path only creates notes, not media attachments.
        skippedCount += 1;
        continue;
      }
      try {
        final content = utf8.decode(entry.content as List<int>);
        final parsed = _parseImportedMarkdown(content);
        // Fall back to the zip entry filename (without extension) when the
        // markdown has no title + no frontmatter.
        final fallbackTitle = entry.name.split('/').last.replaceAll(
              RegExp(r'\.(md|markdown)$', caseSensitive: false),
              '',
            );
        final derivedTitle = _extractTitleFromMarkdown(parsed.body);
        await _createNote(
          markdown: parsed.body,
          title: parsed.title ??
              (derivedTitle == 'Untitled note'
                  ? (fallbackTitle.isEmpty
                      ? 'Imported note'
                      : fallbackTitle)
                  : derivedTitle),
          description: parsed.description ?? '',
        );
        importedCount += 1;
      } catch (error) {
        _log(
          level: DebugLogLevel.warning,
          source: 'Editor.LocalStore/import_zip',
          message:
              'Archive entry skipped: '
              'Editor.LocalStore/import_zip \u2014 '
              '"${entry.name}": '
              '${error.toString().replaceFirst('Exception: ', '')}.',
        );
        skippedCount += 1;
      }
    }
    if (importedCount == 0) {
      _showMessage('No markdown entries found in archive.');
    } else {
      final suffix = skippedCount > 0 ? ' ($skippedCount skipped)' : '';
      _showMessage('Imported $importedCount note(s) from zip.$suffix');
    }
  }

  /// Splits imported markdown into optional YAML frontmatter + body. Recognizes
  /// the exact frontmatter shape we emit during export (`title`, `description`,
  /// `category`, `author`, `last_edit`).
  _ImportedMarkdown _parseImportedMarkdown(String content) {
    final lines = content.split('\n');
    if (lines.isEmpty || lines.first.trim() != '---') {
      return _ImportedMarkdown(body: content);
    }
    final closingIndex = lines.indexWhere((l) => l.trim() == '---', 1);
    if (closingIndex < 0) {
      return _ImportedMarkdown(body: content);
    }
    final headerLines = lines.sublist(1, closingIndex);
    final body = lines.sublist(closingIndex + 1).join('\n').trimLeft();
    String? title;
    String? description;
    for (final line in headerLines) {
      final colonIdx = line.indexOf(':');
      if (colonIdx <= 0) continue;
      final key = line.substring(0, colonIdx).trim().toLowerCase();
      var value = line.substring(colonIdx + 1).trim();
      // Strip surrounding quotes from yaml-escape output.
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      if (key == 'title') {
        title = value;
      } else if (key == 'description') {
        description = value;
      }
    }
    return _ImportedMarkdown(
      title: title,
      description: description,
      body: body,
    );
  }

  Future<void> _exportNote(Map<String, dynamic> note) async {
    try {
      final detail = note['content'] != null
          ? note
          : await _fetchNoteDetail(note['id'] as int);
      // Resolve category + sibling notes so the options dialog can show how
      // many notes a recursive export would include.
      final courseMap =
          Map<String, dynamic>.from(detail['course'] as Map? ?? const {});
      final courseId = courseMap['id'] as int?;
      final categoryTitle = courseMap['title']?.toString() ?? 'Category';
      final siblings = await _collectCategoryNotes(detail, courseId);

      if (!mounted) return;
      final options = await showDialog<_ExportOptions>(
        context: context,
        builder: (ctx) => _ExportOptionsDialog(
          noteTitle: detail['title']?.toString() ?? 'Untitled note',
          categoryTitle: categoryTitle,
          siblingCount: siblings.length,
        ),
      );
      if (options == null) return;

      final notesToExport = options.recursive ? siblings : [detail];
      // Compact timestamp YYYYMMDD-HHMMSS so the filename sorts
      // naturally in a file manager.
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final stamp = '${now.year}${two(now.month)}${two(now.day)}'
          '-${two(now.hour)}${two(now.minute)}${two(now.second)}';
      // UUID-prefix + timestamp for single-note exports; category
      // slug + timestamp for recursive exports so the user can tell
      // them apart on disk even with identical titles.
      String baseName;
      if (options.recursive) {
        final slug =
            _slugifyLocalText(categoryTitle, fallback: 'category');
        baseName = '$slug-$stamp';
      } else {
        final rawUuid = detail['uuid']?.toString() ?? '';
        final uuidPrefix = rawUuid.isNotEmpty
            ? rawUuid.replaceAll('-', '').substring(
                0, rawUuid.replaceAll('-', '').length >= 6 ? 6 : rawUuid.replaceAll('-', '').length)
            : 'local';
        baseName = 'note-$uuidPrefix-$stamp';
      }

      if (options.format == 'zip') {
        await _writeNotesAsZip(
          notes: notesToExport,
          baseName: baseName,
          includeMetadata: options.includeMetadata,
        );
      } else {
        await _writeNotesAsMarkdown(
          notes: notesToExport,
          baseName: baseName,
          includeMetadata: options.includeMetadata,
          combined: options.recursive,
        );
      }
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Returns the list of notes that share a category with [detail]. Falls back
  /// to the single note when no category info is available. Used by the export
  /// options dialog and the recursive export path.
  Future<List<Map<String, dynamic>>> _collectCategoryNotes(
      Map<String, dynamic> detail, int? courseId) async {
    if (courseId == null) {
      return [detail];
    }
    final local = _localDrafts
        .where((d) =>
            (Map<String, dynamic>.from(d['course'] as Map? ?? const {}))['id'] ==
            courseId)
        .map((d) => Map<String, dynamic>.from(d))
        .toList();
    List<Map<String, dynamic>> remote = const [];
    final token = _token;
    if (token != null && token.isNotEmpty && courseId >= 0) {
      try {
        final list = await widget.client.getCourseNotes(courseId, token: token);
        remote = [
          for (final n in list)
            n['content'] != null
                ? Map<String, dynamic>.from(n)
                : await _fetchNoteDetail(n['id'] as int),
        ];
      } catch (_) {
        remote = const [];
      }
    }
    final combined = <Map<String, dynamic>>[...local, ...remote];
    // Deduplicate by id, keep the richer (with content) version.
    final byId = <dynamic, Map<String, dynamic>>{};
    for (final n in combined) {
      final id = n['id'];
      if (!byId.containsKey(id) ||
          (byId[id]!['content'] == null && n['content'] != null)) {
        byId[id] = n;
      }
    }
    final result = byId.values.toList();
    if (result.isEmpty) result.add(detail);
    return result;
  }

  /// Builds YAML frontmatter block prepended to exported markdown when the
  /// user opts in to metadata.
  String _frontmatterForNote(Map<String, dynamic> note) {
    final author =
        Map<String, dynamic>.from(note['author'] as Map? ?? const {});
    final course =
        Map<String, dynamic>.from(note['course'] as Map? ?? const {});
    final buffer = StringBuffer('---\n');
    buffer.writeln('title: ${_yamlEscape(note['title']?.toString() ?? '')}');
    if ((author['username']?.toString() ?? '').isNotEmpty) {
      buffer.writeln('author: ${_yamlEscape(author['username'].toString())}');
    }
    if ((course['title']?.toString() ?? '').isNotEmpty) {
      buffer.writeln('category: ${_yamlEscape(course['title'].toString())}');
    }
    if ((note['last_edit']?.toString() ?? '').isNotEmpty) {
      buffer.writeln('last_edit: ${note['last_edit']}');
    }
    if ((note['description']?.toString() ?? '').isNotEmpty) {
      buffer.writeln(
          'description: ${_yamlEscape(note['description'].toString())}');
    }
    buffer.writeln('---');
    return buffer.toString();
  }

  String _yamlEscape(String value) {
    if (value.contains(':') || value.contains('#') || value.contains('\n')) {
      return '"${value.replaceAll('"', '\\"').replaceAll('\n', ' ')}"';
    }
    return value;
  }

  String _noteMarkdownBody(Map<String, dynamic> note) {
    return note['content']?.toString() ?? _noteToMarkdown(note);
  }

  /// Writes notes as a markdown file. When [combined] is true, all notes are
  /// concatenated with `---` separators into a single file.
  Future<void> _writeNotesAsMarkdown({
    required List<Map<String, dynamic>> notes,
    required String baseName,
    required bool includeMetadata,
    required bool combined,
  }) async {
    final location = await getSaveLocation(
      suggestedName: '$baseName.md',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Markdown', extensions: ['md']),
      ],
    );
    if (location == null) return;
    final buffer = StringBuffer();
    for (var i = 0; i < notes.length; i++) {
      final note = notes[i];
      if (includeMetadata) {
        buffer.writeln(_frontmatterForNote(note));
        buffer.writeln();
      }
      buffer.writeln(_noteMarkdownBody(note));
      if (combined && i < notes.length - 1) {
        buffer.writeln();
        buffer.writeln('---');
        buffer.writeln();
      }
    }
    final bytes = Uint8List.fromList(utf8.encode(buffer.toString()));
    final file = XFile.fromData(bytes,
        name: '$baseName.md', mimeType: 'text/markdown');
    await file.saveTo(location.path);
    _showMessage('Exported ${notes.length} note(s) to ${location.path}.');
  }

  /// Writes notes as a zip archive where each note becomes a separate .md.
  Future<void> _writeNotesAsZip({
    required List<Map<String, dynamic>> notes,
    required String baseName,
    required bool includeMetadata,
  }) async {
    final location = await getSaveLocation(
      suggestedName: '$baseName.zip',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Zip archive', extensions: ['zip']),
      ],
    );
    if (location == null) return;
    final archive = Archive();
    final seen = <String>{};
    for (final note in notes) {
      final title = note['title']?.toString() ?? 'Untitled note';
      var slug = _slugifyLocalText(title, fallback: 'note');
      var finalSlug = slug;
      var counter = 1;
      while (seen.contains('$finalSlug.md')) {
        counter += 1;
        finalSlug = '$slug-$counter';
      }
      seen.add('$finalSlug.md');
      final buffer = StringBuffer();
      if (includeMetadata) {
        buffer.writeln(_frontmatterForNote(note));
        buffer.writeln();
      }
      buffer.writeln(_noteMarkdownBody(note));
      final data = utf8.encode(buffer.toString());
      archive.addFile(ArchiveFile('$finalSlug.md', data.length, data));
    }
    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) {
      _showMessage('Failed to encode zip archive.');
      return;
    }
    final file = XFile.fromData(Uint8List.fromList(zipData),
        name: '$baseName.zip', mimeType: 'application/zip');
    await file.saveTo(location.path);
    _showMessage('Exported ${notes.length} note(s) to ${location.path}.');
  }
}
