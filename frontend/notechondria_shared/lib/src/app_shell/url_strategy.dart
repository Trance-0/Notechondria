/// Stub URL strategy for non-web platforms (used during `flutter test`
/// and native desktop). All three apps (editor / planner / portal)
/// resolve this file at compile time when `dart.library.html` isn't
/// available.
void browserPushState(String url) {}
void browserReplaceState(String url) {}
void browserRedirect(String url) {}

/// Stub for the popup-based GitHub install flow. On non-web targets
/// the SPA never triggers GH App linking (the SDK isn't loaded), so
/// the helpers no-op cleanly.
///
/// `onInstallation` is the callback that fires when the popup posts
/// back the install id; the returned function is the unsubscribe
/// handle the caller invokes when the surface unmounts.
void Function() openPopupInstall({
  required String url,
  required void Function(Map<String, String> params) onInstallation,
  String name = 'github-install',
  int width = 720,
  int height = 800,
}) {
  return () {};
}
