part of notechondria_frontend;

/// Draft sync + pull-from-cloud helpers. `_pullCloudNotesToLocal` is
/// the manual pull flow with the conflict-dialog UI; `_syncLocalDraft`
/// is the push flow used after a draft is saved offline. `_sameNoteTitle`
/// and `_buildPulledLocalDraft` are small helpers consumed by both.
/// State mutations route through `_refresh()` since extensions can't
/// call `setState` directly. Extracted from `app_shell.dart` so that
/// file stays closer to the AGENTS.md §1.5 1000-line ceiling.
extension _AppShellDraftSyncX on _AppShellState {
  bool _sameNoteTitle(Map<String, dynamic> left, Map<String, dynamic> right) {
    final leftTitle = left['title']?.toString().trim().toLowerCase() ?? '';
    final rightTitle = right['title']?.toString().trim().toLowerCase() ?? '';
    return leftTitle.isNotEmpty && leftTitle == rightTitle;
  }

  Map<String, dynamic> _buildPulledLocalDraft(
    Map<String, dynamic> note, {
    Map<String, dynamic>? existingDraft,
  }) {
    final sourceAccount =
        _profile?['username']?.toString().trim().isNotEmpty == true
            ? _profile!['username'].toString().trim()
            : _profile?['email']?.toString().trim() ?? '';
    final metadata = {
      ..._decodeNoteMetadata(note['metadata_json']?.toString() ?? '{}'),
      'pulled_from_cloud_note_id': note['id'],
      'pulled_from_account': sourceAccount,
      'is_cloud_copy': true,
      'source_note_last_edit': note['last_edit']?.toString(),
    };
    return _buildLocalDraft(
      id: (existingDraft?['id'] as num?)?.toInt(),
      clientDraftId: existingDraft?['client_draft_id']?.toString(),
      createdAt: existingDraft?['date_created']?.toString() ??
          note['date_created']?.toString(),
      title: note['title']?.toString() ?? 'Untitled note',
      description: note['description']?.toString() ??
          note['excerpt']?.toString() ??
          '',
      content: note['content']?.toString() ?? _noteToMarkdown(note),
      editorMode: note['editor_mode']?.toString() ??
          existingDraft?['editor_mode']?.toString() ??
          'P',
      metadataJson: jsonEncode(metadata),
    );
  }

  Future<String?> _showPullConflictDialog({
    required Map<String, dynamic> localDraft,
    required Map<String, dynamic> remoteNote,
  }) async {
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resolve note conflict'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A local note and a cloud note share the title "${remoteNote['title'] ?? 'Untitled note'}".',
              ),
              const SizedBox(height: 16),
              Text('Local',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                localDraft['description']?.toString().isNotEmpty == true
                    ? localDraft['description'].toString()
                    : _excerptFromMarkdown(
                        localDraft['content']?.toString() ?? ''),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Text('Cloud',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                remoteNote['description']?.toString().isNotEmpty == true
                    ? remoteNote['description'].toString()
                    : remoteNote['excerpt']?.toString() ?? '',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop('local'),
              child: const Text('Keep local')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop('cloud'),
              child: const Text('Use server')),
        ],
      ),
    );
  }

  Future<ActionFeedback> _pullCloudNotesToLocal() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return const ActionFeedback(
          message: 'Cloud notes not pulled: '
              'Editor.Sync.Notes/pull \u2014 '
              'no cloud session; sign in first.',
          isError: true);
    }
    try {
      final pulledDrafts = List<Map<String, dynamic>>.from(_localDrafts);
      var imported = 0;
      var updated = 0;
      var skipped = 0;
      var offset = 0;
      var hasMore = true;
      while (hasMore) {
        final page = await widget.client
            .listNotes(token: token, offset: offset, limit: 50);
        final rows = (page['results'] as List<dynamic>? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
        hasMore = page['has_more'] == true && rows.isNotEmpty;
        offset += rows.length;
        for (final summary in rows) {
          final noteId = (summary['id'] as num?)?.toInt();
          if (noteId == null) continue;
          final detail =
              await widget.client.getNoteDetail(noteId, token: token);
          final pulledIndex = pulledDrafts.indexWhere((draft) {
            final metadata = _decodeNoteMetadata(
                draft['metadata_json']?.toString() ?? '{}');
            return (metadata['pulled_from_cloud_note_id'] as num?)
                    ?.toInt() ==
                noteId;
          });
          if (pulledIndex >= 0) {
            pulledDrafts[pulledIndex] = _buildPulledLocalDraft(detail,
                existingDraft: pulledDrafts[pulledIndex]);
            updated += 1;
            continue;
          }
          final conflictIndex = pulledDrafts
              .indexWhere((draft) => _sameNoteTitle(draft, detail));
          if (conflictIndex >= 0) {
            final decision = await _showPullConflictDialog(
                localDraft: pulledDrafts[conflictIndex],
                remoteNote: detail);
            if (!mounted) {
              return const ActionFeedback(
                  message: 'Cloud notes pull cancelled: '
                      'Editor.Sync.Notes/pull \u2014 '
                      'widget unmounted during conflict dialog.',
                  isError: true);
            }
            if (decision != 'cloud') {
              skipped += 1;
              continue;
            }
            pulledDrafts[conflictIndex] = _buildPulledLocalDraft(detail,
                existingDraft: pulledDrafts[conflictIndex]);
            updated += 1;
            continue;
          }
          pulledDrafts.insert(0, _buildPulledLocalDraft(detail));
          imported += 1;
        }
      }
      _localDrafts = List<Map<String, dynamic>>.unmodifiable(pulledDrafts);
      _localStats = {
        ..._localStats,
        'cloud_notes_pulled':
            ((_localStats['cloud_notes_pulled'] as num?)?.toInt() ?? 0) +
                imported +
                updated,
        'last_pull_at': DateTime.now().toUtc().toIso8601String(),
      };
      await _persistLocalDrafts();
      await _persistLocalStats();
      // Refresh remote courses and notes so the full cloud state is visible.
      await _loadInitialData();
      if (mounted) _refresh();
      final segments = <String>[];
      if (imported > 0) segments.add('imported $imported');
      if (updated > 0) segments.add('updated $updated');
      if (skipped > 0) segments.add('kept $skipped local');
      final summary = segments.isEmpty
          ? 'local copies already match the cloud'
          : segments.join(', ');
      _log(
        level: DebugLogLevel.info,
        source: 'Editor.Sync.Notes/pull',
        message:
            'Cloud notes pulled: Editor.Sync.Notes/pull \u2014 $summary.',
      );
      return ActionFeedback(
          message: 'Cloud notes pulled: '
              'Editor.Sync.Notes/pull \u2014 $summary.');
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      _log(
        level: DebugLogLevel.error,
        source: 'Editor.Sync.Notes/pull',
        message: 'Cloud notes not pulled: '
            'Editor.Sync.Notes/pull \u2014 $cause.',
      );
      return ActionFeedback(
          message: 'Cloud notes not pulled: '
              'Editor.Sync.Notes/pull \u2014 $cause.',
          isError: true);
    }
  }

  Future<Map<String, dynamic>> _syncLocalDraft(
      Map<String, dynamic> draft) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception(
        'Local draft not synced: '
        'Editor.Sync.Notes/push \u2014 '
        'no cloud session; sign in first.',
      );
    }
    var metadata =
        _decodeNoteMetadata(draft['metadata_json']?.toString() ?? '{}');
    final assignedCourseId = (metadata['course_id'] as num?)?.toInt();
    if (assignedCourseId != null && assignedCourseId < 0) {
      Map<String, dynamic>? localCourse;
      for (final item in _localCourses) {
        if ((item['id'] as num?)?.toInt() == assignedCourseId) {
          localCourse = item;
          break;
        }
      }
      if (localCourse != null) {
        final syncedCourse = await _syncLocalCourse(localCourse);
        metadata = {...metadata, 'course_id': syncedCourse['id']};
        draft = _remapDraftCourseId(
            draft, assignedCourseId, syncedCourse['id'] as int);
      }
    }
    final pulledFromNoteId =
        (metadata['pulled_from_cloud_note_id'] as num?)?.toInt();
    final pulledFromAccount =
        metadata['pulled_from_account']?.toString().trim().toLowerCase() ??
            '';
    final currentAccount =
        (_profile?['username']?.toString().trim().isNotEmpty == true
                ? _profile!['username'].toString().trim()
                : _profile?['email']?.toString().trim() ?? '')
            .toLowerCase();
    if (pulledFromNoteId != null &&
        pulledFromNoteId > 0 &&
        pulledFromAccount.isNotEmpty &&
        pulledFromAccount == currentAccount) {
      final updated =
          await widget.client.updateNote(token, pulledFromNoteId, {
        'title': draft['title'],
        'description': draft['description'] ?? '',
        'content': draft['content'] ?? '',
        'editor_mode': draft['editor_mode'] ?? 'P',
        'course_id': metadata['course_id'],
        'metadata_json': jsonEncode(metadata),
        'is_public': false,
      });
      _localDrafts = _localDrafts
          .map((item) => item['id'] == draft['id']
              ? {
                  ...draft,
                  'last_edit': updated['last_edit'] ?? draft['last_edit'],
                  'metadata_json': jsonEncode({
                    ...metadata,
                    'source_note_last_edit': updated['last_edit'],
                  }),
                }
              : item)
          .toList(growable: false);
      _localStats = {
        ..._localStats,
        'local_drafts_synced':
            ((_localStats['local_drafts_synced'] as num?)?.toInt() ?? 0) + 1,
        'last_sync_at': DateTime.now().toUtc().toIso8601String(),
      };
      await _persistLocalDrafts();
      await _persistLocalStats();
      await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
      if (mounted) _refresh();
      _log(
        level: DebugLogLevel.info,
        source: 'Editor.Sync.Notes/push',
        message:
            "Local cloud-copy draft synced: "
            "Editor.Sync.Notes/push \u2014 "
            "'${draft['title']}' upstream note updated in place.",
      );
      return _promoteQueuedAttachments(updated, metadata);
    }
    final syncCourseId = (metadata['course_id'] as num?)?.toInt();
    final syncClientDraftId = draft['client_draft_id']?.toString();
    final created = await widget.client.createNote(token, <String, dynamic>{
      'title': draft['title'] ?? 'Untitled note',
      'description': draft['description'] ?? '',
      'content': draft['content'] ?? '',
      'editor_mode': draft['editor_mode'] ?? 'P',
      if (syncCourseId != null && syncCourseId > 0) 'course_id': syncCourseId,
      'metadata_json': jsonEncode(metadata),
      if (syncClientDraftId != null && syncClientDraftId.isNotEmpty)
        'client_draft_id': syncClientDraftId,
      'is_public': false,
    });
    _localDrafts = _localDrafts
        .where((item) => item['id'] != draft['id'])
        .toList(growable: false);
    // Stash the just-synced draft in the local recycle bin so the
    // user can restore if the cloud copy turns out wrong later.
    // Auto-pruned after 30 days. See _moveDraftToLocalTrash /
    // _LocalAppStore._pruneTrashed.
    await _moveDraftToLocalTrash(
      draft,
      serverNoteId: (created['id'] as num?)?.toInt(),
      serverNoteUuid: created['uuid']?.toString(),
    );
    _localStats = {
      ..._localStats,
      'local_drafts_synced':
          ((_localStats['local_drafts_synced'] as num?)?.toInt() ?? 0) + 1,
      'last_sync_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _persistLocalDrafts();
    await _persistLocalStats();
    await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
    if (mounted) _refresh();
    _log(
      level: DebugLogLevel.info,
      source: 'Editor.Sync.Notes/push',
      message:
          "Local draft synced: Editor.Sync.Notes/push \u2014 "
          "'${draft['title']}' created on server; local draft moved to "
          "client-side recycle bin (restore from Settings).",
    );
    return _promoteQueuedAttachments(created, metadata);
  }
}
