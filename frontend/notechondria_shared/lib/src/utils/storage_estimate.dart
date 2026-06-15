// Stub storage-quota probe for non-web platforms. Native builds have
// no browser StorageManager; callers treat null usage/quota as
// "unknown / not applicable". Resolved at compile time when
// `dart.library.html` is unavailable. See `storage_estimate_web.dart`.

/// Best-effort `(usage, quota)` in bytes from the browser
/// StorageManager, or `(null, null)` off the web / when unsupported.
Future<({int? usageBytes, int? quotaBytes})> readStorageEstimate() async =>
    (usageBytes: null, quotaBytes: null);
