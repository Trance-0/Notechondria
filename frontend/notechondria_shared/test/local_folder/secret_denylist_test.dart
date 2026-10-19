import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/src/local_folder/secret_denylist.dart';

/// Every key the folder writes today (manifest, sidecar, course, profile,
/// history, planner, attachments, journal, index), which must all survive.
const List<String> _keysTheFolderWrites = [
  'schema_version', 'format', 'layout_version', 'folder_id', 'created_at',
  'created_by_app_version', 'id_counters', 'github_sync_schema_version',
  'restored_from_folder_id', 'id', 'uuid', 'sharing_id', 'metadata_json',
  'custom_meta', 'client_draft_id', 'note_type', 'source_note_uuid',
  'cover_image_url', 'description', 'word_count', 'md_size',
  'md_last_modified', 'deleted_at', 'client_course_id', 'slug', 'title',
  'icon', 'sort_order', 'username', 'first_name', 'last_name', 'email',
  'is_active', 'motto', 'social_link', 'editor_mode', 'theme_preset',
  'theme_mode', 'api_base_url', 'image_url', 'date_joined', 'last_login',
  'app_settings', 'app_settings_updated_at', 'note_uuid', 'versions',
  'reason', 'label', 'op_id', 'filename', 'content_type', 'size_bytes',
  'client_local_id', 'course_id', 'starts_at', 'ends_at', 'kind', 'summary',
  'note_id', 'mode', 'folder_name', 'connected_by', 'remember', 'app',
  'writes', 'removals', 'text', 'expect', 'size', 'lastModified', 'directory',
  'generated_at', 'files', 'last_modified', 'course_slug', 'is_public',
  'max_id', 'needs_ids',
];

/// The benign look-alikes design section 5 names, plus `*_path` keys.
const List<String> _mustSurvive = [
  'path', 'source_path', 'git_path', 'patch', 'pattern', 'tokens_used',
  'keyboard_layout', 'tokenizer', 'passage', 'keys', 'keynote',
];

const List<String> _mustStrip = [
  'token', 'pat', 'secret', 'password', 'passphrase', 'authorization',
  'cookie', 'credential', 'credentials', 'api_key', 'apikey',
  'access_token', 'refresh_token', 'github_token', 'client_secret',
  'private_key', 'db_password', 'Authorization', 'API_KEY', 'GitHub_Token',
];

Map<String, Object?> _level(List<String> keys, Object? child) => {
      for (final k in keys) k: k == 'nested' ? child : 'v',
      'nested': child,
    };

void main() {
  test('every stripped key is gone at every depth', () {
    final fixture = _level(_mustStrip, {
      'list': [_level(_mustStrip, _level(_mustStrip, 'leaf'))],
      ..._level(_mustStrip, null),
    });
    final stripped = stripSecrets(fixture) as Map<String, Object?>;
    void walk(Object? value, String where) {
      if (value is Map) {
        for (final key in value.keys) {
          expect(_mustStrip.contains(key), isFalse, reason: '$where.$key');
          walk(value[key], '$where.$key');
        }
      } else if (value is List) {
        for (final item in value) {
          walk(item, '$where[]');
        }
      }
    }

    walk(stripped, r'$');
    expect((stripped['nested'] as Map)['list'], isA<List>());
  });

  test('every key the folder writes and every look-alike survives', () {
    final keys = [..._keysTheFolderWrites, ..._mustSurvive];
    final fixture = _level(keys, {
      'deeper': [_level(keys, _level(keys, 1))],
    });
    final stripped = stripSecrets(fixture);
    expect(stripped, fixture);
  });

  test('matching is whole-key and case-insensitive', () {
    for (final key in _mustStrip) {
      expect(isSecretKey(key), isTrue, reason: key);
    }
    for (final key in [..._keysTheFolderWrites, ..._mustSurvive]) {
      expect(isSecretKey(key), isFalse, reason: key);
    }
  });

  test('a benign *_key is caught until it is exempted', () {
    // The rule is deliberate: a new key ending in _key fails here first.
    expect(isSecretKey('sort_key'), isTrue);
    expect(kSecretExemptKeys, contains('path'));
  });

  test('non-map values pass through', () {
    expect(stripSecrets([1, 'token', null]), [1, 'token', null]);
    expect(stripSecrets('password'), 'password');
  });
}
