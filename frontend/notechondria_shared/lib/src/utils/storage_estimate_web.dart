// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

// Web implementation: query the browser StorageManager for the
// origin's storage usage + quota (navigator.storage.estimate()).

/// Best-effort `(usage, quota)` in bytes for the current origin, or
/// `(null, null)` when the API is unsupported or throws.
Future<({int? usageBytes, int? quotaBytes})> readStorageEstimate() async {
  try {
    final storage = html.window.navigator.storage;
    if (storage == null) return (usageBytes: null, quotaBytes: null);
    final estimate = await storage.estimate();
    if (estimate == null) return (usageBytes: null, quotaBytes: null);
    final usage = (estimate['usage'] as num?)?.toInt();
    final quota = (estimate['quota'] as num?)?.toInt();
    return (usageBytes: usage, quotaBytes: quota);
  } catch (_) {
    return (usageBytes: null, quotaBytes: null);
  }
}
