// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Web URL strategy using the browser History API. Replaces each
/// app's per-app copy. Resolved at compile time when
/// `dart.library.html` is available.
void browserPushState(String url) {
  html.window.history.pushState(null, '', url);
}

void browserReplaceState(String url) {
  html.window.history.replaceState(null, '', url);
}

void browserRedirect(String url) {
  html.window.location.href = url;
}

/// Hard-reload the page so the browser fetches the newest web bundle.
/// Backs the "Refresh to update" action on the version-update banner.
void browserReload() {
  html.window.location.reload();
}

/// Open a popup window for the GitHub App install flow and listen for
/// a `postMessage` reply carrying the install id.
///
/// Why a popup instead of a same-tab redirect (the pre-0.1.120 path):
/// the install round-trip can take 30s+ (the user clicks through GitHub
/// UI to pick a repo + grant permissions). A full-page redirect cold-
/// boots the SPA on return, and even though the Casdoor JWT lives in
/// `SharedPreferences` (web → localStorage), the cold-boot path can
/// race a JWT that's near expiry: the SPA's first authenticated
/// request comes back 401, the auth-error interceptor calls
/// `logout()`, and the user appears signed out — the "no logs on
/// backend" symptom that prompted this rewrite. A popup keeps the
/// SPA loaded (so in-flight state survives), and the callback page
/// only has to `postMessage` the install id back before closing.
///
/// The popup HTML is served by the backend's `oauth_callback`
/// (`backend/notechondria/api_views.py`). For the popup flow it must
/// `window.opener.postMessage({type: 'gh-install', code, state,
/// installation_id, setup_action}, '*')` and `window.close()` —
/// without `window.opener`, fall back to the existing meta-refresh
/// redirect so the same-tab caller (legacy) keeps working.
///
/// Returns a closer function the caller invokes on widget dispose
/// to detach the message listener.
void Function() openPopupInstall({
  required String url,
  required void Function(Map<String, String> params) onInstallation,
  String name = 'github-install',
  int width = 720,
  int height = 800,
}) {
  // Centre the popup on the parent window when geometry is available;
  // browsers may ignore this on multi-monitor setups but a sensible
  // default beats a corner-pinned 0,0 placement.
  final screenW = html.window.screen?.available.width ?? width;
  final screenH = html.window.screen?.available.height ?? height;
  final left = ((screenW - width) / 2).round();
  final top = ((screenH - height) / 2).round();
  final features = 'popup=yes,width=$width,height=$height,left=$left,top=$top,'
      'resizable=yes,scrollbars=yes,status=no';
  final popup = html.window.open(url, name, features);

  // Listen for postMessage from the popup. We accept any origin (the
  // Casdoor / GitHub install callback reaches us through the backend
  // callback page that we control) but only act on the typed envelope
  // — anything without `type == 'gh-install'` is ignored.
  late final html.EventListener listener;
  listener = (html.Event event) {
    if (event is! html.MessageEvent) return;
    final data = event.data;
    if (data is! Map) return;
    if (data['type'] != 'gh-install') return;
    final params = <String, String>{};
    data.forEach((k, v) {
      if (v == null) return;
      params[k.toString()] = v.toString();
    });
    if (params['installation_id'] == null ||
        params['installation_id']!.isEmpty) {
      // No install id ⇒ user cancelled or the popup closed before
      // GitHub could redirect. Caller treats this as a no-op.
      return;
    }
    onInstallation(params);
  };
  html.window.addEventListener('message', listener);

  // Caller invokes the returned closer on widget dispose so the
  // listener doesn't leak and a stale popup reply doesn't fire
  // against an unmounted state.
  return () {
    html.window.removeEventListener('message', listener);
    try {
      popup?.close();
    } catch (_) {
      // popup may already be closed by the user; harmless.
    }
  };
}
