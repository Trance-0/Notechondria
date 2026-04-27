part of notechondria_frontend;

/// Course/category lifecycle: create, edit, delete, unsubscribe,
/// reorder, and the prompt-with-delete-dialog helpers. Each method
/// handles local-only and cloud-backed courses distinctly because
/// offline-created categories get promoted to the cloud on first
/// sync. State mutations route through `refreshState()` since extensions
/// can't call `setState` directly. Extracted from `app_shell.dart`
/// so that file stays closer to the AGENTS.md §1.5 1000-line ceiling.
extension _AppShellCategoryX on _AppShellState {
  /// True iff the category is the protected Inbox row. The check is
  /// purely name-based (case-insensitive) \u2014 we deliberately do NOT
  /// rely on `is_default`, which is server-controlled and can lag the
  /// UI while a sync is in flight. Single source of truth so all
  /// rename / delete guards agree.
  bool _isInboxCategory(Map<String, dynamic> course) {
    final title = course['title']?.toString().trim() ?? '';
    return title.toLowerCase() == 'inbox';
  }

  /// True iff a category with [title] (case-insensitive) already
  /// exists in the user's combined local + cloud category list,
  /// optionally excluding [excludeId] so a rename can land on its
  /// own current title without false positives.
  bool _categoryNameExists(String title, {int? excludeId}) {
    final normalized = title.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    bool match(Map<String, dynamic> course) {
      final id = (course['id'] as num?)?.toInt();
      if (excludeId != null && id == excludeId) return false;
      final other = course['title']?.toString().trim().toLowerCase() ?? '';
      return other == normalized;
    }
    return _localCourses.any(match) || _courses.any(match);
  }

  /// Creates a new category. Cloud if signed in, otherwise local.
  Future<ActionFeedback> _createCategory(String title, {int? icon}) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return const ActionFeedback(
          message: 'Category not created: '
              'Editor.Sync.Courses/create \u2014 '
              'title field is empty.',
          isError: true);
    }
    if (_categoryNameExists(trimmed)) {
      return ActionFeedback(
          message: "Category not created: "
              "Editor.Sync.Courses/create \u2014 "
              "a category named '$trimmed' already exists.",
          isError: true);
    }
    final token = _token;
    try {
      if (token != null && token.isNotEmpty) {
        final created = await widget.client.createCourse(token, {
          'title': trimmed,
          'description': '',
          if (icon != null) 'icon': icon,
        });
        final decorated = decorateRemoteCourse(created);
          _courses = [decorated, ..._courses];
        refreshState();
        await _persistLocalCache();
        log(
          level: DebugLogLevel.info,
          source: 'Editor.Sync.Courses/create',
          message:
              "Created cloud category '$trimmed': "
              "Editor.Sync.Courses/create \u2014 server accepted new course.",
        );
      } else {
        final localCourse = _buildLocalCourse(title: trimmed);
        if (icon != null) localCourse['icon'] = icon;
          _localCourses = [..._localCourses, localCourse];
        refreshState();
        await persistLocalCourses();
        log(
          level: DebugLogLevel.info,
          source: 'Editor.Sync.Courses/create',
          message:
              "Created local category '$trimmed': "
              "Editor.Sync.Courses/create \u2014 "
              "queued for sync on next sign-in.",
        );
      }
      return ActionFeedback(
          message: "Category created: "
              "Editor.Sync.Courses/create \u2014 '$trimmed' added.");
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      log(
        level: DebugLogLevel.error,
        source: 'Editor.Sync.Courses/create',
        message: 'Category not created: '
            'Editor.Sync.Courses/create \u2014 $cause.',
      );
      return ActionFeedback(
          message: 'Category not created: '
              'Editor.Sync.Courses/create \u2014 $cause.',
          isError: true);
    }
  }

  /// Updates a category title and/or icon. Handles local-only and cloud courses.
  Future<ActionFeedback> _updateCategory(
    Map<String, dynamic> course,
    String newTitle, {
    int? icon,
  }) async {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) {
      return const ActionFeedback(
          message: 'Category not updated: '
              'Editor.Sync.Courses/update \u2014 '
              'title field is empty.',
          isError: true);
    }
    if (_isInboxCategory(course) &&
        trimmed.toLowerCase() != 'inbox') {
      return const ActionFeedback(
          message: 'Category not updated: '
              'Editor.Sync.Courses/update \u2014 '
              'the Inbox category cannot be renamed.',
          isError: true);
    }
    final courseId = (course['id'] as num?)?.toInt();
    if (_categoryNameExists(trimmed, excludeId: courseId)) {
      return ActionFeedback(
          message: 'Category not updated: '
              "Editor.Sync.Courses/update \u2014 "
              "a category named '$trimmed' already exists.",
          isError: true);
    }
    final isLocal = isLocalCourse(course);
    try {
      if (isLocal) {
          _localCourses = _localCourses
              .map((item) => item['id'] == course['id']
                  ? {...item, 'title': trimmed, 'icon': icon}
                  : item)
              .toList(growable: false);
          if ((_selectedCourse?['id'] as num?)?.toInt() == courseId) {
            _selectedCourse = {
              ...?_selectedCourse,
              'title': trimmed,
              'icon': icon,
            };
          }
        refreshState();
        await persistLocalCourses();
      } else {
        final token = _token;
        if (token == null || token.isEmpty || courseId == null) {
          return const ActionFeedback(
              message: 'Category not updated: '
                  'Editor.Sync.Courses/update \u2014 '
                  'sign in first; cloud categories require a session.',
              isError: true);
        }
        final updated = await widget.client.updateCourse(
          token,
          courseId,
          {'title': trimmed, 'icon': icon},
        );
        final decorated = decorateRemoteCourse(updated);
          _courses = _courses
              .map((item) => (item['id'] as num?)?.toInt() == courseId
                  ? decorated
                  : item)
              .toList(growable: false);
          if ((_selectedCourse?['id'] as num?)?.toInt() == courseId) {
            _selectedCourse = decorated;
          }
        refreshState();
        await _persistLocalCache();
      }
      log(
        level: DebugLogLevel.info,
        source: 'Editor.Sync.Courses/update',
        message:
            "Category updated: Editor.Sync.Courses/update \u2014 "
            "'$trimmed' renamed/re-iconed.",
      );
      return ActionFeedback(
          message: "Category updated: Editor.Sync.Courses/update \u2014 "
              "'$trimmed' saved.");
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      log(
        level: DebugLogLevel.error,
        source: 'Editor.Sync.Courses/update',
        message: 'Category not updated: '
            'Editor.Sync.Courses/update \u2014 $cause.',
      );
      return ActionFeedback(
          message: 'Category not updated: '
              'Editor.Sync.Courses/update \u2014 $cause.',
          isError: true);
    }
  }

  /// Deletes a category. Notes in it are moved to the user's default category.
  Future<ActionFeedback> _deleteCategory(Map<String, dynamic> course) async {
    if (_isInboxCategory(course)) {
      return const ActionFeedback(
          message: 'Category not deleted: '
              'Editor.Sync.Courses/delete \u2014 '
              'the Inbox category cannot be removed.',
          isError: true);
    }
    final courseId = (course['id'] as num?)?.toInt();
    final isLocal = isLocalCourse(course);
    try {
      if (isLocal) {
        // Find the local Inbox category (by name, not is_default) to
        // reassign notes orphaned by this delete.
        final defaultLocal = _localCourses.cast<Map<String, dynamic>?>().firstWhere(
          (c) => c != null &&
              c['id'] != course['id'] &&
              _isInboxCategory(c),
          orElse: () => null,
        );
        final defaultLocalId = (defaultLocal?['id'] as num?)?.toInt();
          _localCourses = _localCourses
              .where((item) => item['id'] != course['id'])
              .toList(growable: false);
          // Move drafts from the deleted category into the default category.
          if (courseId != null && defaultLocalId != null) {
            _localDrafts = _localDrafts.map((draft) {
              if (_draftCourseId(draft) != courseId) return draft;
              return _remapDraftCourseId(draft, courseId, defaultLocalId);
            }).toList(growable: false);
          } else {
            // Fallback: strip course_id so they at least remain visible.
            _localDrafts = _localDrafts.map((draft) {
              if (_draftCourseId(draft) != courseId) return draft;
              final metadata = _decodeNoteMetadata(
                  draft['metadata_json']?.toString() ?? '{}');
              metadata.remove('course_id');
              return {
                ...draft,
                'metadata_json': jsonEncode(metadata),
              };
            }).toList(growable: false);
          }
          if ((_selectedCourse?['id'] as num?)?.toInt() == courseId) {
            _selectedCourse = defaultLocal;
            _selectedCategoryId = defaultLocalId;
          }
        refreshState();
        await persistLocalCourses();
        await persistLocalDrafts();
      } else {
        final token = _token;
        if (token == null || token.isEmpty || courseId == null) {
          return const ActionFeedback(
              message: 'Category not deleted: '
                  'Editor.Sync.Courses/delete \u2014 '
                  'sign in first; cloud categories require a session.',
              isError: true);
        }
        await widget.client.deleteCourse(token, courseId);
        // Find the remote Inbox category to land on after deletion
        // (by name, not is_default).
        final defaultRemote = _courses.cast<Map<String, dynamic>?>().firstWhere(
          (c) => c != null &&
              (c['id'] as num?)?.toInt() != courseId &&
              _isInboxCategory(c),
          orElse: () => null,
        );
          _courses = _courses
              .where((item) => (item['id'] as num?)?.toInt() != courseId)
              .toList(growable: false);
          if ((_selectedCourse?['id'] as num?)?.toInt() == courseId) {
            _selectedCourse = defaultRemote;
            _selectedCategoryId = (defaultRemote?['id'] as num?)?.toInt();
          }
        refreshState();
        await _persistLocalCache();
        await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
      }
      log(
        level: DebugLogLevel.info,
        source: 'Editor.Sync.Courses/delete',
        message:
            "Category deleted: Editor.Sync.Courses/delete \u2014 "
            "'${course['title']}' removed; its notes moved to default.",
      );
      return ActionFeedback(
          message: "Category deleted: Editor.Sync.Courses/delete \u2014 "
              "'${course['title']}' removed; notes moved to default.");
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      log(
        level: DebugLogLevel.error,
        source: 'Editor.Sync.Courses/delete',
        message: 'Category not deleted: '
            'Editor.Sync.Courses/delete \u2014 $cause.',
      );
      return ActionFeedback(
          message: 'Category not deleted: '
              'Editor.Sync.Courses/delete \u2014 $cause.',
          isError: true);
    }
  }

  /// Unsubscribes the current user from a cloud category they do not
  /// own, removing it from their sidebar without touching the
  /// course itself on the server. Mirrors planner/portal's existing
  /// unsubscribe flow. Returns an `ActionFeedback` shaped per §1.7.
  Future<ActionFeedback> _unsubscribeCategory(
      Map<String, dynamic> course) async {
    final courseId = (course['id'] as num?)?.toInt();
    final token = _token;
    if (token == null || token.isEmpty || courseId == null) {
      return const ActionFeedback(
          message: 'Category not unsubscribed: '
              'Editor.Sync.Courses/unsubscribe \u2014 '
              'sign in first; unsubscribing requires a cloud session.',
          isError: true);
    }
    try {
      await widget.client.unsubscribeCourse(token, courseId);
      // Land back on the remote Inbox after unsubscribing (by name).
      final defaultRemote = _courses.cast<Map<String, dynamic>?>().firstWhere(
            (c) =>
                c != null &&
                (c['id'] as num?)?.toInt() != courseId &&
                _isInboxCategory(c),
            orElse: () => null,
          );
        _courses = _courses
            .where((item) => (item['id'] as num?)?.toInt() != courseId)
            .toList(growable: false);
        if ((_selectedCourse?['id'] as num?)?.toInt() == courseId) {
          _selectedCourse = defaultRemote;
          _selectedCategoryId = (defaultRemote?['id'] as num?)?.toInt();
        }
      refreshState();
      await _persistLocalCache();
      await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
      log(
        level: DebugLogLevel.info,
        source: 'Editor.Sync.Courses/unsubscribe',
        message:
            'Category unsubscribed: Editor.Sync.Courses/unsubscribe \u2014 '
            "'${course['title']}' removed from sidebar; course stays on server.",
      );
      return ActionFeedback(
          message:
              'Category unsubscribed: Editor.Sync.Courses/unsubscribe \u2014 '
              "'${course['title']}' removed from your sidebar.");
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      log(
        level: DebugLogLevel.error,
        source: 'Editor.Sync.Courses/unsubscribe',
        message: 'Category not unsubscribed: '
            'Editor.Sync.Courses/unsubscribe \u2014 $cause.',
      );
      return ActionFeedback(
          message: 'Category not unsubscribed: '
              'Editor.Sync.Courses/unsubscribe \u2014 $cause.',
          isError: true);
    }
  }

  /// Renders a single sidebar category row with the shared tooltip, long-press,
  /// and right-click handlers. Pulled out so the pinned Inbox row and the
  /// draggable rows inside the reorderable list share the exact same look.
  Widget _buildCategoryRow(Map<String, dynamic> cat) {
    final isInbox = _isInboxCategory(cat);
    return Tooltip(
      message: isInbox
          ? cat['title']?.toString() ?? 'Category'
          : 'Long-press or right-click to rename or delete. Drag to reorder.',
      waitDuration: const Duration(milliseconds: 600),
      child: GestureDetector(
        onLongPress: () => _promptEditCategory(cat),
        onSecondaryTap: () => _promptEditCategory(cat),
        child: SidebarItem(
          icon: cat['is_local_course'] == true
              ? Icons.folder_outlined
              : (isInbox
                  ? Icons.inbox_outlined
                  : Icons.school_outlined),
          label: cat['title']?.toString() ?? 'Category',
          selected:
              _selectedCategoryId == (cat['id'] as num?)?.toInt(),
          onTap: () => _selectCourse(cat),
        ),
      ),
    );
  }

  /// Applies a new ordering for the draggable categories in the sidebar. The
  /// default Inbox is pinned and never included in [newOrder]. Local-only
  /// categories are reordered in memory; remote ones are persisted through
  /// `/courses/reorder/` so the order survives across sessions.
  Future<void> _reorderCategories(List<Map<String, dynamic>> newOrder) async {
    // Split the drag result into local vs cloud buckets. Local drafts keep the
    // in-memory order the user just chose; cloud courses get persisted.
    final newLocal = <Map<String, dynamic>>[];
    final newRemote = <Map<String, dynamic>>[];
    for (final course in newOrder) {
      if (isLocalCourse(course)) {
        newLocal.add(course);
      } else {
        newRemote.add(course);
      }
    }

      _localCourses = List<Map<String, dynamic>>.from(newLocal);
      _courses = List<Map<String, dynamic>>.from(newRemote);
    refreshState();

    // Persist local ordering regardless of auth state.
    await persistLocalCourses();

    final token = _token;
    if (token == null || token.isEmpty || newRemote.isEmpty) {
      log(
        level: DebugLogLevel.info,
        source: 'Editor.Sync.Courses/reorder',
        message:
            'Categories reordered locally: '
            'Editor.Sync.Courses/reorder \u2014 '
            'no cloud session; new order kept in memory only.',
      );
      return;
    }

    final remoteIds = <int>[
      for (final course in newRemote)
        if ((course['id'] as num?) != null) (course['id'] as num).toInt(),
    ];
    try {
      final refreshed = await widget.client.reorderCourses(token, remoteIds);
      final decorated =
          refreshed.map(decorateRemoteCourse).toList(growable: false);
        _courses = decorated;
      refreshState();
      await _persistLocalCache();
      log(
        level: DebugLogLevel.info,
        source: 'Editor.Sync.Courses/reorder',
        message:
            'Categories reordered: Editor.Sync.Courses/reorder \u2014 '
            '${remoteIds.length} cloud categories persisted.',
      );
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      log(
        level: DebugLogLevel.error,
        source: 'Editor.Sync.Courses/reorder',
        message:
            'Categories not reordered: '
            'Editor.Sync.Courses/reorder \u2014 $cause.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Categories not reordered: '
              'Editor.Sync.Courses/reorder \u2014 $cause.',
            ),
          ),
        );
      }
    }
  }

  /// Shows a dialog to create a new category with optional icon.
  Future<void> _promptCreateCategory() async {
    final controller = TextEditingController();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _CreateCategoryDialog(controller: controller),
    );
    controller.dispose();
    if (result == null) return;
    final title = result['title'] as String? ?? '';
    if (title.trim().isEmpty) return;
    final icon = result['icon'] as int?;
    final feedback = await _createCategory(title, icon: icon);
    if (mounted && feedback.isError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(feedback.message)),
      );
    }
  }

  /// Shows an edit dialog for a category (rename + icon + delete).
  Future<void> _promptEditCategory(Map<String, dynamic> course) async {
    if (_isInboxCategory(course)) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.inbox_outlined),
              const SizedBox(width: 8),
              Text(course['title']?.toString() ?? 'Inbox'),
            ],
          ),
          content: const Text(
            'Inbox is the default category. It cannot be renamed or deleted.\n\n'
            'Notes that lose their category are automatically moved here.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    final controller =
        TextEditingController(text: course['title']?.toString() ?? '');
    final currentIcon = (course['icon'] as num?)?.toInt();
    // Local (negative-id) categories are always owned by the current
    // user. For cloud courses we trust the `is_owned` flag computed
    // by `decorateRemoteCourse`. When ownership is unclear (no
    // authenticated username at decoration time) we default to
    // read-only so the user can't produce a backend 403 from the UI.
    final isOwned = isLocalCourse(course) || course['is_owned'] == true;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _EditCategoryDialog(
        controller: controller,
        initialIcon: currentIcon,
        isOwned: isOwned,
      ),
    );
    controller.dispose();
    if (result == null) return;
    final action = result['action'] as String;
    if (action == 'delete') {
      final confirmed = await _confirmWithDelay(
        title: 'Delete category?',
        message:
            "'${course['title']}' will be removed. All notes inside will move to the default category.",
      );
      if (confirmed) {
        final feedback = await _deleteCategory(course);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(feedback.message)),
          );
        }
      }
    } else if (action == 'unsubscribe') {
      final confirmed = await _confirmWithDelay(
        title: 'Unsubscribe from category?',
        message:
            "'${course['title']}' will be removed from your sidebar. "
            'The category itself stays on the server and you can resubscribe later.',
      );
      if (confirmed) {
        final feedback = await _unsubscribeCategory(course);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(feedback.message)),
          );
        }
      }
    } else if (action == 'save') {
      final newTitle = result['title'] as String? ?? '';
      final newIcon = result['icon'] as int?;
      final feedback = await _updateCategory(course, newTitle, icon: newIcon);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(feedback.message)),
        );
      }
    }
  }

  /// Shows a confirmation dialog with a 3-second delay before enabling the
  /// destructive action button. Used for clear-data style operations.
  Future<bool> _confirmWithDelay({
    required String title,
    required String message,
    String confirmLabel = 'Delete',
    int delaySeconds = 3,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => ConfirmWithDelayDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        delaySeconds: delaySeconds,
      ),
    );
    return result == true;
  }
}
