part of notechondria_frontend;

/// Local course + draft builders.
extension _AppShellLocalCourseBuildersX on _AppShellState {
  Map<String, dynamic> _buildLocalCourse({
    required String title,
    String description = '',
    String? clientCourseId,
    String? createdAt,
    int? id,
  }) {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final effectiveTitle = title.trim().isEmpty ? 'Untitled course' : title.trim();
    final ownerLabel = _profile?['username']?.toString() ?? 'Local';
    return {
      'id': id ?? -DateTime.now().microsecondsSinceEpoch,
      'client_course_id': clientCourseId ?? _LocalAppStore.newCourseId(),
      'slug': _slugifyLocalText(effectiveTitle, fallback: 'local-course'),
      'title': effectiveTitle,
      'description': description.trim(),
      'cover_image_url': '',
      'is_default': false,
      'is_subscribed': false,
      'subscriber_count': 0,
      'last_opened_at': nowIso,
      'date_created': createdAt ?? nowIso,
      'last_edit': nowIso,
      'is_local_course': true,
      'is_owned': true,
      'owner': {
        'username': ownerLabel,
        'display_name': ownerLabel,
        'image_url': '',
      },
      'recent_notes': const <Map<String, dynamic>>[],
      'media': const <Map<String, dynamic>>[],
    };
  }

  Future<Map<String, dynamic>> _createLocalCourse(
    String title,
    String description,
  ) async {
    final course = _buildLocalCourse(title: title, description: description);
    _localCourses = [course, ..._localCourses];
    _localStats = {
      ..._localStats,
      'local_courses_created':
          ((_localStats['local_courses_created'] as num?)?.toInt() ?? 0) + 1,
    };
    await persistLocalCourses();
    await persistLocalStats();
      _selectedCourse = course;
      _selectedIndex = 2;
      _courseNotes = _localNotesForCourse(course);
    refreshState();
    log(
      level: DebugLogLevel.info,
      source: 'Portal.Sync.Courses/create_local',
      message:
          "Local course created: "
          "Portal.Sync.Courses/create_local \u2014 "
          "'${course['title']}' queued for sync on next sign-in.",
    );
    return course;
  }

  int? _draftCourseId(Map<String, dynamic> draft) {
    final metadata =
        _decodeNoteMetadata(draft['metadata_json']?.toString() ?? '{}');
    return (metadata['course_id'] as num?)?.toInt() ??
        (draft['course_id'] as num?)?.toInt();
  }

  Map<String, dynamic> _remapDraftCourseId(
    Map<String, dynamic> draft,
    int fromCourseId,
    int toCourseId,
  ) {
    final metadata =
        _decodeNoteMetadata(draft['metadata_json']?.toString() ?? '{}');
    if ((metadata['course_id'] as num?)?.toInt() == fromCourseId) {
      metadata['course_id'] = toCourseId;
    }
    return {
      ...draft,
      'course_id': toCourseId,
      'metadata_json': jsonEncode(metadata),
      'last_edit': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Future<Map<String, dynamic>> _syncLocalCourse(Map<String, dynamic> course) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception(
        'Local course not synced: '
        'Portal.Sync.Courses/push \u2014 '
        'no cloud session; sign in first.',
      );
    }
    final created = await widget.client.createCourse(token, {
      'title': course['title'],
      'description': course['description'] ?? '',
      'client_course_id': course['client_course_id'],
    });
    final localId = (course['id'] as num?)?.toInt();
    final remoteId = (created['id'] as num?)?.toInt();
    if (localId != null && remoteId != null) {
      _localDrafts = _localDrafts
          .map((draft) => _draftCourseId(draft) == localId
              ? _remapDraftCourseId(draft, localId, remoteId)
              : draft)
          .toList(growable: false);
    }
    final selectedCourseId = (_selectedCourse?['id'] as num?)?.toInt();
    _localCourses = _localCourses
        .where((item) => item['id'] != course['id'])
        .toList(growable: false);
    await _moveCourseToLocalTrash(course, serverCourseId: remoteId);
    _courses = [
      _decorateRemoteCourse(created),
      ..._courses.where((item) => item['id'] != created['id']),
    ];
    if (selectedCourseId != null && selectedCourseId == localId) {
      _selectedCourse = _decorateRemoteCourse(created);
      _courseNotes = const [];
    }
    _localStats = {
      ..._localStats,
      'local_courses_synced':
          ((_localStats['local_courses_synced'] as num?)?.toInt() ?? 0) + 1,
      'last_sync_at': DateTime.now().toUtc().toIso8601String(),
    };
    await persistLocalCourses();
    await persistLocalDrafts();
    await persistLocalStats();
    await _persistLocalCache();
    log(
      level: DebugLogLevel.info,
      source: 'Portal.Sync.Courses/push',
      message:
          "Local course synced: Portal.Sync.Courses/push \u2014 "
          "'${course['title']}' created on server; local ID remapped; "
          'local copy moved to client-side recycle bin.',
    );
    return created;
  }

  Map<String, dynamic> _buildLocalDraft({
    required String title,
    required String content,
    String description = '',
    String editorMode = 'P',
    String? clientDraftId,
    String? createdAt,
    int? id,
    String metadataJson = '{}',
  }) {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final effectiveTitle =
        title.trim().isEmpty ? _extractTitleFromMarkdown(content) : title.trim();
    final body = _bodyWithoutTitle(content);
    return {
      'id': id ?? -DateTime.now().microsecondsSinceEpoch,
      'client_draft_id': clientDraftId ?? _LocalAppStore.newDraftId(),
      'title': effectiveTitle,
      'description':
          description.isEmpty ? _excerptFromMarkdown(content) : description,
      'content': _composeMarkdown(effectiveTitle, body),
      'metadata_json': metadataJson,
      'preview_lines': body
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .take(3)
          .toList(),
      'editor_mode': editorMode,
      'is_public': false,
      'course_id': null,
      'date_created': createdAt ?? nowIso,
      'last_edit': nowIso,
      'is_local_draft': true,
      'author': {
        'username': 'Local Draft',
        'display_name': 'Local Draft',
        'image_url': '',
      },
    };
  }

  Future<Map<String, dynamic>> _syncLocalDraft(Map<String, dynamic> draft) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception(
        'Local draft not synced: '
        'Portal.Sync.Notes/push \u2014 '
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
        metadata = {
          ...metadata,
          'course_id': syncedCourse['id'],
        };
        draft = _remapDraftCourseId(
          draft,
          assignedCourseId,
          syncedCourse['id'] as int,
        );
      }
    }
    final pulledFromNoteId =
        (metadata['pulled_from_cloud_note_id'] as num?)?.toInt();
    final pulledFromAccount =
        metadata['pulled_from_account']?.toString().trim().toLowerCase() ?? '';
    final currentAccount = (_profile?['username']?.toString().trim().isNotEmpty == true
            ? _profile!['username'].toString().trim()
            : _profile?['email']?.toString().trim() ?? '')
        .toLowerCase();
    if (pulledFromNoteId != null &&
        pulledFromNoteId > 0 &&
        pulledFromAccount.isNotEmpty &&
        pulledFromAccount == currentAccount) {
      final updated = await widget.client.updateNote(token, pulledFromNoteId, {
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
      await persistLocalDrafts();
      await persistLocalStats();
      await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
      if (mounted) {
        refreshState();
      }
      log(
        level: DebugLogLevel.info,
        source: 'Portal.Sync.Notes/push',
        message:
            "Local cloud-copy draft synced: "
            "Portal.Sync.Notes/push \u2014 "
            "'${draft['title']}' upstream note updated in place.",
      );
      return updated;
    }
    final created = await widget.client.createNote(token, {
      'title': draft['title'],
      'description': draft['description'] ?? '',
      'content': draft['content'] ?? '',
      'editor_mode': draft['editor_mode'] ?? 'P',
      'course_id': metadata['course_id'],
      'metadata_json': jsonEncode(metadata),
      'client_draft_id': draft['client_draft_id'],
      'is_public': false,
    });
    _localDrafts = _localDrafts
        .where((item) => item['id'] != draft['id'])
        .toList(growable: false);
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
    await persistLocalDrafts();
    await persistLocalStats();
    await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
    await _refreshFrontPageData();
    if (mounted) {
      refreshState();
    }
    log(
      level: DebugLogLevel.info,
      source: 'Portal.Sync.Notes/push',
      message:
          "Local draft synced: Portal.Sync.Notes/push \u2014 "
          "'${draft['title']}' created on server; local draft moved to "
          'client-side recycle bin.',
    );
    return created;
  }
}
