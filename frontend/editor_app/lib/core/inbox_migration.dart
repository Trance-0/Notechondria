part of notechondria_frontend;

class _InboxMigrationDecision {
  const _InboxMigrationDecision.moveToCategory(this.title)
      : removeCategory = false;

  const _InboxMigrationDecision.removeCategory()
      : title = '',
        removeCategory = true;

  final String title;
  final bool removeCategory;
}

extension _AppShellInboxMigrationX on _AppShellState {
  Future<void> _maybePromptInboxMigration() async {
    if (_inboxMigrationPromptShown || !mounted) return;
    final token = _token;
    if (token == null || token.isEmpty) return;
    final candidates = _ownedInboxMigrationCandidates();
    if (candidates.isEmpty) return;
    _inboxMigrationPromptShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(() async {
        final decision = await _chooseInboxMigration(candidates.length);
        if (decision == null) return;
        await _runInboxMigration(candidates, decision);
      }());
    });
  }

  List<Map<String, dynamic>> _ownedInboxMigrationCandidates() {
    final username = currentUsername?.trim().toLowerCase() ?? '';
    return [..._localCourses, ..._courses]
        .where((course) {
          final title = course['title']?.toString().trim().toLowerCase() ?? '';
          if (title != 'inbox') return false;
          if (isLocalCourse(course)) return true;
          if (username.isEmpty) return false;
          final owner = Map<String, dynamic>.from(
            course['owner'] as Map? ?? const {},
          );
          final ownerUsername =
              owner['username']?.toString().trim().toLowerCase() ?? '';
          return ownerUsername == username;
        })
        .map((course) => Map<String, dynamic>.from(course))
        .toList();
  }

  Future<_InboxMigrationDecision?> _chooseInboxMigration(int count) {
    final titleController = TextEditingController(text: 'Migrated Inbox');
    return showDialog<_InboxMigrationDecision>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Migrate legacy Inbox'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$count owned Inbox categor${count == 1 ? 'y' : 'ies'} '
                'were found. The editor now uses the uncategorized bucket '
                'for inbox-style notes, so these old categories can create '
                'duplicate Inbox rows.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'New category name',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(
              const _InboxMigrationDecision.removeCategory(),
            ),
            child: const Text('Remove category'),
          ),
          FilledButton(
            onPressed: () {
              final title = titleController.text.trim();
              if (title.isEmpty) return;
              Navigator.of(ctx).pop(
                _InboxMigrationDecision.moveToCategory(title),
              );
            },
            child: const Text('Move notes'),
          ),
        ],
      ),
    ).whenComplete(titleController.dispose);
  }

  Future<void> _runInboxMigration(
    List<Map<String, dynamic>> candidates,
    _InboxMigrationDecision decision,
  ) async {
    const source = 'Editor.DataMigration/inbox';
    final token = _token;
    if (token == null || token.isEmpty) return;
    try {
      log(
        level: DebugLogLevel.info,
        source: source,
        message:
            'Inbox migration started: $source - ${candidates.length} legacy '
            'Inbox categor${candidates.length == 1 ? 'y' : 'ies'} selected.',
      );
      final localIds = candidates
          .where(isLocalCourse)
          .map((course) => (course['id'] as num?)?.toInt())
          .whereType<int>()
          .toSet();
      final cloudIds = candidates
          .where((course) => !isLocalCourse(course))
          .map((course) => (course['id'] as num?)?.toInt())
          .whereType<int>()
          .toList(growable: false);

      int? targetCloudCourseId;
      Map<String, dynamic>? targetLocalCourse;
      if (!decision.removeCategory) {
        if (cloudIds.isNotEmpty) {
          final title = _uniqueInboxMigrationTitle(decision.title);
          final created = await timed(
            '$source.createCourse',
            () => widget.client.createCourse(token, {
              'title': title,
              'description': 'Migrated from legacy Inbox categories.',
            }),
          );
          final decorated = decorateRemoteCourse(created);
          targetCloudCourseId = (decorated['id'] as num?)?.toInt();
          _courses = [decorated, ..._courses];
          _selectedCourse = decorated;
        } else {
          targetLocalCourse = _buildLocalCourse(
            title: _uniqueInboxMigrationTitle(decision.title),
            description: 'Migrated from legacy Inbox categories.',
          );
          _localCourses = [targetLocalCourse, ..._localCourses];
          _selectedCourse = targetLocalCourse;
        }
      }

      if (localIds.isNotEmpty) {
        _localDrafts = _localDrafts.map((draft) {
          final courseId = _draftCourseId(draft);
          if (courseId == null || !localIds.contains(courseId)) return draft;
          final metadata =
              _decodeNoteMetadata(draft['metadata_json']?.toString() ?? '{}');
          if (decision.removeCategory) {
            metadata.remove('course_id');
          } else {
            metadata['course_id'] =
                targetCloudCourseId ?? targetLocalCourse?['id'];
          }
          return {
            ...draft,
            'course_id': metadata['course_id'],
            'metadata_json': jsonEncode(metadata),
          };
        }).toList(growable: false);
        _localCourses = _localCourses
            .where(
                (course) => !localIds.contains((course['id'] as num?)?.toInt()))
            .toList(growable: false);
        await persistLocalDrafts();
        await persistLocalCourses();
      }

      for (final courseId in cloudIds) {
        final notes = await timed(
          '$source.getCourseNotes.$courseId',
          () => widget.client.getCourseNotes(courseId, token: token),
        );
        if (!decision.removeCategory && targetCloudCourseId != null) {
          for (final note in notes) {
            final noteId = (note['id'] as num?)?.toInt();
            if (noteId == null) continue;
            await timed(
              '$source.updateNote.$noteId',
              () => widget.client.updateNote(
                token,
                noteId,
                {'course_id': targetCloudCourseId},
              ),
            );
          }
        }
        await timed(
          '$source.deleteCourse.$courseId',
          () => widget.client.deleteCourse(token, courseId),
        );
      }

      _courses = _courses
          .where(
              (course) => !cloudIds.contains((course['id'] as num?)?.toInt()))
          .toList(growable: false);
      if (decision.removeCategory) {
        _selectedCourse = null;
        _selectedCategoryId = null;
      }
      await _persistLocalCache();
      await _loadInitialData();
      final message = decision.removeCategory
          ? 'Inbox migration complete: old Inbox categories were removed; '
              'their notes now live in the uncategorized bucket.'
          : 'Inbox migration complete: old Inbox notes were moved to '
              '"${decision.title}" and the old Inbox categories were removed.';
      log(level: DebugLogLevel.info, source: source, message: message);
      showMessage(message);
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      final message = 'Inbox migration failed: $source - $cause.';
      log(level: DebugLogLevel.error, source: source, message: message);
      showMessage(message);
    }
  }

  String _uniqueInboxMigrationTitle(String raw) {
    final base = raw.trim().isEmpty ? 'Migrated Inbox' : raw.trim();
    final existing = [..._localCourses, ..._courses]
        .map((course) => course['title']?.toString().trim().toLowerCase() ?? '')
        .toSet();
    if (!existing.contains(base.toLowerCase())) return base;
    for (var i = 2; i < 100; i++) {
      final candidate = '$base $i';
      if (!existing.contains(candidate.toLowerCase())) return candidate;
    }
    return '$base ${DateTime.now().millisecondsSinceEpoch}';
  }
}
