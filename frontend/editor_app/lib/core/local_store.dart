part of notechondria_frontend;

class _LocalAppSnapshot {
  const _LocalAppSnapshot({
    required this.settings,
    required this.drafts,
    required this.courses,
    required this.stats,
    required this.cache,
    required this.logs,
    required this.trashedDrafts,
    required this.trashedCourses,
  });

  final Map<String, dynamic> settings;
  final List<Map<String, dynamic>> drafts;
  final List<Map<String, dynamic>> courses;
  final Map<String, dynamic> stats;
  final Map<String, dynamic> cache;
  final List<String> logs;

  /// Drafts that were successfully synced to the cloud and then moved
  /// to a client-side recycle bin (not deleted). Each entry carries
  /// `trashed_at` (ISO-8601 UTC), the original draft payload, and
  /// `server_note_id` (int) linking to the cloud record that replaced
  /// it. Auto-pruned after [_trashTtlDays] days on next load.
  final List<Map<String, dynamic>> trashedDrafts;

  /// Same idea for local courses after successful cloud promotion.
  final List<Map<String, dynamic>> trashedCourses;
}

class _LocalAppStore {
  // 0.1.127: per-app key namespace. On GitHub Pages (and any
  // single-domain deploy) all three apps share one browser origin,
  // and web SharedPreferences is origin-scoped localStorage — the
  // previous app-agnostic `notechondria.local_*` keys meant editor /
  // planner / portal silently overwrote each other's settings,
  // drafts, courses, and session state (the "multi app auth
  // corrupting" bug). Keys now live under `notechondria.editor.*`;
  // `_migrateLegacyKeys` copies any old unprefixed value into this
  // namespace once. Copy, not move: the other apps migrate the same
  // legacy values into their own namespaces on their next boot, so
  // deleting here would race them. The stale legacy keys are left
  // behind; a future maintenance action may clear them.
  static const String _legacyKeyPrefix = 'notechondria.';
  static const String _keyPrefix = 'notechondria.editor.';
  static const List<String> _migratableKeySuffixes = [
    'local_settings',
    'local_drafts',
    'local_courses',
    'local_stats',
    'local_cache',
    'local_logs',
    'local_trashed_drafts',
    'local_trashed_courses',
    'session',
  ];
  static bool _legacyKeysMigrated = false;

  static Future<void> _migrateLegacyKeys(SharedPreferences prefs) async {
    if (_legacyKeysMigrated) return;
    for (final suffix in _migratableKeySuffixes) {
      final namespacedKey = '$_keyPrefix$suffix';
      if (prefs.containsKey(namespacedKey)) continue;
      final legacy = prefs.getString('$_legacyKeyPrefix$suffix');
      if (legacy == null || legacy.isEmpty) continue;
      await prefs.setString(namespacedKey, legacy);
    }
    _legacyKeysMigrated = true;
  }

  static const String _settingsKey = 'notechondria.editor.local_settings';
  static const String _draftsKey = 'notechondria.editor.local_drafts';
  static const String _coursesKey = 'notechondria.editor.local_courses';
  static const String _statsKey = 'notechondria.editor.local_stats';
  static const String _cacheKey = 'notechondria.editor.local_cache';
  static const String _logsKey = 'notechondria.editor.local_logs';
  static const String _sessionKey = 'notechondria.editor.session';
  // Client-side recycle-bin buckets for just-synced drafts and
  // courses. Populated AFTER a successful cloud create/update so the
  // user can restore if the cloud copy later turns out to be wrong.
  // Auto-pruned after [_trashTtlDays] days on each load.
  static const String _trashedDraftsKey =
      'notechondria.editor.local_trashed_drafts';
  static const String _trashedCoursesKey =
      'notechondria.editor.local_trashed_courses';

  /// Days a just-synced draft/course stays in the local recycle bin
  /// before load-time auto-prune. 30 days balances recoverability
  /// against SharedPreferences footprint.
  static const int _trashTtlDays = 30;

  static Map<String, dynamic> defaultSettings() {
    return {
      'theme_preset': 'teal',
      'theme_mode': 'S',
      'api_base_url': _defaultApiBaseUrl(),
      'offline_mode': false,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'log_preferences': {
        'copy_include_timestamps': true,
      },
    };
  }

  static Map<String, dynamic> defaultStats() {
    return {
      'local_drafts_created': 0,
      'local_drafts_synced': 0,
      'local_courses_created': 0,
      'local_courses_synced': 0,
      'avatar_updates': 0,
      'settings_saves': 0,
      'logs_copied': 0,
      'cache_clears': 0,
      'local_data_clears': 0,
      'sync_failures': 0,
      'last_sync_at': null,
    };
  }

  static Map<String, dynamic> defaultCache() {
    return {
      'front_page': <String, dynamic>{},
      'courses': <Map<String, dynamic>>[],
      'activity': <Map<String, dynamic>>[],
      'updated_at': null,
    };
  }

  static Future<_LocalAppSnapshot> load() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacyKeys(prefs);
    // Prune recycle-bin entries older than [_trashTtlDays] days so
    // the bucket doesn't grow unbounded across sessions.
    final rawTrashedDrafts = _decodeList(prefs.getString(_trashedDraftsKey));
    final rawTrashedCourses = _decodeList(prefs.getString(_trashedCoursesKey));
    final trashedDrafts = _pruneTrashed(rawTrashedDrafts);
    final trashedCourses = _pruneTrashed(rawTrashedCourses);
    if (trashedDrafts.length != rawTrashedDrafts.length) {
      await prefs.setString(_trashedDraftsKey, jsonEncode(trashedDrafts));
    }
    if (trashedCourses.length != rawTrashedCourses.length) {
      await prefs.setString(_trashedCoursesKey, jsonEncode(trashedCourses));
    }
    return _LocalAppSnapshot(
      settings: _decodeMap(prefs.getString(_settingsKey), defaultSettings()),
      drafts: _decodeList(prefs.getString(_draftsKey)),
      courses: _decodeList(prefs.getString(_coursesKey)),
      stats: _decodeMap(prefs.getString(_statsKey), defaultStats()),
      cache: _decodeMap(prefs.getString(_cacheKey), defaultCache()),
      logs: _decodeStringList(prefs.getString(_logsKey)),
      trashedDrafts: trashedDrafts,
      trashedCourses: trashedCourses,
    );
  }

  /// Drops entries whose `trashed_at` is older than [_trashTtlDays]
  /// days. Entries without a parseable `trashed_at` are kept (we
  /// don't want to silently delete data we can't date).
  static List<Map<String, dynamic>> _pruneTrashed(
    List<Map<String, dynamic>> entries,
  ) {
    final threshold =
        DateTime.now().toUtc().subtract(const Duration(days: _trashTtlDays));
    return entries.where((entry) {
      final raw = entry['trashed_at']?.toString();
      if (raw == null || raw.isEmpty) return true;
      final when = DateTime.tryParse(raw)?.toUtc();
      if (when == null) return true;
      return when.isAfter(threshold);
    }).toList(growable: false);
  }

  static Future<void> saveSettings(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings));
  }

  static Future<void> saveDrafts(List<Map<String, dynamic>> drafts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_draftsKey, jsonEncode(drafts));
  }

  static Future<void> saveCourses(List<Map<String, dynamic>> courses) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_coursesKey, jsonEncode(courses));
  }

  static Future<void> saveStats(Map<String, dynamic> stats) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_statsKey, jsonEncode(stats));
  }

  static Future<void> saveCache(Map<String, dynamic> cache) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(cache));
  }

  static Future<void> saveLogs(List<String> logs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_logsKey, jsonEncode(logs));
  }

  static Future<void> saveTrashedDrafts(
    List<Map<String, dynamic>> drafts,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_trashedDraftsKey, jsonEncode(drafts));
  }

  static Future<void> saveTrashedCourses(
    List<Map<String, dynamic>> courses,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_trashedCoursesKey, jsonEncode(courses));
  }

  /// Persists the auth token and profile so the session survives page refresh.
  static Future<void> saveSession(
      String token, Map<String, dynamic> profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _sessionKey,
        jsonEncode({
          'token': token,
          'profile': profile,
        }));
  }

  /// Loads a previously persisted session. Returns null if none exists.
  static Future<Map<String, dynamic>?> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacyKeys(prefs);
    final raw = prefs.getString(_sessionKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['token'] != null) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  /// Clears the persisted session (on logout).
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  static String newDraftId() {
    final random = math.Random();
    return 'draft_${DateTime.now().microsecondsSinceEpoch}_${random.nextInt(1 << 20)}';
  }

  static String newCourseId() {
    final random = math.Random();
    return 'course_${DateTime.now().microsecondsSinceEpoch}_${random.nextInt(1 << 20)}';
  }

  static Map<String, dynamic> _decodeMap(
    String? raw,
    Map<String, dynamic> fallback,
  ) {
    if (raw == null || raw.trim().isEmpty) {
      return Map<String, dynamic>.from(fallback);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return {
          ...fallback,
          ...Map<String, dynamic>.from(decoded),
        };
      }
    } catch (_) {}
    return Map<String, dynamic>.from(fallback);
  }

  static List<Map<String, dynamic>> _decodeList(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  static List<String> _decodeStringList(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((item) => item.toString()).toList();
      }
    } catch (_) {}
    return const [];
  }
}
