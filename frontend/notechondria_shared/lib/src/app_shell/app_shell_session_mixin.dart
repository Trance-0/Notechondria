import 'package:flutter/widgets.dart';

import '../components/debug_log.dart';
import 'auth_client.dart';
import '../utils/local_data_ownership.dart';

/// Session-establishment + sign-out flow shared across `_AppShellState`
/// in editor / planner / portal. The biggest cross-app body the
/// 0.1.78–0.1.81 mixin sweep had left to land — `applyAuthPayload`
/// (~120 lines per app) and `logout` (~35 lines per app), invoked
/// from password login, OAuth, email-verify, and session-restore.
///
/// What this mixin owns:
///   - **`applyAuthPayload(payload)`** — fetches the user's server
///     `/settings/`, reconciles client-vs-server `app_settings`
///     timestamps, applies local theme + log-preference settings,
///     stamps `token` / `profile` / `settings` on the State, fires
///     `loadInitialData()`, and pushes any locally-created courses
///     and drafts. On a 401 / 5xx during settings fetch, falls back
///     to cached local settings so the user still gets a usable
///     session.
///   - **`logout()`** — calls the backend logout endpoint
///     (best-effort), clears `token` / `profile` / `settings` /
///     `deletedNotes`, fires `loadInitialData()` to drop back to the
///     anonymous view, surfaces a "Signed out" snackbar.
///
/// Five hooks the implementing State customises:
///   - `applySessionMetadata(payload)` — editor uses this to
///     populate `_currentSessionId` / `_multiDevice` /
///     `_otherSessionsCount` from the 0.1.65 multi-device payload
///     shape. Planner / portal default no-op (no multi-device UI
///     yet).
///   - `clearSessionMetadata()` — editor uses this to reset the
///     same three fields on logout. Planner / portal no-op.
///   - `clearAppSpecificSessionFields()` — planner / portal use
///     this to reset `_plannerEvents` on logout. Editor no-op.
///   - `persistSession(token, user)` — editor calls
///     `_LocalAppStore.saveSession`. Planner / portal default
///     no-op (they don't persist the session token client-side
///     yet — see 0.1.82.md notes).
///   - `clearPersistedSession()` — editor calls
///     `_LocalAppStore.clearSession`. Same per-app pattern.
///
/// Five per-app methods passed through to the State's own helpers:
///   - `currentAppSettingsPayload({...})` — builds the
///     `app_settings` map sent to the server. Lives in each app's
///     `core/settings_helpers.dart`.
///   - `applyLocalAppSettings(settings, {persist})` — mutates
///     `localSettings`, retunes the http client base URL, fires
///     `widget.onThemeChanged`. Lives in each app's
///     `core/settings_helpers.dart`.
///   - `loadInitialData()` — top-level boot loader. Lives in each
///     app's `core/initial_data.dart`.
///   - `syncAllLocalCourses()` / `syncAllLocalDrafts()` — push any
///     offline-created content after sign-in. Live in each app's
///     `core/maintenance_actions.dart`.
mixin AppShellSessionMixin<W extends StatefulWidget> on State<W> {
  // ---- State the mixin reads + writes ---------------------------
  // Read getters duplicate the declarations on
  // `AppShellAuthActionsMixin.token` and
  // `AppShellLocalPersistMixin.localSettings`. Re-declaring them
  // here keeps the mixin self-contained — a single override on the
  // State satisfies both mixins.

  /// The current bearer token, or null when signed out.
  String? get token;
  set token(String? value);

  /// The signed-in user's profile Map, or null when signed out.
  Map<String, dynamic>? get profile;
  set profile(Map<String, dynamic>? value);

  /// The signed-in user's full settings Map (server-fetched +
  /// local merge), or null when signed out.
  Map<String, dynamic>? get settings;
  set settings(Map<String, dynamic>? value);

  /// In-memory client-side settings. Read by `applyAuthPayload` to
  /// seed the server-app-settings reconcile, written by
  /// `applyLocalAppSettings`.
  Map<String, dynamic> get localSettings;

  /// Server-side soft-deleted notes list. Logout clears it; the
  /// next boot fetches a fresh copy from `/notes/deleted/`.
  List<Map<String, dynamic>> get deletedNotes;
  set deletedNotes(List<Map<String, dynamic>> value);

  // ---- Per-app abstract surface ---------------------------------

  /// `'Editor'` / `'Planner'` / `'Portal'`. Drives log source tags
  /// like `Editor.Auth/applyAuthPayload`. Same getter as
  /// `AppShellLogMixin.logAppTag`; a single override on the State
  /// satisfies both.
  String get logAppTag;

  /// The HTTP client this app uses. Read for `client.getSettings`,
  /// `client.updateSettings`, `client.logout`. Same getter as
  /// `AppShellAuthActionsMixin.authClient`; a single override
  /// satisfies both.
  AuthClient get authClient;

  /// Per-app forwarder to the State's `_currentAppSettingsPayload`
  /// (in `core/settings_helpers.dart`).
  Map<String, dynamic> currentAppSettingsPayload({
    String? themePreset,
    String? themeMode,
    String? apiBaseUrl,
  });

  /// Per-app forwarder to the State's `_applyLocalAppSettings`.
  Future<void> applyLocalAppSettings(
    Map<String, dynamic> settings, {
    bool persist = true,
  });

  /// Per-app forwarder to the State's `_loadInitialData`.
  Future<void> loadInitialData();

  /// Per-app forwarder to the State's `_syncAllLocalCourses`.
  Future<void> syncAllLocalCourses();

  /// Per-app forwarder to the State's `_syncAllLocalDrafts`.
  Future<void> syncAllLocalDrafts();

  // ---- Hooks for per-app session-shape divergences --------------

  /// Read multi-device session metadata out of the auth payload.
  /// Editor populates `_currentSessionId` / `_multiDevice` /
  /// `_otherSessionsCount` here. Planner / portal default no-op.
  void applySessionMetadata(Map<String, dynamic> payload) {}

  /// Reset multi-device session metadata fields. Editor clears its
  /// three fields; planner / portal default no-op.
  void clearSessionMetadata() {}

  /// Reset per-app fields cleared on logout. Planner / portal use
  /// this to clear `_plannerEvents`; editor default no-op.
  void clearAppSpecificSessionFields() {}

  /// Persist the session to durable storage so subsequent cold
  /// boots can restore it. Editor calls
  /// `_LocalAppStore.saveSession(token, user)`; planner / portal
  /// default no-op (they don't persist the token client-side —
  /// every boot re-authenticates instead).
  Future<void> persistSession(String token, Map<String, dynamic> user) async {}

  /// Clear the persisted session. Editor calls
  /// `_LocalAppStore.clearSession()`; planner / portal default
  /// no-op.
  Future<void> clearPersistedSession() async {}

  // ---- Helpers expected from sibling mixins ---------------------
  // These ARE provided by `AppShellLogMixin` already on every
  // implementing State, so re-declaring them here is just a
  // documentation aid — Dart doesn't enforce a transitive `on`
  // constraint, but every State that mixes in
  // `AppShellSessionMixin` should also mix in `AppShellLogMixin`.

  /// Triggers a rebuild after mutating mixin-controlled fields.
  void refreshState();

  /// Info / warning / error sink. See `AppShellLogMixin.log`.
  void log({
    required String message,
    DebugLogLevel level,
    String source,
    int? durationMs,
  });

  /// Snackbar-style user-visible message. See
  /// `AppShellLogMixin.showMessage`.
  void showMessage(String message);

  // ---- Implementations ------------------------------------------

  /// Establishes a new session from a backend auth-payload (keys:
  /// `token`, `user`, optional `multi_device` / `other_sessions_count`
  /// / `session.id` for editor's 0.1.65 multi-device manager). See
  /// the mixin doc-comment for the full flow.
  Future<void> applyAuthPayload(Map<String, dynamic> payload) async {
    final token = payload['token']?.toString() ?? '';
    final user = Map<String, dynamic>.from(payload['user'] as Map? ?? {});
    // Diagnostic breadcrumb (since 0.1.117): record what the backend
    // actually returned in the auth payload so the operator can
    // confirm post-OAuth provisioning succeeded without having to
    // inspect the network panel. The token is truncated to a
    // prefix-suffix tuple so a captured log line never carries the
    // full bearer credential — enough to tell the JWT/Bearer/DRF
    // scheme apart and correlate against backend logs.
    final tokenLen = token.length;
    final tokenPreview = tokenLen <= 18
        ? token // short DRF hex - safe to log in full
        : '${token.substring(0, 12)}…${token.substring(tokenLen - 6)}';
    final tokenScheme = token.startsWith('eyJ')
        ? 'JWT (Bearer)'
        : token.startsWith('ntc_')
            ? 'API key (Bearer)'
            : tokenLen == 40
                ? 'DRF authtoken hex (Token)'
                : 'unknown shape';
    final payloadKeys = payload.keys.toList(growable: false)..sort();
    final userFields = user.entries
        .where((e) => e.key != 'image_url') // skip long URLs
        .map((e) {
      final v = e.value;
      String preview;
      if (v == null) {
        preview = 'null';
      } else if (v is String) {
        preview = v.length > 60 ? '"${v.substring(0, 60)}…"' : '"$v"';
      } else if (v is bool || v is num) {
        preview = v.toString();
      } else if (v is Map) {
        preview = 'Map(${v.length} key${v.length == 1 ? "" : "s"})';
      } else if (v is List) {
        preview = 'List(${v.length})';
      } else {
        preview = v.runtimeType.toString();
      }
      return '${e.key}=$preview';
    }).join(', ');
    log(
      level: DebugLogLevel.debug,
      source: '$logAppTag.Auth/applyAuthPayload.captured',
      message: 'Auth payload received: '
          '$logAppTag.Auth/applyAuthPayload.captured — '
          'token=$tokenPreview (len=$tokenLen, scheme=$tokenScheme); '
          'payload keys=[${payloadKeys.join(", ")}]; '
          'user fields={$userFields}.',
    );
    Map<String, dynamic> serverSettings;
    try {
      serverSettings = await authClient.getSettings(token);
      final localUpdated =
          _parseUpdatedAt(localSettings['updated_at']?.toString());
      final serverUpdated = _parseUpdatedAt(
          serverSettings['app_settings_updated_at']?.toString());
      if (localUpdated.isAfter(serverUpdated)) {
        // Local app-settings are newer — push them up so the
        // server's copy reflects the user's most recent client-side
        // tweaks.
        serverSettings = await authClient.updateSettings(token, {
          'app_settings': currentAppSettingsPayload(),
          'app_settings_updated_at': localSettings['updated_at'],
          'theme_preset': localSettings['theme_preset'],
          'theme_mode': localSettings['theme_mode'],
          'api_base_url': localSettings['api_base_url'],
        });
      } else {
        // Server settings are newer (or equal) — apply them
        // locally. Note: `api_base_url` is CLIENT-side state — we
        // never overwrite the local value with whatever the server
        // sent. The server's creator.api_base_url defaults to
        // "http://localhost:9080/api/v1" on Django, and we don't
        // want that to clobber the user's actual API URL on every
        // login. See 0.1.66.md for the full root cause.
        final serverAppSettings = Map<String, dynamic>.from(
          serverSettings['app_settings'] as Map? ??
              currentAppSettingsPayload(
                themePreset: serverSettings['theme_preset']?.toString(),
                themeMode: serverSettings['theme_mode']?.toString(),
                apiBaseUrl: localSettings['api_base_url']?.toString(),
              ),
        )..['api_base_url'] = localSettings['api_base_url'];
        await applyLocalAppSettings({
          ...serverAppSettings,
          'updated_at': serverSettings['app_settings_updated_at']?.toString() ??
              DateTime.now().toUtc().toIso8601String(),
        });
      }
    } catch (error) {
      // Server unreachable / 401 / 5xx — fall back to cached local
      // settings so the user still gets a usable session.
      serverSettings = {
        'username': user['username'],
        'email': user['email'],
        'editor_mode': settings?['editor_mode'] ?? 'P',
        'theme_preset': localSettings['theme_preset'],
        'theme_mode': localSettings['theme_mode'],
        'api_base_url': localSettings['api_base_url'],
        'app_settings': currentAppSettingsPayload(),
        'app_settings_updated_at': localSettings['updated_at'] ??
            DateTime.now().toUtc().toIso8601String(),
      };
      log(
        level: DebugLogLevel.warning,
        source: '$logAppTag.Sync.Settings/bootstrap',
        message: 'Remote settings unavailable right after login: '
            '$logAppTag.Sync.Settings/bootstrap — '
            '${error.toString().replaceFirst('Exception: ', '')}. '
            'Using cached local settings.',
      );
    }
    this.token = token;
    profile = user;
    settings = serverSettings;
    applySessionMetadata(payload);
    refreshState();
    await persistSession(token, user);
    final foreignLocalData = await _reconcileLocalDataOwner(user);
    await applyLocalAppSettings({
      'theme_preset': serverSettings['theme_preset']?.toString() ??
          localSettings['theme_preset'],
      'theme_mode': serverSettings['theme_mode']?.toString() ??
          localSettings['theme_mode'],
      // api_base_url is client-side state only — see comment above.
      'api_base_url': localSettings['api_base_url'],
      'updated_at': serverSettings['app_settings_updated_at']?.toString() ??
          localSettings['updated_at'],
      'log_preferences': Map<String, dynamic>.from(
        (serverSettings['app_settings'] as Map?)?['log_preferences'] as Map? ??
            localSettings['log_preferences'] as Map? ??
            {},
      ),
    });
    await loadInitialData();
    // Push any local courses + drafts created offline. Skip
    // `_syncAllLocalData`'s inner `loadInitialData` call to avoid
    // the double-bootstrap race that made first login fall over
    // when a single flaky 401 tripped sessionRejected and nuked
    // the fresh token.
    try {
      // Cross-user offline-cache guard (#13): never auto-push local data
      // that belongs to a different user into the account just signed in.
      if (!foreignLocalData) {
        await syncAllLocalCourses();
        await syncAllLocalDrafts();
      }
    } catch (error) {
      log(
        level: DebugLogLevel.warning,
        source: '$logAppTag.Sync.Notes/push_all',
        message: 'Local push after login failed: '
            '$logAppTag.Sync.Notes/push_all — '
            '${error.toString().replaceFirst('Exception: ', '')}. '
            'Will retry on next manual sync.',
      );
    }
    final displayName =
        user['username']?.toString() ?? user['email']?.toString() ?? 'user';
    log(
      level: DebugLogLevel.info,
      source: '$logAppTag.Auth/applyAuthPayload',
      message: 'Session established: $logAppTag.Auth/applyAuthPayload — '
          'authenticated as $displayName.',
    );
    if (mounted) {
      showMessage('Signed in as $displayName.');
    }
  }

  /// Tears down the current session: best-effort cloud logout, then
  /// clear `token` / `profile` / `settings` / `deletedNotes` plus
  /// per-app session metadata, drop the persisted session, and
  /// refire `loadInitialData()` so the UI lands on the anonymous
  /// front page.
  Future<void> logout() async {
    final currentToken = token;
    if (currentToken == null || currentToken.isEmpty) return;
    try {
      await authClient.logout(currentToken);
    } catch (error) {
      log(
        level: DebugLogLevel.warning,
        source: '$logAppTag.Auth/logout',
        message: 'Cloud logout call failed but local session cleared anyway: '
            '$logAppTag.Auth/logout — '
            '${error.toString().replaceFirst('Exception: ', '')}.',
      );
    }
    token = null;
    profile = null;
    settings = null;
    deletedNotes = const [];
    clearSessionMetadata();
    clearAppSpecificSessionFields();
    refreshState();
    await clearPersistedSession();
    await loadInitialData();
    showMessage(
      'Signed out: $logAppTag.Auth/logout — local session cleared.',
    );
    log(
      level: DebugLogLevel.info,
      source: '$logAppTag.Auth/logout',
      message: 'Signed out: $logAppTag.Auth/logout — local session cleared.',
    );
  }

  /// Trivial ISO-8601 parser used by the settings-timestamp
  /// reconcile in `applyAuthPayload`. Same body in all three apps;
  /// inlined here so the mixin is self-contained.
  DateTime _parseUpdatedAt(String? raw) {
    return DateTime.tryParse(raw ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  /// Cross-user offline-cache guard (0.1.192): stamp the local data with
  /// the signed-in user, or — if it already belongs to someone else —
  /// flag it so the sync path refuses to push it and the user is warned.
  /// See [resolveLocalDataOwner].
  /// Returns true when the device's local data belongs to a DIFFERENT
  /// user, in which case the caller must NOT auto-push it to the cloud.
  Future<bool> _reconcileLocalDataOwner(Map<String, dynamic> user) async {
    final username = user['username']?.toString() ?? '';
    if (username.isEmpty) return false;
    final recorded = localSettings['local_data_owner']?.toString();
    final decision =
        resolveLocalDataOwner(recordedOwner: recorded, currentUser: username);
    switch (decision.status) {
      case LocalDataOwnership.claimed:
      case LocalDataOwnership.sameUser:
        // Same user (or first claim): own the data, clear any prior flag.
        if ((localSettings['local_data_owner']?.toString() ?? '') !=
                decision.owner ||
            (localSettings['foreign_local_data_owner']?.toString() ?? '')
                .isNotEmpty) {
          await applyLocalAppSettings({
            'local_data_owner': decision.owner,
            'foreign_local_data_owner': '',
          });
        }
        return false;
      case LocalDataOwnership.foreignUser:
        // Different user's cache on this device. Do NOT retag it (that
        // would let it sync as the new user's) — flag it so
        // `_syncAllLocalData` refuses and warn the person signing in.
        await applyLocalAppSettings({
          'foreign_local_data_owner': decision.priorOwner,
        });
        log(
          level: DebugLogLevel.warning,
          source: '$logAppTag.Auth/local_data_owner',
          message: 'Foreign offline data detected: '
              '$logAppTag.Auth/local_data_owner — local drafts on this '
              'device belong to "${decision.priorOwner}", not "$username"; '
              'they will not sync to this account.',
        );
        if (mounted) {
          showMessage(
            'Heads up: offline notes on this device belong to '
            '"${decision.priorOwner}". They will NOT sync to your account. '
            'Clear local data (Settings) or sign in as '
            '"${decision.priorOwner}" to keep them.',
          );
        }
        return true;
    }
  }

}
