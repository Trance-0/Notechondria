part of notechondria_frontend;

class _LocalAppSnapshot {
  const _LocalAppSnapshot({
    required this.settings,
    required this.drafts,
    required this.stats,
  });

  final Map<String, dynamic> settings;
  final List<Map<String, dynamic>> drafts;
  final Map<String, dynamic> stats;
}

class _LocalAppStore {
  static const String _settingsKey = 'notechondria.local_settings';
  static const String _draftsKey = 'notechondria.local_drafts';
  static const String _statsKey = 'notechondria.local_stats';

  static Map<String, dynamic> defaultSettings() {
    return {
      'theme_preset': 'teal',
      'theme_mode': 'S',
      'api_base_url': 'http://localhost:9080/api/v1',
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
      'avatar_updates': 0,
      'settings_saves': 0,
      'logs_copied': 0,
      'last_sync_at': null,
    };
  }

  static Future<_LocalAppSnapshot> load() async {
    final prefs = await SharedPreferences.getInstance();
    return _LocalAppSnapshot(
      settings: _decodeMap(prefs.getString(_settingsKey), defaultSettings()),
      drafts: _decodeList(prefs.getString(_draftsKey)),
      stats: _decodeMap(prefs.getString(_statsKey), defaultStats()),
    );
  }

  static Future<void> saveSettings(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings));
  }

  static Future<void> saveDrafts(List<Map<String, dynamic>> drafts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_draftsKey, jsonEncode(drafts));
  }

  static Future<void> saveStats(Map<String, dynamic> stats) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_statsKey, jsonEncode(stats));
  }

  static String newDraftId() {
    final random = math.Random();
    return 'draft_${DateTime.now().microsecondsSinceEpoch}_${random.nextInt(1 << 20)}';
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
}
