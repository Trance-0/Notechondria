import '../folder_journal.dart';
import '../folder_layout.dart';
import '../folder_messages.dart';
import '../router.dart';
import '../secret_denylist.dart';
import 'records.dart';

// Handshake, ping, settings (with the per-device key filter, F08), session
// (shape in 8.4), logout, and Casdoor config (4.1 "Auth (local answers)").

/// F08 / decision D2: per-device preferences. The folder settings handler
/// drops them from every `PATCH /settings/`, at the top level and inside
/// `app_settings`, and omits them from `GET /settings/`, so the device
/// values stay in browser storage.
const Set<String> kPerDeviceSettingKeys = {
  'api_base_url',
  'theme_preset',
  'theme_mode',
  'locale',
  'offline_mode',
  'log_preferences',
  'splash_image_url',
  'splash_image_local',
  'keep_offline_data_on_login',
};

/// The token the folder session uses (main 7.1 step 2).
const String kLocalFolderToken = 'local-folder';

Map<String, Object?> _withoutDeviceKeys(Object? value) => value is Map
    ? {
        for (final e in value.entries)
          if (!kPerDeviceSettingKeys.contains('${e.key}')) '${e.key}': e.value,
      }
    : <String, Object?>{};

Map<String, Object?> _object(Object? value) => value is Map
    ? Map<String, Object?>.from(value)
    : <String, Object?>{};

/// The handshake (F46): the running build's version and no frontend floor,
/// so the update banner stays hidden; `storage.label` names the folder.
Map<String, Object?> localHandshake(
        {required String appVersion, required String folderName}) =>
    {
      'service': 'notechondria-backend',
      'api_version': 'v1',
      'version': appVersion,
      'min_frontend_version': '',
      'capabilities': {
        'auth': 1,
        'notes': 1,
        'courses': 1,
        'planner': 0,
        'calendar_feeds': 0,
        'attachments': 0,
        'mcp': 0,
      },
      'build': {
        'version': appVersion,
        'commit': '',
        'build_time': '',
        'deploy_target': 'local-folder',
      },
      'storage': {'backend': 'local-folder', 'label': 'Local folder: $folderName'},
    };

/// `GET /settings/`: the keys of the backend's settings representation
/// (`backend/creators/api.py:395-428`) minus [kPerDeviceSettingKeys].
Map<String, Object?> settingsPayload(FolderProfile p) {
  final folderLabel = p.field('uncategorized_folder_name').trim();
  return {
    'username': p.username,
    'first_name': p.field('first_name'),
    'last_name': p.field('last_name'),
    'email': p.field('email'),
    'is_staff': false,
    'is_superuser': false,
    'motto': p.field('motto'),
    'social_link': p.field('social_link'),
    'display_name': p.displayName,
    'image_url': p.field('image_url'),
    'avatar_url': '',
    'image_upload_url': p.field('image_url'),
    'editor_mode': p.editorMode,
    'api_key_prefix': '',
    'mcp_skill_md': p.skill,
    'uncategorized_folder_name': folderLabel.isEmpty ? 'Inbox' : folderLabel,
    'casdoor_linked': false,
    'casdoor_profile_synced_at': null,
    'app_settings': _withoutDeviceKeys(p.settings['app_settings']),
    'app_settings_updated_at': jsonString(p.settings['app_settings_updated_at']),
    'last_seen_versions': _object(p.settings['last_seen_versions']),
  };
}

Future<LocalResponse> _getSettings(LocalHandlerContext ctx) async {
  final p = await FolderProfile.read(ctx.fs, folderName: ctx.folderName);
  return LocalResponse(200, settingsPayload(p));
}

const Map<String, int?> _creatorStringFields = {
  'username': 150,
  'first_name': 150,
  'last_name': 150,
  'email': 254,
  'motto': 100,
  'social_link': 200,
  'display_name': 255,
};

Future<LocalResponse> _patchSettings(LocalHandlerContext ctx) async {
  final request = ctx.request;
  if (request.files.isNotEmpty) {
    throw LocalHttpError(
        501,
        LocalFolderMessages.laterRelease(
            'Avatar upload', request.method, request.path));
  }
  final raw = request.body;
  for (final key in kPerDeviceSettingKeys) {
    raw.remove(key);
  }
  if (raw['app_settings'] is String) {
    // Multipart sends JSON fields as text.
    raw['app_settings'] = decodeJsonValue(raw['app_settings'] as String);
  }
  final body = BodyFields(raw, consequence: 'Settings not saved', process: 'settings');
  final p = await FolderProfile.read(ctx.fs, folderName: ctx.folderName);
  final creator = Map<String, Object?>.from(p.creator);
  final settings = Map<String, Object?>.from(p.settings);
  _creatorStringFields.forEach((key, max) {
    final v = body.string(key, maxLength: max);
    if (v != null) creator[key] = key == 'email' ? v.toLowerCase() : v;
  });
  final mode = body.choice('editor_mode', const {'G', 'B', 'P'});
  if (mode != null) creator['editor_mode'] = mode;
  final label = body.string('uncategorized_folder_name', maxLength: 120);
  if (label != null) {
    creator['uncategorized_folder_name'] =
        label.trim().isEmpty ? 'Inbox' : label.trim();
  }
  if (body.has('app_settings')) {
    final incoming = raw['app_settings'];
    if (incoming is! Map) throw body.bad('app_settings must be a JSON object');
    settings['app_settings'] = {
      ..._withoutDeviceKeys(settings['app_settings']),
      ..._withoutDeviceKeys(incoming),
    };
    settings['app_settings_updated_at'] =
        body.string('app_settings_updated_at') ??
            ctx.now().toUtc().toIso8601String();
  }
  if (body.has('last_seen_versions')) {
    final seen = raw['last_seen_versions'];
    if (seen is! Map || seen.entries.any((e) => e.value is! String)) {
      throw body.bad('last_seen_versions must map app ids to version strings');
    }
    settings['last_seen_versions'] = {
      ..._object(settings['last_seen_versions']),
      for (final e in seen.entries) '${e.key}'.trim(): '${e.value}'.trim(),
    };
  }
  final skill = body.string('mcp_skill_md');
  final writes = <JournalWriteSpec>[];
  // Section 5: the secret denylist applies to every write under profile/.
  final creatorText = encodeFolderJson(stripSecrets(
      {...creator, 'schema_version': kFolderSchemaVersion}));
  final settingsText = encodeFolderJson(stripSecrets(
      {...settings, 'schema_version': kFolderSchemaVersion}));
  if (!_sameJson(creator, p.creator)) {
    writes.add((path: kProfileCreatorPath, text: creatorText));
  }
  if (!_sameJson(settings, p.settings)) {
    writes.add((path: kProfileSettingsPath, text: settingsText));
  }
  if (skill != null && skill != p.skill) {
    writes.add((path: kProfileSkillPath, text: skill));
  }
  await commitWrites(ctx, writes);
  final updated = await FolderProfile.read(ctx.fs, folderName: ctx.folderName);
  return LocalResponse(200, settingsPayload(updated));
}

bool _sameJson(Map<String, Object?> a, Map<String, Object?> b) =>
    encodeFolderJson(a) == encodeFolderJson(b);

/// `GET /auth/session/` (8.4): the request's token and the settings profile
/// with `is_local_folder: true`. The backend has no such route (Q17).
Future<LocalResponse> _session(LocalHandlerContext ctx) async {
  final p = await FolderProfile.read(ctx.fs, folderName: ctx.folderName);
  return LocalResponse(200, {
    'authenticated': true,
    'token': ctx.request.token ?? kLocalFolderToken,
    'user': {...settingsPayload(p), 'is_local_folder': true},
  });
}

List<LocalRoute> authSettingsRoutes() => [
      LocalRoute(
          'GET',
          'handshake',
          (ctx) async => LocalResponse(
              200,
              localHandshake(
                  appVersion: ctx.appVersion, folderName: ctx.folderName)),
          everyState: true),
      LocalRoute(
          'GET',
          'ping',
          (ctx) async => LocalResponse(200, {
                'pong': true,
                'service': 'notechondria-local-folder',
                'timestamp': ctx.now().toUtc().toIso8601String(),
              }),
          everyState: true),
      LocalRoute('GET', 'settings', _getSettings),
      LocalRoute('PATCH', 'settings', _patchSettings),
      LocalRoute('GET', 'auth/session', _session),
      LocalRoute('POST', 'auth/logout',
          (ctx) async => const LocalResponse(200, <String, Object?>{})),
      LocalRoute('GET', 'auth/casdoor/config',
          (ctx) async => const LocalResponse(200, {'configured': false})),
    ];

typedef JournalWriteSpec = ({String path, String text});

/// One file through [LocalHandlerContext.writeText], several through one
/// journal record (3.4.1); nothing for none.
Future<void> commitWrites(
    LocalHandlerContext ctx, List<JournalWriteSpec> writes) async {
  if (writes.isEmpty) return;
  if (writes.length == 1) {
    await ctx.writeText(writes.single.path, writes.single.text);
    return;
  }
  await ctx.commit(ctx.journal.newRecord([
    for (final w in writes) JournalWrite(w.path, w.text),
  ]));
}
