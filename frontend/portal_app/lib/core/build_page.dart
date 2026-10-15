part of notechondria_frontend;

/// Per-tab page switch for the portal shell. Moved verbatim out of
/// `app_shell.dart` in 0.1.198 to keep that file under the AGENTS.md
/// 1000-line cap.
extension _AppShellBuildPageX on _AppShellState {
  Widget _buildPage() {
    switch (_selectedIndex) {
      case 0:
        return _FrontPage(
          frontPage: _frontPage ?? const {},
          profile: _profile,
          apiBaseUrl: _localSettings['api_base_url']?.toString() ??
              _httpClient?.baseUrl,
          onOpenNote: _openNoteViewer,
          onOpenCourse: _selectCourse,
        );
      case 1:
        return _LearnerPage(
          notes: _learnerNotes,
          localDrafts: _localDrafts,
          courses: (_token == null || _token!.isEmpty)
              ? [..._localCourses]
              : [..._localCourses, ..._courses],
          selectedNote: _selectedNote,
          editorMode: _settings?['editor_mode']?.toString() ?? 'P',
          hasMoreNotes: _hasMoreLearnerNotes,
          isLoadingMore: _isLoadingMoreNotes,
          searchQuery: _learnerSearchQuery,
          isAuthenticated: _token != null && _token!.isNotEmpty,
          feedScope: _learnerScope,
          feedSort: _learnerSort,
          feedWindow: _learnerWindow,
          onChangeFeedFilters: ({scope, sort, window}) =>
              _setLearnerFilters(scope: scope, sort: sort, window: window),
          apiBaseUrl: _localSettings['api_base_url']?.toString() ??
              _httpClient?.baseUrl,
          onSearchChanged: (value) =>
              _loadLearnerNotes(reset: true, query: value),
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
      case 2:
        return _CoursePage(
          courses: _courses,
          localCourses: _localCourses,
          selectedCourse: _selectedCourse,
          notes: _courseNotes,
          notesLoading: _courseNotesLoading,
          notesHasMore: _courseNotesHasMore,
          notesLoadingMore: _courseNotesLoadingMore,
          onLoadMoreNotes: _loadMoreCourseNotes,
          localNotes: _localDrafts,
          isAuthenticated: _token != null && _token!.isNotEmpty,
          canCreateLocalCourses: true,
          apiBaseUrl: _localSettings['api_base_url']?.toString() ??
              _httpClient?.baseUrl,
          onCourseChanged: _selectCourse,
          onCreateLocalCourse: _createLocalCourse,
          onSyncLocalData: _syncAllLocalData,
          onSubscribe: _subscribeToCourse,
          onUnsubscribe: _unsubscribeFromCourse,
          onFetchNoteDetail: _fetchNoteDetail,
          onOpenRoutedNote: _openNoteViewer,
          initialModuleKey: widget.initialModuleKey,
          onEditCourse: _updateCourseMeta,
          onTransferCourse: _transferCourseOwnership,
          onImportCourseFromGit: _importCourseFromGit,
        );
      case 3:
        return _ActivityPage(
          activityWeek: _activityWeek,
          isAuthenticated: _token != null && _token!.isNotEmpty,
          plannerEvents: [..._localEvents, ..._plannerEvents],
          courses: (_token == null || _token!.isEmpty)
              ? _localCourses
              : [..._localCourses, ..._courses],
          rangeDays: _activityRangeDays,
          onCreatePlannerEvent: _createPlannerEvent,
          onImportCalendar: _importCalendarFeed,
          onSubscribeCalendar: _subscribeCalendarFeed,
          onNavigateWeek: (direction) => _loadActivityWeek(
            startDate:
                _activityWeekStart.add(Duration(days: direction * _activityRangeDays)),
          ),
          onShiftStartDay: (dayDelta) => _loadActivityWeek(
            startDate: _activityWeekStart.add(Duration(days: dayDelta)),
          ),
          onChangeRange: (days) => _loadActivityWeek(rangeDays: days),
          onTogglePlannerEventCompletion: _togglePlannerEventCompletion,
          onUpdatePlannerEvent: _updatePlannerEvent,
          onEditCourse: _updateCourseMeta,
          onTransferCourse: _transferCourseOwnership,
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
          onReplayTour: _replayOnboarding,
          currentLocale: _localSettings['locale']?.toString() ?? 'system',
          onSetLocale: _setLocale,
          onProbeStorageArch: _probeStorageArch,
          casdoorOrgLoginUrl: _casdoorOrgLoginUrl,
          onCasdoorLogin: () => launchOAuth('casdoor', intent: 'login'),
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
          onRestoreDeletedNote: _restoreDeletedNote,
          onEmptyDeletedNotes: _emptyDeletedNotes,
          onCopyLogs: _copyFrontendLogs,
          onUploadAvatar: _uploadAvatar,
          onSyncLocalData: _syncAllLocalData,
          onPullCloudData: _pullCloudNotesToLocal,
          onClearLocalCache: _clearLocalCache,
          onClearLocalData: _clearLocalData,
          onRestoreTemplateCourses: _restoreTemplateCourses,
          onOpenLocalRecycleBin: _openLocalRecycleBinDialog,
          localTrashedDraftCount: _localTrashedDrafts.length,
          localTrashedCourseCount: _localTrashedCourses.length,
          onOfflineModeChanged: _setOfflineMode,
          onApplyLocalSettings: _applyLocalAppSettings,
          localDraftCount: _localDrafts.length,
          localCourseCount: _localCourses.length,
          apiBaseUrl: _localSettings['api_base_url']?.toString() ??
              _httpClient?.baseUrl,
          debugSnapshotListenable: _httpClient?.debugSnapshot,
          debugHistoryListenable: _httpClient?.debugHistory,
          debugLogController: logController,
          uiLogs: uiLogs,
          onRotateApiKey: _token != null
              ? () async {
                  try {
                    final result = await widget.client.rotateApiKey(_token!);
                    final newPrefix =
                        result['api_key_prefix']?.toString() ?? '';
                    if (newPrefix.isNotEmpty && mounted) {
                      _settings = {
                        ..._settings ?? <String, dynamic>{},
                        'api_key_prefix': newPrefix,
                      };
                      refreshState();
                    }
                    log(
                      level: DebugLogLevel.info,
                      source: 'Portal.UI',
                      message: 'API key rotated: Portal.UI/api_key.rotate — '
                          'new prefix ${newPrefix.isEmpty ? "<unknown>" : newPrefix}; '
                          'the previous key is now invalid.',
                    );
                    return result;
                  } catch (e) {
                    // A stale Casdoor session is the common cause: the app
                    // renders from local cache so it looks signed in, but
                    // this direct server call 401s. Log the effective cause
                    // so the Debug log explains the SnackBar.
                    log(
                      level: DebugLogLevel.warning,
                      source: 'Portal.UI',
                      message: 'API key was NOT rotated: '
                          'Portal.UI/api_key.rotate — '
                          '${e.toString().replaceFirst('Exception: ', '')} '
                          '(if this is a 401, the sign-in session has '
                          'expired — sign in again and retry).',
                    );
                    rethrow;
                  }
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
                          'Portal.Settings/skill.save — $msg.',
                      isError: true,
                    );
                  }
                }
              : null,
          githubSyncCardBuilder: _token != null
              ? () => GithubSyncExperimentalCard(
                    appId: 'portal',
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
          onExportLocalData: _exportLocalArchive,
          onRestoreFromLocalImport: _restoreFromLocalImport,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
