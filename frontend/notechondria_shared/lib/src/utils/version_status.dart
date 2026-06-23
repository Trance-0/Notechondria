// App-version comparison for the update-notification banner.
//
// The web bundle embeds its built version (`--dart-define=APP_VERSION`).
// The backend handshake returns its running `version` plus an optional
// `min_frontend_version` floor. Comparing the three tells the client
// whether it is current, a refresh behind a newer deploy, ahead of a
// backend still mid-rollout, or below the supported floor.

/// The version facts a client reads from the backend handshake to drive
/// the update banner. `probe` callbacks return null when the backend is
/// unreachable (so the banner shows nothing rather than a false signal).
class BackendVersionInfo {
  const BackendVersionInfo({
    required this.version,
    this.minFrontendVersion,
  });

  /// The backend's running `version`.
  final String version;

  /// The backend's `min_frontend_version` floor (empty/null = none).
  final String? minFrontendVersion;
}

/// Outcome of comparing the running frontend build against the backend.
enum AppVersionStatus {
  /// Frontend matches the backend (or versions aren't comparable) — no
  /// banner.
  upToDate,

  /// Backend is newer than this frontend build: a new version has
  /// deployed but the browser still runs the cached old bundle. Soft
  /// "refresh to update" banner.
  updateAvailable,

  /// Backend is OLDER than this frontend build: a deploy is rolling out
  /// (the new web bundle is already served, the backend container hasn't
  /// flipped yet). Informational "rolling out" banner.
  deploying,

  /// Frontend build is below the backend's `min_frontend_version` floor:
  /// stronger "update required" prompt.
  unsupported,
}

/// Compare two dotted-numeric version strings (e.g. `0.1.151`).
/// Returns <0 if [a] < [b], 0 if equal/incomparable, >0 if [a] > [b].
/// Non-numeric versions ("unknown", "git-abc", "") are treated as
/// incomparable and yield 0 so callers don't show a spurious banner.
int compareSemver(String a, String b) {
  final pa = _parse(a);
  final pb = _parse(b);
  if (pa == null || pb == null) return 0;
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final ai = i < pa.length ? pa[i] : 0;
    final bi = i < pb.length ? pb[i] : 0;
    if (ai != bi) return ai < bi ? -1 : 1;
  }
  return 0;
}

List<int>? _parse(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  // Take the leading dotted-numeric run; ignore a build/pre-release
  // suffix like "-rc1" or "+5" if present.
  final core = trimmed.split(RegExp(r'[-+ ]')).first;
  final parts = core.split('.');
  final out = <int>[];
  for (final p in parts) {
    final v = int.tryParse(p);
    if (v == null) return null;
    out.add(v);
  }
  return out.isEmpty ? null : out;
}

/// Classify the running frontend against the backend handshake.
///
/// [frontendVersion] is this build's `APP_VERSION`; [backendVersion] is
/// the handshake `version`; [minFrontendVersion] is the handshake
/// `min_frontend_version` (empty/null = no floor).
AppVersionStatus computeVersionStatus({
  required String frontendVersion,
  required String backendVersion,
  String? minFrontendVersion,
}) {
  final floor = (minFrontendVersion ?? '').trim();
  if (floor.isNotEmpty && compareSemver(frontendVersion, floor) < 0) {
    return AppVersionStatus.unsupported;
  }
  final cmp = compareSemver(frontendVersion, backendVersion);
  if (cmp < 0) return AppVersionStatus.updateAvailable; // backend newer
  if (cmp > 0) return AppVersionStatus.deploying; // backend older
  return AppVersionStatus.upToDate;
}
