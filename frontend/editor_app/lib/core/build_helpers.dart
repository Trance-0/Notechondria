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
    // Show current folder/category name instead of app title.
    String compactTitle;
    if (_selectedIndex == 1) {
      if (_selectedCategoryId != null) {
        compactTitle = _selectedCourse?['title']?.toString() ?? 'Category';
      } else {
        compactTitle = 'All Notes';
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
            tooltip: 'Navigation',
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
                  label: 'All Notes',
                  selected:
                      _selectedIndex == 1 && _selectedCategoryId == null,
                  onTap: () {
                    Navigator.of(context).pop(); // close drawer
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
                              'Categories',
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
                      final pinned = _allCategories
                          .where((c) => c['is_default'] == true)
                          .toList(growable: false);
                      final draggable = _allCategories
                          .where((c) => c['is_default'] != true)
                          .toList(growable: false);
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
                              padding:
                                  const EdgeInsets.fromLTRB(12, 0, 12, 0),
                              buildDefaultDragHandles: false,
                              itemCount: draggable.length,
                              onReorder: (oldIndex, newIndex) {
                                if (newIndex > oldIndex) newIndex -= 1;
                                final reordered =
                                    List<Map<String, dynamic>>.from(
                                        draggable);
                                final moved =
                                    reordered.removeAt(oldIndex);
                                reordered.insert(newIndex, moved);
                                _reorderCategories(
                                    [...pinned, ...reordered]);
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
                                      padding:
                                          const EdgeInsets.only(bottom: 4),
                                      child: ReorderableDragStartListener(
                                        index: index,
                                        child:
                                            _buildDrawerCategoryRow(cat),
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
                              label: 'New category',
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
                    label: 'New category',
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
                  label: 'Settings',
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
                      label: 'All Notes',
                      selected: _selectedIndex == 1 &&
                          _selectedCategoryId == null,
                      onTap: () {
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
                                  'Categories',
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
                          // Pin the default (Inbox) category at the top so it
                          // stays out of the drag-reorder zone.
                          final pinned = _allCategories
                              .where((c) => c['is_default'] == true)
                              .toList(growable: false);
                          final draggable = _allCategories
                              .where((c) => c['is_default'] != true)
                              .toList(growable: false);
                          return Column(
                            children: [
                              for (var ci = 0; ci < pinned.length; ci++)
                                _StaggeredFadeIn(
                                  index: ci,
                                  slideOffset: const Offset(0.06, 0),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        12, 0, 12, 4),
                                    child: _buildCategoryRow(pinned[ci]),
                                  ),
                                ),
                              Expanded(
                                child: ReorderableListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                      12, 0, 12, 0),
                                  buildDefaultDragHandles: false,
                                  itemCount: draggable.length,
                                  onReorder: (oldIndex, newIndex) {
                                    // Flutter's ReorderableListView passes
                                    // newIndex as the target slot *before*
                                    // removal, so shift it left when moving
                                    // down the list.
                                    if (newIndex > oldIndex) newIndex -= 1;
                                    final reordered = List<Map<String, dynamic>>
                                        .from(draggable);
                                    final moved = reordered.removeAt(oldIndex);
                                    reordered.insert(newIndex, moved);
                                    // _reorderCategories synchronously updates
                                    // _localCourses/_courses via setState, so
                                    // the next rebuild already reflects the
                                    // new order — no local mutation needed.
                                    _reorderCategories([...pinned, ...reordered]);
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
                                          padding: const EdgeInsets.only(bottom: 4),
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
                                padding: const EdgeInsets.fromLTRB(
                                    12, 4, 12, 8),
                                child: SidebarItem(
                                  icon: Icons.add_circle_outline,
                                  label: 'New category',
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
                        label: 'New category',
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
                      label: 'Settings',
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
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
                  if (_isLoading)
                    const LinearProgressIndicator(minHeight: 2),
                  if (_errorMessage != null)
                    Material(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Icon(Icons.cloud_off_outlined,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer),
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
                                child: const Text('Retry')),
                            IconButton(
                              onPressed: () {
                                _errorMessage = null;
                                refreshState();
                              },
                              icon: const Icon(Icons.close),
                              tooltip: 'Dismiss',
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
        return _LearnerPage(
          notes: _learnerNotes,
          localDrafts: _localDrafts,
          courses: [..._localCourses, ..._courses],
          selectedNote: _selectedNote,
          editorMode: _settings?['editor_mode']?.toString() ?? 'P',
          hasMoreNotes: _hasMoreLearnerNotes,
          isLoadingMore: _isLoadingMoreNotes,
          searchQuery: _learnerSearchQuery,
          searchScope: _learnerSearchScope,
          isAuthenticated: _token != null && _token!.isNotEmpty,
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
          onLogEvent: appendUiLog,
          onUploadAttachment: _uploadNoteAttachment,
        );
      case 4:
        return _SettingsPage(
          profile: _profile,
          settings: _settings,
          localSettings: _localSettings,
          localStats: _localStats,
          deletedNotes: _deletedNotes,
          onSave: _updateSettings,
          onLogout: _logout,
          onRegister: _register,
          onValidateInvitation: (code) => widget.client.validateInvitation(code),
          onVerify: _verify,
          onResendVerification: _resendVerification,
          onLogin: _login,
          onRequestPasswordReset: _requestPasswordReset,
          onConfirmPasswordReset: _confirmPasswordReset,
          onGoogleLogin: (invitationCode) => _launchOAuth('google', invitationCode: invitationCode),
          onGithubLogin: (invitationCode) => _launchOAuth('github', invitationCode: invitationCode),
          onGoogleLoginOnly: () => _launchOAuth('google', intent: 'login'),
          onGithubLoginOnly: () => _launchOAuth('github', intent: 'login'),
          onBindGoogle: () => _launchOAuth('google', intent: 'bind'),
          onBindGithub: () => _launchOAuth('github', intent: 'bind'),
          onListSocialAccounts: _token != null ? () => widget.client.listSocialAccounts(_token!) : null,
          onUnlinkSocialAccount: _token != null ? (provider) => widget.client.unlinkSocialAccount(_token!, provider) : null,
          onSendIdentityCode: _token != null ? () => widget.client.sendIdentityCode(_token!) : null,
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
          onChangePassword: _token != null ? (current, newPw, identityCode) => widget.client.changePassword(_token!, current, newPw, identityCode) : null,
          onChangeEmailRequest: _token != null ? (email, identityCode) => widget.client.changeEmailRequest(_token!, email, identityCode) : null,
          onChangeEmailConfirm: _token != null ? (email, code) => widget.client.changeEmailConfirm(_token!, email, code) : null,
          onRestoreDeletedNote: _restoreDeletedNote,
          onEmptyDeletedNotes: _emptyDeletedNotes,
          onCopyLogs: _copyFrontendLogs,
          onUploadAvatar: _uploadAvatar,
          onSyncLocalData: _syncAllLocalData,
          onPullCloudData: _pullCloudNotesToLocal,
          onClearLocalData: _clearLocalData,
          onRestoreTemplateCourses: _restoreTemplateCourses,
          onExportLocalData: _exportLocalArchive,
          onRestoreFromLocalImport: _restoreFromLocalImport,
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
}
