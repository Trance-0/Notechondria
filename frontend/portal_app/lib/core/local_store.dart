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
  final List<Map<String, dynamic>> trashedDrafts;
  final List<Map<String, dynamic>> trashedCourses;
}

class _LocalAppStore {
  static const String _settingsKey = 'notechondria.local_settings';
  static const String _draftsKey = 'notechondria.local_drafts';
  static const String _coursesKey = 'notechondria.local_courses';
  static const String _statsKey = 'notechondria.local_stats';
  static const String _cacheKey = 'notechondria.local_cache';
  static const String _logsKey = 'notechondria.local_logs';
  static const String _trashedDraftsKey =
      'notechondria.local_trashed_drafts';
  static const String _trashedCoursesKey =
      'notechondria.local_trashed_courses';
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

  static List<Map<String, dynamic>> _pruneTrashed(
    List<Map<String, dynamic>> entries,
  ) {
    final threshold = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: _trashTtlDays));
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
