part of notechondria_frontend;

/// Note CRUD + import/export.
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
      refreshState();
      return draft;
    }
    final payload = {
      'title': title ?? _extractTitleFromMarkdown(initialMarkdown),
      'description': description ?? _excerptFromMarkdown(initialMarkdown),
      'content': initialMarkdown,
      'editor_mode': mode,
      'course_id': null,
      'client_draft_id': clientDraftId,
      'metadata_json': jsonEncode({'section': '', 'autosave': false}),
    };
    try {
      final created = await widget.client.createNote(token, payload);
      await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
        _selectedNote = created;
        _selectedIndex = 1;
      refreshState();
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
      refreshState();
      log(
        level: DebugLogLevel.warning,
        source: 'Portal.Sync.Notes/create',
        message:
            'Note saved locally, cloud create deferred: '
            'Portal.Sync.Notes/create \u2014 $cause.',
      );
      showMessage(
        'Note saved locally: Portal.Sync.Notes/create \u2014 '
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
      if (existing.isEmpty) {
        throw Exception(
          'Local draft not found: '
          'Portal.Sync.Notes/save_local \u2014 '
          'no local draft matches the requested id.',
        );
      }
      final updated = _buildLocalDraft(
        id: noteId,
        title: payload['title']?.toString() ?? existing['title']?.toString() ?? 'Untitled note',
        description:
            payload['description']?.toString() ?? existing['description']?.toString() ?? '',
        content: payload['content']?.toString() ?? existing['content']?.toString() ?? '',
        editorMode: payload['editor_mode']?.toString() ??
            existing['editor_mode']?.toString() ??
            'P',
        clientDraftId: existing['client_draft_id']?.toString(),
        createdAt: existing['date_created']?.toString(),
        metadataJson:
            payload['metadata_json']?.toString() ?? existing['metadata_json']?.toString() ?? '{}',
      );
      _localDrafts = _localDrafts
          .map((item) => item['id'] == noteId ? updated : item)
          .toList(growable: false);
      await _persistLocalDrafts();
        _selectedNote = updated;
      refreshState();
      return updated;
    }
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception(
        'Note not saved: '
        'Portal.Sync.Notes/save \u2014 '
        'no cloud session; sign in first.',
      );
    }
    try {
      final updated = await widget.client.updateNote(token, noteId, payload);
      await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
        _selectedNote = updated;
      refreshState();
      return updated;
    } catch (error) {
      final sourceNote = _selectedNote?['id'] == noteId
          ? Map<String, dynamic>.from(_selectedNote!)
          : null;
      final fallbackDraft = _storeLocalDraft(
        _buildOfflineFallbackDraft(
          sourceNote: sourceNote,
          payload: payload,
        ),
      );
      await _persistLocalDrafts();
      final message = error.toString().replaceFirst('Exception: ', '');
        _selectedNote = fallbackDraft;
      refreshState();
      log(
        level: DebugLogLevel.warning,
        source: 'Portal.Sync.Notes/save',
        message:
            'Note save deferred to local draft: '
            'Portal.Sync.Notes/save \u2014 $message.',
      );
      showMessage(
        'Note saved locally: Portal.Sync.Notes/save \u2014 '
        'backend unavailable ($message); changes kept as a local draft.',
      );
      return fallbackDraft;
    }
  }

  Future<List<Map<String, dynamic>>> _getNoteHistory(int noteId) async {
    final token = _token;
    if (token == null || token.isEmpty || noteId < 0) {
      return const [];
    }
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
      throw Exception(
        'Note version not restored: '
        'Portal.Sync.Notes/restore_version \u2014 '
        'no cloud session or note is local-only; sign in first.',
      );
    }
    final restored =
        await widget.client.restoreNoteVersion(token, noteId, versionId);
    await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
      _selectedNote = restored;
    refreshState();
    return restored;
  }

  Future<void> _importMarkdownNote() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
              label: 'Markdown', extensions: ['md', 'markdown', 'txt']),
        ],
      );
      if (file == null) {
        return;
      }
      final contents = await file.readAsString();
      final created = await _createNote(
        markdown: contents,
        title: _extractTitleFromMarkdown(contents),
        description: '',
      );
      showMessage("Imported '${created['title']}'.");
    } catch (error) {
      showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _exportNote(Map<String, dynamic> note) async {
    try {
      final detail = note['content'] != null
          ? note
          : await _fetchNoteDetail(note['id'] as int);
      final location = await getSaveLocation(
        suggestedName: '${detail['title'] ?? 'note'}.md',
        acceptedTypeGroups: [
          const XTypeGroup(label: 'Markdown', extensions: ['md']),
        ],
      );
      if (location == null) {
        return;
      }
      final bytes = Uint8List.fromList(utf8
          .encode(detail['content']?.toString() ?? _noteToMarkdown(detail)));
      final file = XFile.fromData(bytes,
          name: '${detail['title'] ?? 'note'}.md', mimeType: 'text/markdown');
      await file.saveTo(location.path);
      showMessage("Exported '${detail['title'] ?? 'note'}'.");
    } catch (error) {
      showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }
}
