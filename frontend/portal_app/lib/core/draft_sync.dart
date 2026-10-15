part of notechondria_frontend;

/// Draft pull-from-cloud.
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
      description:
          note['description']?.toString() ?? note['excerpt']?.toString() ?? '',
      content: note['content']?.toString() ?? _noteToMarkdown(note),
      editorMode: note['editor_mode']?.toString() ??
          existingDraft?['editor_mode']?.toString() ??
          'P',
      metadataJson: jsonEncode(metadata),
      author: note['author'] is Map
          ? Map<String, dynamic>.from(note['author'] as Map)
          : null,
    );
  }

  Future<String?> _showPullConflictDialog({
    required Map<String, dynamic> localDraft,
    required Map<String, dynamic> remoteNote,
  }) async {
    if (!mounted) {
      return null;
    }
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resolve note conflict'),
        content: SizedBox(
          width: (MediaQuery.of(context).size.width - 80).clamp(280.0, 640.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A local note and a cloud note share the title '
                '"${remoteNote['title'] ?? 'Untitled note'}". Review the '
                'differences below, then choose which version to keep.',
              ),
              const SizedBox(height: 12),
              // #31: git-diff-style side-by-side (local vs cloud) so the
              // user sees exactly what changed, not just a per-side summary.
              NoteConflictDiffView(
                localContent: localDraft['content']?.toString() ?? '',
                remoteContent: remoteNote['content']?.toString() ??
                    _noteToMarkdown(remoteNote),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('local'),
            child: const Text('Keep local'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('cloud'),
            child: const Text('Use server'),
          ),
        ],
      ),
    );
  }

  Future<ActionFeedback> _pullCloudNotesToLocal() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return const ActionFeedback(
        message: 'Cloud notes not pulled: '
            'Portal.Sync.Notes/pull \u2014 '
            'no cloud session; sign in first.',
        isError: true,
      );
    }
    try {
      final pulledDrafts = List<Map<String, dynamic>>.from(_localDrafts);
      var imported = 0;
      var updated = 0;
      var skipped = 0;
      var offset = 0;
      var hasMore = true;
      while (hasMore) {
        final page = await widget.client.listNotes(
          token: token,
          offset: offset,
          limit: 50,
        );
        final rows = (page['results'] as List<dynamic>? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
        hasMore = page['has_more'] == true && rows.isNotEmpty;
        offset += rows.length;
        for (final summary in rows) {
          final noteId = (summary['id'] as num?)?.toInt();
          if (noteId == null) {
            continue;
          }
          final detail =
              await widget.client.getNoteDetail(noteId, token: token);
          final pulledIndex = pulledDrafts.indexWhere((draft) {
            final metadata =
                _decodeNoteMetadata(draft['metadata_json']?.toString() ?? '{}');
            return (metadata['pulled_from_cloud_note_id'] as num?)?.toInt() ==
                noteId;
          });
          if (pulledIndex >= 0) {
            pulledDrafts[pulledIndex] = _buildPulledLocalDraft(
              detail,
              existingDraft: pulledDrafts[pulledIndex],
            );
            updated += 1;
            continue;
          }
          final conflictIndex =
              pulledDrafts.indexWhere((draft) => _sameNoteTitle(draft, detail));
          if (conflictIndex >= 0) {
            final decision = await _showPullConflictDialog(
              localDraft: pulledDrafts[conflictIndex],
              remoteNote: detail,
            );
            if (!mounted) {
              return const ActionFeedback(
                message: 'Cloud notes pull cancelled: '
                    'Portal.Sync.Notes/pull \u2014 '
                    'widget unmounted during conflict dialog.',
                isError: true,
              );
            }
            if (decision != 'cloud') {
              skipped += 1;
              continue;
            }
            pulledDrafts[conflictIndex] = _buildPulledLocalDraft(
              detail,
              existingDraft: pulledDrafts[conflictIndex],
            );
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
      await persistLocalDrafts();
      await persistLocalStats();
      if (mounted) {
        refreshState();
      }
      final segments = <String>[];
      if (imported > 0) {
        segments.add('imported $imported');
      }
      if (updated > 0) {
        segments.add('updated $updated');
      }
      if (skipped > 0) {
        segments.add('kept $skipped local');
      }
      final summary = segments.isEmpty
          ? 'local copies already match the cloud'
          : segments.join(', ');
      log(
        level: DebugLogLevel.info,
        source: 'Portal.Sync.Notes/pull',
        message: 'Cloud notes pulled: Portal.Sync.Notes/pull \u2014 $summary.',
      );
      return ActionFeedback(
          message: 'Cloud notes pulled: '
              'Portal.Sync.Notes/pull \u2014 $summary.');
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      log(
        level: DebugLogLevel.error,
        source: 'Portal.Sync.Notes/pull',
        message: 'Cloud notes not pulled: '
            'Portal.Sync.Notes/pull \u2014 $cause.',
      );
      return ActionFeedback(
          message: 'Cloud notes not pulled: '
              'Portal.Sync.Notes/pull \u2014 $cause.',
          isError: true);
    }
  }
}
