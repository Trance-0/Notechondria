import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'folder_messages.dart';

// Storage-mode decision before the first request (modes and migration 2.8)
// and the shared key of 2.10.

/// Origin-wide record of the connected folder (2.10).
const String kSharedStorageModeKey = 'notechondria.shared.storage_mode';

/// Set once the shared-origin notice (6.1 mitigation 2) was acknowledged.
const String kLocalFolderNoticeAckKey =
    'notechondria.shared.local_folder_notice_ack';

/// T7(a): the one table of saved cloud sessions, keyed by app id. Each
/// entry lists the keys exactly as the app's `loadSession` reads them: the
/// editor reads `notechondria.editor.session`, or, when that key is absent,
/// the legacy `notechondria.session` that `_migrateLegacyKeys` would copy
/// into it (editor `core/local_store.dart:61-71`, `:287-299`); the portal
/// reads `notechondria.portal.session` (portal `core/local_store.dart:76`);
/// the planner keeps its session in memory only.
const Map<String, ({String key, String? legacyKey})?> kAppSessionKeys = {
  'editor': (key: 'notechondria.editor.session', legacyKey: 'notechondria.session'),
  'portal': (key: 'notechondria.portal.session', legacyKey: null),
  'planner': null,
};

/// The `<App>` module prefix of an app id (`editor` -> `Editor`).
String appModuleOf(String app) =>
    app.isEmpty ? app : '${app[0].toUpperCase()}${app.substring(1)}';

enum StorageMode { browserOrCloud, folder }

/// The shared key's value: `{"mode": "folder", "folder_id", "folder_name",
/// "connected_by", "connected_at", "remember"}`. [remember] is T3's
/// "Remember this folder on this browser" choice.
class StorageModeRecord {
  const StorageModeRecord({
    required this.folderId,
    required this.folderName,
    required this.connectedBy,
    required this.connectedAt,
    required this.remember,
  });

  final String folderId;
  final String folderName;
  final String connectedBy;
  final String connectedAt;
  final bool remember;

  static StorageModeRecord? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map || json['mode'] != 'folder') return null;
      final id = json['folder_id'];
      if (id is! String || id.isEmpty) return null;
      return StorageModeRecord(
        folderId: id,
        folderName: (json['folder_name'] as String?) ?? '',
        connectedBy: (json['connected_by'] as String?) ?? '',
        connectedAt: (json['connected_at'] as String?) ?? '',
        remember: json['remember'] == true,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  String encode() => jsonEncode({
        'mode': 'folder',
        'folder_id': folderId,
        'folder_name': folderName,
        'connected_by': connectedBy,
        'connected_at': connectedAt,
        'remember': remember,
      });
}

/// The values `preload` read, frozen for the synchronous decision.
class LocalFolderBootSnapshot {
  const LocalFolderBootSnapshot(this.values, {this.error});

  const LocalFolderBootSnapshot.empty({this.error}) : values = const {};

  final Map<String, String> values;

  /// Why browser storage could not be read, when it could not.
  final Object? error;

  bool containsKey(String key) => values.containsKey(key);
  String? getString(String key) => values[key];
}

class LocalFolderBoot {
  LocalFolderBoot._();

  /// Set by [preload]; null before it ran (today's widget tests).
  static LocalFolderBootSnapshot? snapshot;

  /// `runGuardedApp(prepare:)` hook (2.8): loads `SharedPreferences` once.
  /// Catches its own errors; the snapshot is then empty, so the mode is
  /// `browserOrCloud`.
  static Future<void> preload() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final values = <String, String>{};
      for (final key in _bootKeys) {
        if (!prefs.containsKey(key)) continue;
        final value = prefs.get(key);
        values[key] = value is String ? value : '';
      }
      snapshot = LocalFolderBootSnapshot(values);
    } catch (error) {
      snapshot = LocalFolderBootSnapshot.empty(error: error);
    }
  }

  static Iterable<String> get _bootKeys => {
        kSharedStorageModeKey,
        kLocalFolderNoticeAckKey,
        for (final keys in kAppSessionKeys.values)
          if (keys != null) ...[keys.key, if (keys.legacyKey != null) keys.legacyKey!],
      };

  /// The 2.8 log line for a failed preload, or null.
  static String? preloadFailureMessage(String app) {
    final error = snapshot?.error;
    return error == null
        ? null
        : LocalFolderMessages.bootNotChecked(appModuleOf(app), '$error');
  }
}

bool _isSession(String? raw) {
  if (raw == null || raw.isEmpty) return false;
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map && decoded['token'] != null;
  } on FormatException {
    return false;
  }
}

/// Whether [app] holds a saved cloud session, read as its `loadSession`
/// reads it.
bool hasSavedCloudSession(String app, LocalFolderBootSnapshot snapshot) {
  final keys = kAppSessionKeys[app];
  if (keys == null) return false;
  if (snapshot.containsKey(keys.key)) return _isSession(snapshot.getString(keys.key));
  final legacy = keys.legacyKey;
  return legacy != null && _isSession(snapshot.getString(legacy));
}

class StorageModeDecision {
  const StorageModeDecision(this.mode, {this.record, this.cloudSessionWins = false});

  final StorageMode mode;

  /// The connected folder, also when a cloud session took precedence.
  final StorageModeRecord? record;

  /// 2.10 rule 2: a folder is connected, but this app's session wins.
  final bool cloudSessionWins;
}

/// 2.8: `folder` only when the build is web ([isWeb] comes from the
/// platform, so VM tests can exercise it, T7(b)), the shared key holds
/// `"mode": "folder"`, and [app] has no saved cloud session.
StorageModeDecision decideStorageMode({
  required String app,
  required bool isWeb,
  required LocalFolderBootSnapshot? snapshot,
}) {
  if (!isWeb || snapshot == null) {
    return const StorageModeDecision(StorageMode.browserOrCloud);
  }
  final record =
      StorageModeRecord.tryParse(snapshot.getString(kSharedStorageModeKey));
  if (record == null) return const StorageModeDecision(StorageMode.browserOrCloud);
  if (hasSavedCloudSession(app, snapshot)) {
    return StorageModeDecision(StorageMode.browserOrCloud,
        record: record, cloudSessionWins: true);
  }
  return StorageModeDecision(StorageMode.folder, record: record);
}
