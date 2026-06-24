part of notechondria_frontend;

/// Local archive (.nchron) export + import helpers. Pulls the two
/// ~100-line Settings-page actions out of `app_shell.dart` so that
/// file stays closer to the AGENTS.md §1.5 1000-line ceiling.
///
/// State mutations go through the `refreshState` wrapper on
/// `_AppShellState` because `setState` is `@protected` and unusable
/// from extension methods. See `core/local_trash.dart` for the same
/// pattern.
extension _AppShellLocalArchiveX on _AppShellState {
  /// Exports every persisted local bucket into a `.nchron` v1 zip
  /// package (see `docs/export_format_v1.md`). Profile fields sent
  /// into the archive exclude tokens and API key prefixes by design;
  /// only read-only identity fields are carried so an operator can
  /// inspect who the archive came from.
  Future<void> _exportLocalArchive() async {
    try {
      final username = _profile?['username']?.toString() ?? 'editor';
      final suggestedName = 'notechondria-editor-$username.nchron';
      final archiveBytes = writeLocalArchive(
        LocalArchiveInput(
          app: LocalArchiveApp.editor,
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
        ),
      );
      final location = await getSaveLocation(
        suggestedName: suggestedName,
        acceptedTypeGroups: [
          XTypeGroup(
            label: AppLocalizations.of(context).localArchiveTypeLabel,
            extensions: const ['nchron', 'zip'],
          ),
        ],
      );
      if (location == null) return;
      final file = XFile.fromData(archiveBytes,
          name: suggestedName, mimeType: 'application/zip');
      await file.saveTo(location.path);
      showMessage(
        'Local user data exported: '
        'Editor.LocalStore/export_zip \u2014 $suggestedName written '
        '(${archiveBytes.length} bytes).',
      );
      log(
        level: DebugLogLevel.info,
        source: 'Editor.LocalStore/export_zip',
        message: 'Local user data exported: '
            'Editor.LocalStore/export_zip \u2014 '
            'wrote $suggestedName to disk '
            '(${archiveBytes.length} bytes, '
            '${_localCourses.length} course(s), '
            '${_localDrafts.length} draft(s)).',
      );
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      showMessage(
        'Local user data not exported: '
        'Editor.LocalStore/export_zip \u2014 $cause.',
      );
      log(
        level: DebugLogLevel.error,
        source: 'Editor.LocalStore/export_zip',
        message: 'Local user data not exported: '
            'Editor.LocalStore/export_zip \u2014 $cause.',
      );
    }
  }

  /// Reads a `.nchron` archive the user picks from disk, shows a
  /// confirmation dialog summarizing its contents, and on confirm
  /// wipes local state and replays the archive's buckets into
  /// `_LocalAppStore`.
  Future<void> _restoreFromLocalImport() async {
    try {
      final picked = await openFile(acceptedTypeGroups: [
        XTypeGroup(
          label: AppLocalizations.of(context).localArchiveTypeLabel,
          extensions: const ['nchron', 'zip', 'env'],
        ),
      ]);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();

      // Sniff for legacy .env first so pre-0.1.38 downloads still work.
      final legacy = tryReadLegacyEnvConfig(bytes);
      if (legacy != null) {
        final proceed = await _confirmWithDelay(
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
          source: 'Editor.LocalStore/restore_from_import',
          message: 'Legacy .env imported: '
              'Editor.LocalStore/restore_from_import \u2014 '
              '${legacy.length} key(s) applied from config file.',
        );
        showMessage(
          'Legacy config imported: '
          'Editor.LocalStore/restore_from_import \u2014 '
          '${legacy.length} key(s) applied.',
        );
        return;
      }

      final parsed = readLocalArchive(bytes);
      if (!parsed.ok) {
        showMessage(parsed.errorMessage!);
        log(
          level: DebugLogLevel.error,
          source: 'Editor.LocalStore/restore_from_import',
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
      final proceed = await _confirmWithDelay(
        title: 'Restore local data?',
        message: 'Archive produced by $exporterApp app ($exportedAt) '
            'contains: $summary. '
            'Continuing will REPLACE your current local drafts, '
            'categories, and cached data with the archive contents.',
        confirmLabel: 'Replace',
        delaySeconds: 5,
      );
      if (!proceed) return;

      // Apply buckets. We mutate the in-memory state fields directly
      // (Dart extensions can't call `setState` because it's
      // `@protected`), then trigger a single rebuild via the
      // `refreshState` wrapper left on `_AppShellState`.
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
        source: 'Editor.LocalStore/restore_from_import',
        message: 'Local user data restored: '
            'Editor.LocalStore/restore_from_import \u2014 '
            'archive from $exporterApp applied ($summary).',
      );
      showMessage(
        'Local user data restored: '
        'Editor.LocalStore/restore_from_import \u2014 '
        'archive from $exporterApp applied ($summary).',
      );

      // Refresh downstream UI (learner list, course panel, front page).
      await _loadInitialData();
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      showMessage(
        'Local user data not restored: '
        'Editor.LocalStore/restore_from_import \u2014 $cause.',
      );
      log(
        level: DebugLogLevel.error,
        source: 'Editor.LocalStore/restore_from_import',
        message: 'Local user data not restored: '
            'Editor.LocalStore/restore_from_import \u2014 $cause.',
      );
    }
  }
}
