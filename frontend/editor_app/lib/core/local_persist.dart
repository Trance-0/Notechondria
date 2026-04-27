part of notechondria_frontend;

/// Tiny `_LocalAppStore` persist helpers + debug-terminal cache snapshot
/// + the one-shot 0.1.37 inline-base64 attachment migration. All of these
/// are thin pass-throughs (or nearly so) over in-memory state and
/// `_LocalAppStore` bucket savers — the interesting logic lives in
/// `core/local_store.dart`. Extracted from `app_shell.dart` so that file
/// stays closer to the AGENTS.md §1.5 1000-line ceiling.
extension _AppShellLocalPersistX on _AppShellState {
  // _persistLocalSettings / _persistLocalDrafts / _persistLocalCourses /
  // _persistLocalStats / _persistUiLogs all moved into the shared
  // `AppShellLocalPersistMixin` (notechondria_shared 0.1.78). Call
  // sites use the public `persistLocalSettings()` / etc. names now.

  /// App-specific cache snapshot — editor includes `front_page` +
  /// `courses` in its cache bucket. Stays in this file because the
  /// shape diverges from planner / portal.
  Future<void> _persistLocalCache() async {
    _localCache = {
      ..._localCache,
      'front_page': _frontPage ?? const <String, dynamic>{},
      'courses': _courses,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _LocalAppStore.saveCache(_localCache);
  }

  /// Snapshot of the in-memory "cache" the debug terminal can navigate with
  /// `ls` / `cd`. Mirrors the persistence buckets of `_LocalAppStore`.
  Map<String, Object?> _snapshotLocalStore() {
    return <String, Object?>{
      'settings': _localSettings,
      'drafts': _localDrafts,
      'courses': _localCourses,
      'stats': _localStats,
      'cache': _localCache,
      'logs': uiLogs,
      'session': _token == null
          ? null
          : {
              'token_present': true,
              'profile': _profile ?? const <String, dynamic>{},
            },
    };
  }

  /// One-time shim: walk `_localDrafts`, move any inline base64
  /// queued-attachment payloads into `LocalAttachmentStore`, rewrite
  /// the draft body to use `local://` URLs, and mark the migration
  /// complete in local settings so subsequent boots skip this path.
  Future<void> _migrateAttachmentStoreIfNeeded() async {
    if ((_localSettings['attachment_store_migrated_at']?.toString() ?? '')
        .isNotEmpty) {
      return;
    }
    try {
      final store = await LocalAttachmentStore.open();
      final migrated = await store.migrateBase64Drafts(_localDrafts);
      // migrateBase64Drafts returns a new list only when there is
      // base64 to move; otherwise it hands back the same underlying
      // objects and we skip the re-save.
      if (!identical(migrated, _localDrafts)) {
        _localDrafts = migrated;
        await _LocalAppStore.saveDrafts(_localDrafts);
        refreshState();
      }
      _localSettings = {
        ..._localSettings,
        'attachment_store_migrated_at':
            DateTime.now().toUtc().toIso8601String(),
      };
      await _LocalAppStore.saveSettings(_localSettings);
      log(
        level: DebugLogLevel.info,
        source: 'Editor.LocalStore/attachment_store_migrate',
        message:
            'Attachment store migration complete: '
            'Editor.LocalStore/attachment_store_migrate \u2014 '
            'legacy base64 queued_attachments moved to '
            'LocalAttachmentStore; drafts rewritten to local:// URLs.',
      );
    } catch (error) {
      log(
        level: DebugLogLevel.warning,
        source: 'Editor.LocalStore/attachment_store_migrate',
        message:
            'Attachment store migration deferred: '
            'Editor.LocalStore/attachment_store_migrate \u2014 '
            '${error.toString().replaceFirst('Exception: ', '')}.',
      );
    }
  }
}
