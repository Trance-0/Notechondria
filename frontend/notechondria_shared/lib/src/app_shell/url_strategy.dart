/// Stub URL strategy for non-web platforms (used during `flutter test`
/// and native desktop). All three apps (editor / planner / portal)
/// resolve this file at compile time when `dart.library.html` isn't
/// available.
void browserPushState(String url) {}
void browserReplaceState(String url) {}
void browserRedirect(String url) {}
