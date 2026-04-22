part of notechondria_frontend;

/// Offline draft store-and-fallback helpers. Both methods live just
/// outside the `setState` boundary: `_storeLocalDraft` updates the
/// in-memory `_localDrafts` list (callers either call `setState`
/// themselves or persist + rebuild afterward), and
/// `_buildOfflineFallbackDraft` is a pure constructor over
/// `_localDrafts` for the offline-create and offline-update paths.
/// Extracted from `app_shell.dart` so that file stays closer to the
/// AGENTS.md §1.5 1000-line ceiling.
extension _AppShellDraftHelpersX on _AppShellState {
  Map<String, dynamic> _storeLocalDraft(
    Map<String, dynamic> draft, {
    bool incrementCreated = false,
  }) {
    final existingIndex =
        _localDrafts.indexWhere((item) => item['id'] == draft['id']);
    final nextDrafts = List<Map<String, dynamic>>.from(_localDrafts);
    if (existingIndex >= 0) {
      nextDrafts[existingIndex] = draft;
      nextDrafts.insert(0, nextDrafts.removeAt(existingIndex));
    } else {
      nextDrafts.insert(0, draft);
    }
    _localDrafts = List<Map<String, dynamic>>.unmodifiable(nextDrafts);
    if (incrementCreated) {
      _localStats = {
        ..._localStats,
        'local_drafts_created':
            ((_localStats['local_drafts_created'] as num?)?.toInt() ?? 0) + 1,
      };
    }
    return draft;
  }

  Map<String, dynamic> _buildOfflineFallbackDraft({
    Map<String, dynamic>? sourceNote,
    required Map<String, dynamic> payload,
  }) {
    final sourceId = (sourceNote?['id'] as num?)?.toInt();
    final existingIndex = sourceId == null
        ? -1
        : _localDrafts.indexWhere((item) {
            final metadata = _decodeNoteMetadata(
                item['metadata_json']?.toString() ?? '{}');
            return (metadata['offline_source_note_id'] as num?)?.toInt() ==
                sourceId;
          });
    final existingDraft = existingIndex >= 0
        ? Map<String, dynamic>.from(_localDrafts[existingIndex])
        : null;
    final metadata = _decodeNoteMetadata(
      payload['metadata_json']?.toString() ??
          sourceNote?['metadata_json']?.toString() ??
          '{}',
    );
    if (sourceId != null) {
      metadata['offline_source_note_id'] = sourceId;
    }
    return _buildLocalDraft(
      id: (existingDraft?['id'] as num?)?.toInt(),
      clientDraftId: existingDraft?['client_draft_id']?.toString(),
      createdAt: existingDraft?['date_created']?.toString() ??
          sourceNote?['date_created']?.toString(),
      title: payload['title']?.toString() ??
          sourceNote?['title']?.toString() ??
          'Untitled note',
      description: payload['description']?.toString() ??
          sourceNote?['description']?.toString() ??
          '',
      content: payload['content']?.toString() ??
          sourceNote?['content']?.toString() ??
          '# Untitled note\n\n',
      editorMode: payload['editor_mode']?.toString() ??
          sourceNote?['editor_mode']?.toString() ??
          'P',
      metadataJson: jsonEncode(metadata),
    );
  }
}
