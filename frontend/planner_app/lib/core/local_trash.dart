part of notechondria_frontend;

/// Client-side recycle-bin for drafts and courses successfully synced
/// to the cloud. See editor_app/lib/core/local_trash.dart for the
/// full contract. State fields live on `_AppShellState` in
/// `app_shell.dart`; this extension holds the read/write logic so
/// `app_shell.dart` stays under the AGENTS.md §1.5 1000-line ceiling.
extension _AppShellLocalTrashX on _AppShellState {
  Future<void> _persistLocalTrashedDrafts() async {
    await _LocalAppStore.saveTrashedDrafts(_localTrashedDrafts);
  }

  Future<void> _persistLocalTrashedCourses() async {
    await _LocalAppStore.saveTrashedCourses(_localTrashedCourses);
  }

  Future<void> _moveDraftToLocalTrash(
    Map<String, dynamic> draft, {
    int? serverNoteId,
    String? serverNoteUuid,
  }) async {
    final entry = {
      'draft': Map<String, dynamic>.from(draft),
      'trashed_at': DateTime.now().toUtc().toIso8601String(),
      if (serverNoteId != null) 'server_note_id': serverNoteId,
      if (serverNoteUuid != null && serverNoteUuid.isNotEmpty)
        'server_note_uuid': serverNoteUuid,
    };
    _localTrashedDrafts = [entry, ..._localTrashedDrafts];
    await _persistLocalTrashedDrafts();
  }

  Future<void> _moveCourseToLocalTrash(
    Map<String, dynamic> course, {
    int? serverCourseId,
  }) async {
    final entry = {
      'course': Map<String, dynamic>.from(course),
      'trashed_at': DateTime.now().toUtc().toIso8601String(),
      if (serverCourseId != null) 'server_course_id': serverCourseId,
    };
    _localTrashedCourses = [entry, ..._localTrashedCourses];
    await _persistLocalTrashedCourses();
  }

  Future<ActionFeedback> _restoreTrashedDraft(
      Map<String, dynamic> entry) async {
    final raw = entry['draft'];
    if (raw is! Map) {
      return const ActionFeedback(
        message: 'Draft not restored: '
            'Planner.LocalStore/restore_trashed_draft \u2014 '
            'recycle-bin entry was missing its draft payload.',
        isError: true,
      );
    }
    final restored = {
      ...Map<String, dynamic>.from(raw),
      'id': _LocalAppStore.newDraftId(),
      'last_edit': DateTime.now().toUtc().toIso8601String(),
    };
    _localDrafts = [..._localDrafts, restored];
    _localTrashedDrafts = _localTrashedDrafts
        .where((item) => item != entry)
        .toList(growable: false);
    await _persistLocalDrafts();
    await _persistLocalTrashedDrafts();
    _trashRefresh();
    final title = restored['title']?.toString() ?? 'draft';
    log(
      level: DebugLogLevel.info,
      source: 'Planner.LocalStore/restore_trashed_draft',
      message:
          'Draft restored from local recycle bin: '
          'Planner.LocalStore/restore_trashed_draft \u2014 '
          "'$title' re-added as a local draft; cloud copy left untouched.",
    );
    return ActionFeedback(
      message:
          'Draft restored: Planner.LocalStore/restore_trashed_draft \u2014 '
          "'$title' is back. The cloud copy was not touched.",
    );
  }

  Future<ActionFeedback> _restoreTrashedCourse(
      Map<String, dynamic> entry) async {
    final raw = entry['course'];
    if (raw is! Map) {
      return const ActionFeedback(
        message: 'Category not restored: '
            'Planner.LocalStore/restore_trashed_course \u2014 '
            'recycle-bin entry was missing its course payload.',
        isError: true,
      );
    }
    final restored = {
      ...Map<String, dynamic>.from(raw),
      'id': _LocalAppStore.newCourseId(),
      'last_edit': DateTime.now().toUtc().toIso8601String(),
    };
    _localCourses = [..._localCourses, restored];
    _localTrashedCourses = _localTrashedCourses
        .where((item) => item != entry)
        .toList(growable: false);
    await _persistLocalCourses();
    await _persistLocalTrashedCourses();
    _trashRefresh();
    final title = restored['title']?.toString() ?? 'category';
    log(
      level: DebugLogLevel.info,
      source: 'Planner.LocalStore/restore_trashed_course',
      message:
          'Category restored from local recycle bin: '
          'Planner.LocalStore/restore_trashed_course \u2014 '
          "'$title' re-added as a local category; cloud copy left untouched.",
    );
    return ActionFeedback(
      message:
          'Category restored: Planner.LocalStore/restore_trashed_course \u2014 '
          "'$title' is back. The cloud copy was not touched.",
    );
  }

  Future<void> _openLocalRecycleBinDialog() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, rebuild) {
          final drafts = List<Map<String, dynamic>>.from(_localTrashedDrafts);
          final courses =
              List<Map<String, dynamic>>.from(_localTrashedCourses);
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.7,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                    child: Text(
                      'Local recycle bin',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      'Drafts and categories kept here for 30 days after a '
                      'successful cloud sync.',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        if (drafts.isEmpty && courses.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(
                              child: Text(
                                'Nothing in the local recycle bin yet.',
                              ),
                            ),
                          ),
                        for (final entry in drafts)
                          ListTile(
                            leading: const Icon(Icons.description_outlined),
                            title: Text(
                              (entry['draft']
                                          as Map?)?['title']
                                      ?.toString() ??
                                  'Untitled draft',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              'Draft \u00b7 trashed ${_formatTrashedAt(entry['trashed_at'])}',
                            ),
                            trailing: TextButton.icon(
                              icon: const Icon(Icons.restore),
                              label: const Text('Restore'),
                              onPressed: () async {
                                final feedback =
                                    await _restoreTrashedDraft(entry);
                                if (mounted) showMessage(feedback.message);
                                if (ctx.mounted) rebuild(() {});
                              },
                            ),
                          ),
                        for (final entry in courses)
                          ListTile(
                            leading: const Icon(Icons.folder_outlined),
                            title: Text(
                              (entry['course']
                                          as Map?)?['title']
                                      ?.toString() ??
                                  'Untitled category',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              'Category \u00b7 trashed ${_formatTrashedAt(entry['trashed_at'])}',
                            ),
                            trailing: TextButton.icon(
                              icon: const Icon(Icons.restore),
                              label: const Text('Restore'),
                              onPressed: () async {
                                final feedback =
                                    await _restoreTrashedCourse(entry);
                                if (mounted) showMessage(feedback.message);
                                if (ctx.mounted) rebuild(() {});
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  String _formatTrashedAt(Object? raw) {
    final text = raw?.toString();
    if (text == null || text.isEmpty) return 'recently';
    final when = DateTime.tryParse(text)?.toLocal();
    if (when == null) return text;
    final now = DateTime.now();
    final delta = now.difference(when);
    if (delta.inMinutes < 2) return 'just now';
    if (delta.inHours < 1) return '${delta.inMinutes}m ago';
    if (delta.inDays < 1) return '${delta.inHours}h ago';
    if (delta.inDays < 30) return '${delta.inDays}d ago';
    return text.substring(0, 10);
  }
}
