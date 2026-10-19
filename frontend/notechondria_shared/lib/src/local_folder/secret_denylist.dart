// Whole-key secret denylist (main 5). Applied to every JSON object the
// folder bridge exports (v1 buckets and the `folder/` copy), to the GitHub
// push, and to every write under `profile/`.

/// Keys stripped when they match exactly (case-insensitive).
const Set<String> kSecretExactKeys = {
  'token',
  'pat',
  'secret',
  'password',
  'passphrase',
  'authorization',
  'cookie',
  'credential',
  'credentials',
  'api_key',
  'apikey',
};

/// Keys stripped when they end in one of these (case-insensitive). They
/// cover `access_token`, `refresh_token`, `github_token`, `client_secret`,
/// and `private_key`.
const List<String> kSecretKeySuffixes = ['_token', '_secret', '_password', '_key'];

/// Keys never stripped, besides every `*_path` key. A new benign key that a
/// suffix would match (a `*_key`, say) fails the denylist test until it is
/// listed here.
const Set<String> kSecretExemptKeys = {'path'};

/// Whether [key] names a secret. Keys are compared whole, never as
/// substrings, so `patch`, `pattern`, and `tokens_used` are kept; `path`
/// and every `*_path` key are exempt.
bool isSecretKey(String key) {
  final k = key.toLowerCase();
  if (kSecretExemptKeys.contains(k) || k.endsWith('_path')) return false;
  if (kSecretExactKeys.contains(k)) return true;
  return kSecretKeySuffixes.any(k.endsWith);
}

/// A deep copy of [value] without secret keys at any depth.
Object? stripSecrets(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        if (!isSecretKey('${entry.key}'))
          '${entry.key}': stripSecrets(entry.value),
    };
  }
  if (value is List) return [for (final item in value) stripSecrets(item)];
  return value;
}
