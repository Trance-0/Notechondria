part of notechondria_frontend;

/// App-settings helpers.
extension _AppShellSettingsHelpersX on _AppShellState {
  Map<String, dynamic> _currentAppSettingsPayload({
    String? themePreset,
    String? themeMode,
    String? apiBaseUrl,
  }) {
    final existingLogPrefs = Map<String, dynamic>.from(
        _localSettings['log_preferences'] as Map? ?? {});
    final effectiveApiBase =
        (apiBaseUrl ?? _localSettings['api_base_url'] ?? _defaultApiBaseUrl())
            .toString()
            .trim();
    return {
      'theme_preset': themePreset ?? _localSettings['theme_preset'] ?? 'teal',
      'theme_mode': themeMode ?? _localSettings['theme_mode'] ?? 'S',
      'api_base_url': effectiveApiBase.startsWith('/')
          ? _defaultApiBaseUrl()
          : effectiveApiBase,
      'log_preferences': existingLogPrefs,
    };
  }

  Future<void> _applyLocalAppSettings(Map<String, dynamic> settings,
      {bool persist = true}) async {
    final normalizedApiBase = (settings['api_base_url']?.toString() ??
            _localSettings['api_base_url']?.toString() ??
            _defaultApiBaseUrl())
        .trim();
    _localSettings = {
      ..._localSettings,
      ...settings,
      'api_base_url': normalizedApiBase.startsWith('/')
          ? _defaultApiBaseUrl()
          : normalizedApiBase,
    };
    _httpClient?.updateBaseUrl(
      _localSettings['api_base_url']?.toString() ?? _defaultApiBaseUrl(),
    );
    widget.onThemeChanged?.call(
      _localSettings['theme_preset']?.toString() ?? 'teal',
      _localSettings['theme_mode']?.toString() ?? 'S',
    );
    widget.onLocaleChanged?.call(
      _localSettings['locale']?.toString() ?? 'system',
    );
    if (persist) {
      await persistLocalSettings();
    }
  }

  /// Apply + persist a Language change immediately (mirrors the editor's
  /// `_setLocale`). `_applyLocalAppSettings` fires `onLocaleChanged`,
  /// rebuilding `MaterialApp` with the new locale.
  Future<void> _setLocale(String locale) async {
    await _applyLocalAppSettings({'locale': locale});
    log(
      level: DebugLogLevel.info,
      source: 'Planner.Sync.Settings/locale',
      message: 'Language changed: Planner.Sync.Settings/locale — '
          'app locale set to "$locale".',
    );
  }

  /// Toggles the offline-mode flag. Persists via
  /// `_applyLocalAppSettings` so SharedPreferences picks it up, then
  /// re-runs `_loadInitialData` so the new mode takes effect without
  /// forcing the user to restart the app.
  Future<void> _setOfflineMode(bool offlineMode) async {
    await _applyLocalAppSettings({'offline_mode': offlineMode});
    log(
      level: DebugLogLevel.info,
      source: 'Planner.Sync.Settings/offline_mode',
      message: offlineMode
          ? 'Offline mode enabled: Planner.Sync.Settings/offline_mode \u2014 '
              'remote fetches will be skipped at startup.'
          : 'Offline mode disabled: Planner.Sync.Settings/offline_mode \u2014 '
              'remote fetches re-enabled.',
    );
    await _loadInitialData();
  }

  /// Probes the configured backend's handshake for its media-storage
  /// architecture label (e.g. "Cloudflare R2"), shown on the storage
  /// card. Returns null on any failure (offline, old backend). Mirrors
  /// the editor's `_probeStorageArch`.
  Future<String?> _probeStorageArch() async {
    final url =
        _localSettings['api_base_url']?.toString() ?? _defaultApiBaseUrl();
    try {
      final result = await widget.client.verifyHandshake(url);
      if (!result.ok) return null;
      return result.storageLabel.isEmpty ? null : result.storageLabel;
    } catch (_) {
      return null;
    }
  }

  /// Probe the backend's running version + compat floor for the
  /// version-update banner. Returns null when the backend is
  /// unreachable (banner then shows nothing).
  Future<BackendVersionInfo?> _probeBackendVersion() async {
    final url =
        _localSettings['api_base_url']?.toString() ?? _defaultApiBaseUrl();
    try {
      final result = await widget.client.verifyHandshake(url);
      if (!result.ok || result.version.isEmpty) return null;
      return BackendVersionInfo(
        version: result.version,
        minFrontendVersion: result.minFrontendVersion,
      );
    } catch (_) {
      return null;
    }
  }
}
