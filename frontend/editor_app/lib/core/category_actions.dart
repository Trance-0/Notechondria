part of notechondria_frontend;

/// Course/category lifecycle: create, edit, delete, unsubscribe,
/// reorder, and the prompt-with-delete-dialog helpers. Each method
/// handles local-only and cloud-backed courses distinctly because
/// offline-created categories get promoted to the cloud on first
/// sync. State mutations route through `refreshState()` since extensions
/// can't call `setState` directly. Extracted from `app_shell.dart`
/// so that file stays closer to the AGENTS.md §1.5 1000-line ceiling.
extension _AppShellCategoryX on _AppShellState {
  /// True iff [course] is the synthetic uncategorized folder rendered
  /// at the top of the sidebar \u2014 the placeholder that groups every
  /// note with no `course_id` (the post-0.1.120 replacement for the
  /// pre-refactor Inbox course). The synthetic row is marked with
  /// `is_uncategorized: true` by `buildUncategorizedFolder`; nothing
  /// on the server side carries this flag, so it can't accidentally
  /// match a real Course row that happens to be titled "Inbox".
  bool _isUncategorizedFolder(Map<String, dynamic> course) {
    return course['is_uncategorized'] == true;
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
    if (_isUncategorizedFolder(course)) {
      // 0.1.120: the synthetic uncategorized bucket isn't a real
      // Course row \u2014 its label lives on Creator.uncategorized_folder_name
      // and is editable from Settings. Inline rename here would have
      // nothing to write to; bail with a clear pointer.
      return const ActionFeedback(
          message: 'Category not updated: '
              'Editor.Sync.Courses/update \u2014 '
              'the uncategorized bucket is renamed from Settings, not '
              'inline. Open Settings \u2192 Display \u2192 Uncategorized folder name.',
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

  /// Deletes a category. Notes in it fall to the synthetic
  /// uncategorized bucket (no `course_id`).
  ///
  /// 0.1.120: the pre-refactor "find the Inbox course and reassign
  /// orphaned notes to it" logic was retired along with `is_default`.
  /// On the server, ``Note.course_id`` is `on_delete=SET_NULL` so
  /// notes survive the category delete with `course_id IS NULL`. On
  /// the client we just drop the row from local state and clear any
  /// `course_id` field on local drafts that pointed at the deleted
  /// category.
  Future<ActionFeedback> _deleteCategory(Map<String, dynamic> course) async {
    if (_isUncategorizedFolder(course)) {
      return const ActionFeedback(
          message: 'Category not deleted: '
              'Editor.Sync.Courses/delete \u2014 '
              'the uncategorized bucket is the fallback for orphaned '
              'notes and cannot be removed. Rename it from Settings if '
              'you want a different label.',
          isError: true);
    }
    final courseId = (course['id'] as num?)?.toInt();
    final isLocal = isLocalCourse(course);
    try {
      if (isLocal) {
        _localCourses = _localCourses
            .where((item) => item['id'] != course['id'])
            .toList(growable: false);
        // Strip `course_id` from any local draft pointing at the
        // deleted row so it surfaces in the synthetic uncategorized
        // bucket on next render.
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
        if ((_selectedCourse?['id'] as num?)?.toInt() == courseId) {
          _selectedCourse = null;
          _selectedCategoryId = null;
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
        _courses = _courses
            .where((item) => (item['id'] as num?)?.toInt() != courseId)
            .toList(growable: false);
        if ((_selectedCourse?['id'] as num?)?.toInt() == courseId) {
          _selectedCourse = null;
          _selectedCategoryId = null;
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
            "'${course['title']}' removed; its notes fall to the "
            "uncategorized bucket via SET_NULL.",
      );
      return ActionFeedback(
          message: "Category deleted: Editor.Sync.Courses/delete \u2014 "
              "'${course['title']}' removed; its notes are now in the "
              "uncategorized bucket.");
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

  /// Removes a category from the user's sidebar. Works in any auth
  /// state — when signed in against a cloud course we best-effort
  /// `widget.client.unsubscribeCourse(...)`; offline (no token) or
  /// for local-only rows we skip the server call entirely. Either
  /// way the row is dropped from `_courses` / `_localCourses` and
  /// the UI updates immediately. A failed cloud unsubscribe (401
  /// stale session, 403 owned-row, network blip) is logged at
  /// warning and does NOT block the local removal — user intent
  /// ("get this off my sidebar") wins. Next online sync may
  /// re-surface a cloud row whose server-side subscription wasn't
  /// actually dropped; that's acceptable for now and clearer than
  /// blocking the action when the cloud call fails.
  Future<ActionFeedback> _unsubscribeCategory(
      Map<String, dynamic> course) async {
    final courseId = (course['id'] as num?)?.toInt();
    if (courseId == null) {
      return const ActionFeedback(
          message: 'Category not removed: '
              'Editor.Sync.Courses/unsubscribe \u2014 '
              'category id missing from row.',
          isError: true);
    }
    final token = _token;
    final isLocal = isLocalCourse(course);
    final hasToken = token != null && token.isNotEmpty;
    if (!isLocal && hasToken) {
      try {
        await widget.client.unsubscribeCourse(token, courseId);
      } catch (error) {
        log(
          level: DebugLogLevel.warning,
          source: 'Editor.Sync.Courses/unsubscribe',
          message:
              'Cloud unsubscribe failed; sidebar row dropped locally anyway: '
              'Editor.Sync.Courses/unsubscribe \u2014 '
              '${error.toString().replaceFirst("Exception: ", "")}.',
        );
      }
    }
    if (isLocal) {
      _localCourses = _localCourses
          .where((item) => (item['id'] as num?)?.toInt() != courseId)
          .toList(growable: false);
      await persistLocalCourses();
    } else {
      _courses = _courses
          .where((item) => (item['id'] as num?)?.toInt() != courseId)
          .toList(growable: false);
      await _persistLocalCache();
    }
    if ((_selectedCourse?['id'] as num?)?.toInt() == courseId) {
      // Fall back to the synthetic uncategorized bucket (no course
      // selected). The sidebar pins it client-side.
      _selectedCourse = null;
      _selectedCategoryId = null;
    }
    refreshState();
    if (hasToken) {
      await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
    }
    final scope = !hasToken
        ? 'sidebar (offline; cloud not contacted)'
        : (isLocal
            ? 'sidebar (local row)'
            : 'sidebar; server unsubscribe attempted');
    log(
      level: DebugLogLevel.info,
      source: 'Editor.Sync.Courses/unsubscribe',
      message:
          'Category removed from sidebar: '
          'Editor.Sync.Courses/unsubscribe \u2014 '
          "'${course['title']}' dropped from $scope.",
    );
    return ActionFeedback(
        message:
            'Category removed: Editor.Sync.Courses/unsubscribe \u2014 '
            "'${course['title']}' dropped from your sidebar.");
  }

  /// Renders a single sidebar category row with the shared tooltip, long-press,
  /// and right-click handlers. Pulled out so the pinned Inbox row and the
  /// draggable rows inside the reorderable list share the exact same look.
  Widget _buildCategoryRow(Map<String, dynamic> cat) {
    final isInbox = _isUncategorizedFolder(cat);
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
  ///
  /// 0.1.120: the synthetic uncategorized folder is informational —
  /// long-press / right-click on it surfaces a hint pointing the user
  /// at Settings (where its label can be edited). It can't be renamed
  /// inline (its label lives on `Creator.uncategorized_folder_name`)
  /// and it can't be removed (it's the fallback for any note without
  /// a course).
  Future<void> _promptEditCategory(Map<String, dynamic> course) async {
    if (_isUncategorizedFolder(course)) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.inbox_outlined),
              const SizedBox(width: 8),
              Text(course['title']?.toString() ?? 'Uncategorized'),
            ],
          ),
          content: const Text(
            'This is your uncategorized bucket — every note that has '
            'no category lands here. It cannot be renamed inline or '
            'removed. Open Settings → Display to rename it (the label '
            'is per-account).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Got it'),
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
      // Unsubscribe is non-destructive (the category stays on the
      // server; only the sidebar row is dropped) and the user has
      // already confirmed by tapping "Unsubscribe" in the edit
      // dialog — no second 3s-delay confirmation, since the action
      // is recoverable by resubscribing or signing in again.
      final feedback = await _unsubscribeCategory(course);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(feedback.message)),
        );
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
