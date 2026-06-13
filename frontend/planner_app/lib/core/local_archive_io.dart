part of notechondria_frontend;

/// Local archive (.nchron) export + import helpers for the planner app.
/// State mutations go through `refreshState` since extensions can't
/// call `setState` directly.
extension _AppShellLocalArchiveX on _AppShellState {
  /// Exports local planner data as a `.nchron` package.
  Future<void> _exportLocalArchive() async {
    try {
      final username = _profile?['username']?.toString() ?? 'planner';
      final suggestedName = 'notechondria-planner-$username.nchron';
      final archiveBytes = writeLocalArchive(
        LocalArchiveInput(
          app: LocalArchiveApp.planner,
          appVersion: _kAppVersion,
          profile: {
            if (_profile?['username'] != null)
              'username': _profile!['username'],
            if (_profile?['email'] != null) 'email': _profile!['email'],
            if (_profile?['first_name'] != null)
              'first_name': _profile!['first_name'],
            if (_profile?['last_name'] != null)
              'last_name': _profile!['last_name'],
            if (_settings?['motto'] != null) 'motto': _settings!['motto'],
            if (_settings?['social_link'] != null)
              'social_link': _settings!['social_link'],
            if (_profile?['image_url'] != null)
              'image_url': _profile!['image_url'],
          },
          settings: _settings ?? const {},
          localSettings: _localSettings,
          stats: _localStats,
          cache: _localCache,
          courses: _localCourses,
          drafts: _localDrafts,
          logs: uiLogs,
          plannerEvents: _plannerEvents,
          calendarFeeds: _calendarFeeds,
          activityWeek: _activityWeek ?? const {},
        ),
      );
      final location = await getSaveLocation(
        suggestedName: suggestedName,
        acceptedTypeGroups: [
          const XTypeGroup(
              label: 'Notechondria archive', extensions: ['nchron', 'zip']),
        ],
      );
      if (location == null) return;
      final file = XFile.fromData(archiveBytes,
          name: suggestedName, mimeType: 'application/zip');
      await file.saveTo(location.path);
      showMessage(
        'Local data exported: '
        'Planner.LocalStore/export_zip — $suggestedName written '
        '(${archiveBytes.length} bytes).',
      );
      log(
        level: DebugLogLevel.info,
        source: 'Planner.LocalStore/export_zip',
        message: 'Local data exported: '
            'Planner.LocalStore/export_zip — '
            'wrote $suggestedName to disk '
            '(${archiveBytes.length} bytes, '
            '${_localCourses.length} course(s), '
            '${_localDrafts.length} draft(s), '
            '${_plannerEvents.length} event(s)).',
      );
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      showMessage(
        'Local data not exported: '
        'Planner.LocalStore/export_zip — $cause.',
      );
      log(
        level: DebugLogLevel.error,
        source: 'Planner.LocalStore/export_zip',
        message: 'Local data not exported: '
            'Planner.LocalStore/export_zip — $cause.',
      );
    }
  }

  /// Imports a `.nchron` archive, showing a confirmation dialog first.
  Future<void> _restoreFromLocalImport() async {
    try {
      final picked = await openFile(acceptedTypeGroups: const [
        XTypeGroup(
            label: 'Notechondria archive',
            extensions: ['nchron', 'zip', 'env']),
      ]);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();

      final legacy = tryReadLegacyEnvConfig(bytes);
      if (legacy != null) {
        final proceed = await _confirmRestore(
          title: 'Restore from legacy config?',
          message: 'Legacy .env config detected. Only API_BASE_URL / '
              'API_KEY_PREFIX will be applied; local drafts, categories, '
              'and cache stay as they are. Continue?',
          confirmLabel: 'Import',
        );
        if (!proceed) return;
        final apiBase = legacy['API_BASE_URL']?.trim();
        if (apiBase != null && apiBase.isNotEmpty) {
          await _applyLocalAppSettings({'api_base_url': apiBase});
        }
        log(
          level: DebugLogLevel.info,
          source: 'Planner.LocalStore/restore_from_import',
          message: 'Legacy .env imported: '
              'Planner.LocalStore/restore_from_import — '
              '${legacy.length} key(s) applied from config file.',
        );
        showMessage(
          'Legacy config imported: '
          'Planner.LocalStore/restore_from_import — '
          '${legacy.length} key(s) applied.',
        );
        return;
      }

      final parsed = readLocalArchive(bytes);
      if (!parsed.ok) {
        showMessage(parsed.errorMessage!);
        log(
          level: DebugLogLevel.error,
          source: 'Planner.LocalStore/restore_from_import',
          message: parsed.errorMessage!,
        );
        return;
      }

      final counts = parsed.counts;
      final summary = [
        '${counts['courses'] ?? parsed.courses.length} categor(ies)',
        '${counts['drafts'] ?? parsed.drafts.length} draft(s)',
        if ((counts['queued_attachments'] ?? 0) > 0)
          '${counts['queued_attachments']} queued attachment(s)',
        '${counts['logs'] ?? parsed.logs.length} log line(s)',
      ].join(', ');
      final exporterApp = parsed.manifestApp?.tag ?? 'unknown';
      final exportedAt = parsed.exportedAt?.toLocal().toIso8601String() ?? '';
      final proceed = await _confirmRestore(
        title: 'Restore local data?',
        message: 'Archive produced by $exporterApp app ($exportedAt) '
            'contains: $summary. '
            'Continuing will REPLACE your current local drafts, '
            'categories, and cached data with the archive contents.',
        confirmLabel: 'Replace',
        delaySeconds: 5,
      );
      if (!proceed) return;

      _localSettings = {
        ..._LocalAppStore.defaultSettings(),
        ...parsed.localSettings,
      };
      _localStats = {
        ..._LocalAppStore.defaultStats(),
        ...parsed.stats,
      };
      _localCache = {
        ..._LocalAppStore.defaultCache(),
        ...parsed.cache,
      };
      _localCourses = parsed.courses;
      _localDrafts = parsed.drafts;
      uiLogs
        ..clear()
        ..addAll(parsed.logs);
      refreshState();
      logController
        ..replaceAll(parsed.logs.map(DebugLogEntry.fromPersistedString))
        ..bindCacheProvider(_snapshotLocalStore);

      await _LocalAppStore.saveSettings(_localSettings);
      await _LocalAppStore.saveStats(_localStats);
      await _LocalAppStore.saveCache(_localCache);
      await _LocalAppStore.saveCourses(_localCourses);
      await _LocalAppStore.saveDrafts(_localDrafts);
      await _LocalAppStore.saveLogs(uiLogs);

      log(
        level: DebugLogLevel.info,
        source: 'Planner.LocalStore/restore_from_import',
        message: 'Local data restored: '
            'Planner.LocalStore/restore_from_import — '
            'archive from $exporterApp applied ($summary).',
      );
      showMessage(
        'Local data restored: '
        'Planner.LocalStore/restore_from_import — '
        'archive from $exporterApp applied ($summary).',
      );

      await _loadInitialData();
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      showMessage(
        'Local data not restored: '
        'Planner.LocalStore/restore_from_import — $cause.',
      );
      log(
        level: DebugLogLevel.error,
        source: 'Planner.LocalStore/restore_from_import',
        message: 'Local data not restored: '
            'Planner.LocalStore/restore_from_import — $cause.',
      );
    }
  }

  Future<bool> _confirmRestore({
    required String title,
    required String message,
    String confirmLabel = 'Replace',
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
