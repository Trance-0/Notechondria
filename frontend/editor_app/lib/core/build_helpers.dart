part of notechondria_frontend;

/// Build-helpers for the main scaffold: compact (mobile/narrow drawer)
/// + wide (side-navigation rail) layouts, category row rendering for
/// the drawer and sidebar, the body switcher that picks between
/// learner list / editor / settings pages, and the page-routed content
/// wrapper. Extracted from `app_shell.dart` so that file stays closer
/// to the AGENTS.md §1.5 1000-line ceiling. The top-level `build()`
/// stays on `_AppShellState` because Flutter requires it as an
/// override; everything it delegates to lives here.
extension _AppShellBuildHelpersX on _AppShellState {
  /// Compact (mobile/narrow) layout with a hamburger drawer for navigation.
  Widget _buildCompactScaffold(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Show current folder/category name instead of app title.
    String compactTitle;
    if (_selectedIndex == 1) {
      if (_selectedCategoryId != null) {
        compactTitle = _selectedCourse?['title']?.toString() ?? 'Category';
      } else {
        compactTitle = l10n.navAllNotes;
      }
    } else {
      compactTitle = widget.appTitle;
    }
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(compactTitle),
        backgroundColor: Colors.transparent,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: l10n.navNavigation,
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              // "All Notes" item
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SidebarItem(
                  icon: Icons.menu_book_outlined,
                  label: l10n.navAllNotes,
                  selected: _selectedIndex == 1 && _selectedCategoryId == null,
                  onTap: () {
                    Navigator.of(context).pop(); // close drawer
                    _selectedCategoryId = null;
                    _selectedIndex = 1;
                    refreshState();
                    _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
                  },
                ),
              ),
              // Categories section
              if (_allCategories.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: InkWell(
                    onTap: () {
                      _coursePanelExpanded = !_coursePanelExpanded;
                      refreshState();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.navCategories,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Icon(_coursePanelExpanded
                              ? Icons.expand_less
                              : Icons.expand_more),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_coursePanelExpanded)
                  Expanded(
                    child: Builder(builder: (context) {
                      // 0.1.101: defensive pinning guard. Older builds
                      // and some sync paths could leave a row titled
                      // "Inbox" with `is_default == false`, which made
                      // the pinned filter below come up empty and the
                      // category vanished from the top of the sidebar
                      // until "Restore default Inbox" got tapped from
                      // Settings. Now we treat any Inbox-named row as
                      // pinned so the user always sees it.
                      final pinned = _allCategories
                          .where(isCategoryPinned)
                          .toList(growable: false);
                      final draggable = _allCategories
                          .where((c) => !isCategoryPinned(c))
                          .toList(growable: false);
                      emitSidebarPinDiagnostics(
                        total: _allCategories.length,
                        pinned: pinned.length,
                      );
                      return Column(
                        children: [
                          for (var ci = 0; ci < pinned.length; ci++)
                            _StaggeredFadeIn(
                              index: ci,
                              slideOffset: const Offset(0.06, 0),
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 0, 12, 4),
                                child: _buildDrawerCategoryRow(pinned[ci]),
                              ),
                            ),
                          Expanded(
                            child: ReorderableListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                              buildDefaultDragHandles: false,
                              itemCount: draggable.length,
                              onReorder: (oldIndex, newIndex) {
                                if (newIndex > oldIndex) newIndex -= 1;
                                final reordered =
                                    List<Map<String, dynamic>>.from(draggable);
                                final moved = reordered.removeAt(oldIndex);
                                reordered.insert(newIndex, moved);
                                _reorderCategories([...pinned, ...reordered]);
                              },
                              itemBuilder: (context, index) {
                                final cat = draggable[index];
                                final key = ValueKey(
                                    'dcat-${cat['id']?.toString() ?? index}');
                                return KeyedSubtree(
                                  key: key,
                                  child: _StaggeredFadeIn(
                                    index: index + pinned.length,
                                    slideOffset: const Offset(0.06, 0),
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: ReorderableDragStartListener(
                                        index: index,
                                        child: _buildDrawerCategoryRow(cat),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                            child: SidebarItem(
                              icon: Icons.add_circle_outline,
                              label: l10n.navNewCategory,
                              selected: false,
                              onTap: () {
                                Navigator.of(context).pop();
                                _promptCreateCategory();
                              },
                            ),
                          ),
                        ],
                      );
                    }),
                  )
                else
                  const Spacer(),
              ] else ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SidebarItem(
                    icon: Icons.add_circle_outline,
                    label: l10n.navNewCategory,
                    selected: false,
                    onTap: () {
                      Navigator.of(context).pop();
                      _promptCreateCategory();
                    },
                  ),
                ),
                const Spacer(),
              ],
              // Settings at bottom
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                child: SidebarItem(
                  icon: Icons.settings_outlined,
                  label: l10n.navSettings,
                  selected: _selectedIndex == 4,
                  onTap: () {
                    Navigator.of(context).pop();
                    _selectActualIndex(4);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  /// Category row for the compact drawer. Closes the drawer on tap, then
  /// selects the course. Long-press opens the edit dialog (same as wide).
  Widget _buildDrawerCategoryRow(Map<String, dynamic> cat) {
    return GestureDetector(
      onLongPress: () {
        Navigator.of(context).pop();
        _promptEditCategory(cat);
      },
      onSecondaryTap: () {
        Navigator.of(context).pop();
        _promptEditCategory(cat);
      },
      child: SidebarItem(
        icon: _courseIcon(cat),
        label: cat['title']?.toString() ?? 'Category',
        selected: _selectedCategoryId == (cat['id'] as num?)?.toInt(),
        onTap: () {
          Navigator.of(context).pop();
          _selectCourse(cat);
        },
      ),
    );
  }

  /// Wide (horizontal) layout with category sidebar.
  Widget _buildWideScaffold(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            // ---- Sidebar ----
            Container(
              width: 240,
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(
                    right: BorderSide(color: colorScheme.outlineVariant)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  // "All Notes" item
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: SidebarItem(
                      icon: Icons.menu_book_outlined,
                      label: l10n.navAllNotes,
                      selected:
                          _selectedIndex == 1 && _selectedCategoryId == null,
                      onTap: () {
                        _selectedCategoryId = null;
                        _selectedIndex = 1;
                        refreshState();
                        _loadLearnerNotes(
                            reset: true, query: _learnerSearchQuery);
                      },
                    ),
                  ),
                  // Categories section
                  if (_allCategories.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: InkWell(
                        onTap: () {
                          _coursePanelExpanded = !_coursePanelExpanded;
                          refreshState();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l10n.navCategories,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              Icon(_coursePanelExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_coursePanelExpanded)
                      Expanded(
                        child: Builder(builder: (context) {
                          // Pin the default (Inbox) category at the
                          // top so it stays out of the drag-reorder
                          // zone. Same defensive title-fallback as
                          // the compact layout above (0.1.101) so an
                          // Inbox-named row pins even when
                          // `is_default` got stripped on the way in.
                          final pinned = _allCategories
                              .where(isCategoryPinned)
                              .toList(growable: false);
                          final draggable = _allCategories
                              .where((c) => !isCategoryPinned(c))
                              .toList(growable: false);
                          emitSidebarPinDiagnostics(
                            total: _allCategories.length,
                            pinned: pinned.length,
                          );
                          return Column(
                            children: [
                              for (var ci = 0; ci < pinned.length; ci++)
                                _StaggeredFadeIn(
                                  index: ci,
                                  slideOffset: const Offset(0.06, 0),
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(12, 0, 12, 4),
                                    child: _buildCategoryRow(pinned[ci]),
                                  ),
                                ),
                              Expanded(
                                child: ReorderableListView.builder(
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 0, 12, 0),
                                  buildDefaultDragHandles: false,
                                  itemCount: draggable.length,
                                  onReorder: (oldIndex, newIndex) {
                                    // Flutter's ReorderableListView passes
                                    // newIndex as the target slot *before*
                                    // removal, so shift it left when moving
                                    // down the list.
                                    if (newIndex > oldIndex) newIndex -= 1;
                                    final reordered =
                                        List<Map<String, dynamic>>.from(
                                            draggable);
                                    final moved = reordered.removeAt(oldIndex);
                                    reordered.insert(newIndex, moved);
                                    // _reorderCategories synchronously updates
                                    // _localCourses/_courses via setState, so
                                    // the next rebuild already reflects the
                                    // new order — no local mutation needed.
                                    _reorderCategories(
                                        [...pinned, ...reordered]);
                                  },
                                  itemBuilder: (context, index) {
                                    final cat = draggable[index];
                                    final key = ValueKey(
                                        'cat-${cat['id']?.toString() ?? index}');
                                    return KeyedSubtree(
                                      key: key,
                                      child: _StaggeredFadeIn(
                                        index: index + pinned.length,
                                        slideOffset: const Offset(0.06, 0),
                                        child: Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 4),
                                          child: ReorderableDragStartListener(
                                            index: index,
                                            child: _buildCategoryRow(cat),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 4, 12, 8),
                                child: SidebarItem(
                                  icon: Icons.add_circle_outline,
                                  label: l10n.navNewCategory,
                                  selected: false,
                                  onTap: _promptCreateCategory,
                                ),
                              ),
                            ],
                          );
                        }),
                      )
                    else
                      const Spacer(),
                  ] else ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: SidebarItem(
                        icon: Icons.add_circle_outline,
                        label: l10n.navNewCategory,
                        selected: false,
                        onTap: _promptCreateCategory,
                      ),
                    ),
                    const Spacer(),
                  ],
                  // Settings at bottom
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    child: SidebarItem(
                      icon: Icons.settings_outlined,
                      label: l10n.navSettings,
                      selected: _selectedIndex == 4,
                      onTap: () => _selectActualIndex(4),
                    ),
                  ),
                ],
              ),
            ),
            // ---- Main content ----
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_showWidePageHeader(_selectedIndex))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                      child: Text(
                        _AppShellState._titles[_selectedIndex],
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  Expanded(child: _buildBody()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final l10n = AppLocalizations.of(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isLoading) const LinearProgressIndicator(minHeight: 2),
            if (_errorMessage != null)
              Material(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_off_outlined,
                          color:
                              Theme.of(context).colorScheme.onErrorContainer),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(_errorMessage!,
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer)),
                      ),
                      TextButton(
                          onPressed: _loadInitialData,
                          child: Text(l10n.commonRetry)),
                      IconButton(
                        onPressed: () {
                          _errorMessage = null;
                          refreshState();
                        },
                        icon: const Icon(Icons.close),
                        tooltip: l10n.commonDismiss,
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.03, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey<int>(_selectedIndex),
                  child: _buildPage(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage() {
    switch (_selectedIndex) {
      case 1:
        // Local-draft visibility rules:
        //
        //   1. No category selected → show every local draft
        //      (the "All Notes" pseudo-category).
        //   2. Scope dropdown explicitly set to "Local drafts only"
        //      → drop the category filter and show every local draft
        //      so the user can see ALL of them (the whole point of
        //      that filter — they want to triage local drafts across
        //      categories without switching the sidebar selection).
        //   3. Otherwise → scope to the active course so we don't
        //      mix unrelated drafts from other categories.
        final showAllLocalDrafts =
            _selectedCourse == null || _learnerSearchScope == 'local';
        final scopedLocalDrafts = showAllLocalDrafts
            ? _localDrafts
            : _localNotesForCourse(_selectedCourse!);
        return _LearnerPage(
          notes: _learnerNotes,
          localDrafts: scopedLocalDrafts,
          courses: [..._localCourses, ..._courses],
          selectedNote: _selectedNote,
          editorMode: _settings?['editor_mode']?.toString() ?? 'P',
          hasMoreNotes: _hasMoreLearnerNotes,
          isLoadingMore: _isLoadingMoreNotes,
          searchQuery: _learnerSearchQuery,
          searchScope: _learnerSearchScope,
          isAuthenticated: _token != null && _token!.isNotEmpty,
          isLocalCourseSelected: isLocalCourse(_selectedCourse),
          currentUsername: _profile?['username']?.toString() ?? '',
          apiBaseUrl: _localSettings['api_base_url']?.toString() ??
              _httpClient?.baseUrl,
          onSearchChanged: (value) =>
              _loadLearnerNotes(reset: true, query: value),
          onSearchScopeChanged: (value) =>
              _loadLearnerNotes(reset: true, scope: value),
          onLoadMore: () => _loadLearnerNotes(),
          onOpenNote: _selectNote,
          onFetchNoteDetail: _fetchNoteDetail,
          onCreateNote: _createNote,
          onImportMarkdown: _importMarkdownNote,
          onExportNote: _exportNote,
          onSaveNote: _saveNote,
          onGetNoteHistory: _getNoteHistory,
          onSnapshotNote: _snapshotNote,
          onRestoreNoteVersion: _restoreNoteVersion,
          onStartNoteSession: _startNoteSession,
          onFinishNoteSession: _finishNoteSession,
          onDeleteNote: _deleteNoteToRecycleBin,
          onSyncLocalDraft: _syncLocalDraft,
          onSyncAllLocalDrafts: _syncAllLocalDrafts,
          onLogEvent: ({
            required source,
            required message,
            level = DebugLogLevel.info,
            durationMs,
          }) =>
              log(
            source: source,
            message: message,
            level: level,
            durationMs: durationMs,
          ),
          onUploadAttachment: _uploadNoteAttachment,
          onUploadCover: _token != null
              ? (noteId, file) =>
                  widget.client.uploadNoteCoverImage(_token!, noteId, file)
              : null,
          onDeleteCover: _token != null
              ? (noteId) => widget.client.deleteNoteCoverImage(_token!, noteId)
              : null,
          offlineMode: _localSettings['offline_mode'] == true,
          onLoadPublicNotes: () => _loadLearnerNotes(),
        );
      case 4:
        return _SettingsPage(
          profile: _profile,
          settings: _settings,
          localSettings: _localSettings,
          localStats: _localStats,
          deletedNotes: _deletedNotes,
          onSave: _updateSettings,
          onLogout: logout,
          onLogin: login,
          onCasdoorLogin: () => launchOAuth('casdoor', intent: 'login'),
          casdoorOrgLoginUrl: _casdoorOrgLoginUrl,
          onBindCasdoor: (_casdoorConfigured && _token != null)
              ? () => launchOAuth('casdoor', intent: 'bind')
              : null,
          onUnlinkCasdoor: (_casdoorConfigured && _token != null)
              ? () async {
                  try {
                    await widget.client.casdoorUnlink(_token!);
                    if (mounted) {
                      _settings = {
                        ..._settings ?? <String, dynamic>{},
                        'casdoor_linked': false,
                      };
                      refreshState();
                    }
                  } catch (_) {/* swallowed; UI stays stale */}
                }
              : null,
          onRotateApiKey: _token != null
              ? () async {
                  final result = await widget.client.rotateApiKey(_token!);
                  // Merge the new prefix into the in-memory settings so the
                  // UI shows the updated masked value after rebuild.
                  final newPrefix = result['api_key_prefix']?.toString() ?? '';
                  if (newPrefix.isNotEmpty && mounted) {
                    _settings = {
                      ..._settings ?? <String, dynamic>{},
                      'api_key_prefix': newPrefix,
                    };
                    refreshState();
                  }
                  return result;
                }
              : null,
          onSaveMcpSkill: _token != null
              ? (skillMd) async {
                  try {
                    final result = await widget.client.updateSettings(
                      _token!,
                      {'mcp_skill_md': skillMd},
                    );
                    if (mounted) {
                      _settings = {
                        ..._settings ?? <String, dynamic>{},
                        'mcp_skill_md':
                            result['mcp_skill_md']?.toString() ?? skillMd,
                      };
                      refreshState();
                    }
                    return const ActionFeedback(
                      message: 'Agent skill saved.',
                    );
                  } catch (e) {
                    final msg = e.toString().replaceFirst('Exception: ', '');
                    return ActionFeedback(
                      message: 'Agent skill not saved: '
                          'Editor.Settings/skill.save — $msg.',
                      isError: true,
                    );
                  }
                }
              : null,
          githubSyncCardBuilder: _token != null
              ? () => GithubSyncExperimentalCard(
                    appId: 'editor',
                    onLoadStatus: () => widget.client.githubSyncStatus(_token!),
                    onListRepos: () => widget.client.githubSyncRepos(_token!),
                    onConnect: ({
                      required String installationId,
                      String? accountLogin,
                      String? repoFullName,
                      String? repoDefaultBranch,
                    }) =>
                        widget.client.githubSyncCallback(_token!, {
                      'installation_id': installationId,
                      if (accountLogin != null && accountLogin.isNotEmpty)
                        'account_login': accountLogin,
                      if (repoFullName != null && repoFullName.isNotEmpty)
                        'repo_full_name': repoFullName,
                      if (repoDefaultBranch != null &&
                          repoDefaultBranch.isNotEmpty)
                        'repo_default_branch': repoDefaultBranch,
                    }),
                    onPushNow: ({bool includeAssets = false}) =>
                        widget.client.githubSyncPush(
                      _token!,
                      includeAssets: includeAssets,
                    ),
                    onDisconnect: () =>
                        widget.client.githubSyncDisconnect(_token!),
                  )
              : null,
          onRestoreDeletedNote: _restoreDeletedNote,
          onEmptyDeletedNotes: _emptyDeletedNotes,
          onCopyLogs: _copyFrontendLogs,
          onUploadAvatar: _uploadAvatar,
          onSyncLocalData: _syncAllLocalData,
          onPullCloudData: _pullCloudNotesToLocal,
          onClearLocalData: _clearLocalData,
          onRestoreTemplateCourses: _restoreTemplateCourses,
          onRestoreLocalStarterTemplate: _restoreLocalStarterTemplate,
          onExportLocalData: _exportLocalArchive,
          onRestoreFromLocalImport: _restoreFromLocalImport,
          onImportAppleJournal: _importAppleJournalArchive,
          onClearLegacyStorage: _clearLegacySharedStorage,
          onReplayTour: _replayOnboarding,
          onSetLocale: _setLocale,
          currentLocale: _localSettings['locale']?.toString() ?? 'system',
          onProbeStorageArch: _probeStorageArch,
          onOpenLocalRecycleBin: _openLocalRecycleBinDialog,
          localTrashedDraftCount: _localTrashedDrafts.length,
          localTrashedCourseCount: _localTrashedCourses.length,
          onOfflineModeChanged: _setOfflineMode,
          localDraftCount: _localDrafts.length,
          localCourseCount: _localCourses.length,
          apiBaseUrl: _localSettings['api_base_url']?.toString() ??
              _httpClient?.baseUrl,
          debugSnapshotListenable: _httpClient?.debugSnapshot,
          debugHistoryListenable: _httpClient?.debugHistory,
          debugLogController: logController,
          uiLogs: uiLogs,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  /// True iff *course* should pin to the top of the sidebar's
  /// Categories block.
  ///
  /// 0.1.120: only the synthetic uncategorized bucket pins. Every
  /// real Course row is freely reorderable now — the pre-refactor
  /// "is_default OR title=='inbox'" heuristic was retired along with
  /// `Course.is_default`.
  bool isCategoryPinned(Map<String, dynamic> course) {
    return course['is_uncategorized'] == true;
  }

  /// Build the synthetic uncategorized folder row that pins to the
  /// top of the sidebar. Carries `is_uncategorized: true` so action
  /// guards can identify it, and a `null` `id` so it never collides
  /// with a real Course row. Label comes from the user's profile
  /// (`Creator.uncategorized_folder_name`, default "Inbox") which the
  /// auth payload exposes verbatim — falls back to "Inbox" when the
  /// payload is missing it (anonymous, or pre-0.1.120 SPA build).
  Map<String, dynamic> buildUncategorizedFolder() {
    final label =
        (_settings?['uncategorized_folder_name']?.toString().trim() ?? '')
                .isNotEmpty
            ? _settings!['uncategorized_folder_name']!.toString().trim()
            : 'Inbox';
    return <String, dynamic>{
      'id': null,
      'title': label,
      'is_uncategorized': true,
    };
  }

  /// Diagnostic: emit a debug-log line per sidebar rebuild that
  /// records `total` categories vs `pinned` count, plus a sample of
  /// the first 5 rows' `id`/`title`/`is_default`/source-list so the
  /// user can paste a single log line that fully describes what's
  /// in their sidebar. Goes warning when `pinned == 0 && total > 0`
  /// — that case is the "Inbox vanished from my sidebar" symptom
  /// users have reported across releases, where the seed flag got
  /// stripped server- or persistence-side. Filter by
  /// `Editor.UI/sidebar.pin_diagnostics` in the Debug Log card to
  /// see the breadcrumbs.
  ///
  /// Throttled: re-emits only when the category set composition
  /// changes (different ids, titles, flags, or list-of-origin). The
  /// dedupe key is parked on `_AppShellState._lastSidebarPinDiagnosticKey`
  /// because Dart extensions cannot declare instance fields. Without
  /// dedupe this fires ~120×/second on a busy editor (every rebuild
  /// of the sidebar tree), drowning the log card.
  void emitSidebarPinDiagnostics({
    required int total,
    required int pinned,
  }) {
    final cats = _allCategories;
    final localIds =
        _localCourses.map((c) => c['id']?.toString() ?? '').toSet();
    String describe(Map<String, dynamic> c) {
      final id = c['id']?.toString() ?? '<noid>';
      final title =
          (c['title']?.toString() ?? '<untitled>').replaceAll('|', '/');
      final isDefault = c['is_default'] == true ? 'default' : 'plain';
      final origin = localIds.contains(id) ? 'local' : 'cloud';
      final pinnedFlag = isCategoryPinned(c) ? 'pin' : 'drag';
      return '#$id "$title" $isDefault/$origin/$pinnedFlag';
    }

    final sampleCount = cats.length > 5 ? 5 : cats.length;
    final sample = [
      for (var i = 0; i < sampleCount; i++) describe(cats[i]),
    ].join(' | ');
    final overflow = cats.length > sampleCount
        ? ' (+${cats.length - sampleCount} more)'
        : '';
    final key =
        'total=$total pinned=$pinned signedIn=${_token != null && _token!.isNotEmpty} '
        'rows=$sample$overflow';
    if (_lastSidebarPinDiagnosticKey == key) return;
    _lastSidebarPinDiagnosticKey = key;
    log(
      level: pinned == 0 && total > 0
          ? DebugLogLevel.warning
          : DebugLogLevel.debug,
      source: 'Editor.UI/sidebar.pin_diagnostics',
      message: 'Sidebar Categories rebuilt: '
          'Editor.UI/sidebar.pin_diagnostics — '
          'total=$total pinned=$pinned signedIn='
          '${_token != null && _token!.isNotEmpty}. '
          'Rows: $sample$overflow. '
          'Pinned counts rows where `is_default == true` OR title '
          'casefolds to "inbox". A `pinned=0` warning with `total>0` '
          'means neither signal matched any row — paste this line so '
          'we can see the actual title/flag/origin tuple. Tap '
          '"Restore default Inbox" in Settings to reseed.',
    );
  }
}
