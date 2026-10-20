// Phase 0 spike U3 (local folder design 1.2, 11.1), started by
// scripts/local_folder_verify/u3_spike.sh: does Flutter web keep
// the transient user activation of a real click through `onPressed`, so
// that `showDirectoryPicker` is not rejected with SecurityError?
//
// Runs inside a `--network none` container. It serves the editor's release
// build on 127.0.0.1:8099 (loopback only), starts headless Chromium with
// DevTools on 127.0.0.1:9222 (Chromium's default loopback bind), wraps
// `window.showDirectoryPicker` before the app loads to record
// `navigator.userActivation.isActive` at call time and the promise outcome,
// and clicks the real Flutter "Use a local folder (no account)" button
// with trusted CDP mouse input: once with semantics enabled (to learn the
// button's rectangle), once after a reload with semantics off (Flutter's
// pointer path, as a mouse user meets it). A control call without a gesture
// must fail with SecurityError, which shows that activation is enforced.
// Exit code 0 only when the control fails with SecurityError and both clicks
// reach showDirectoryPicker with isActive true and no SecurityError
// (headless Chromium then answers AbortError). APP_VERSION must match the
// build so the "what's new" overlay stays closed.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const label = 'Use a local folder (no account)';
final out = Directory('/work/u3');
final appVersion = Platform.environment['APP_VERSION'] ?? '0.1.200';

Future<void> main() async {
  out.createSync(recursive: true);
  final server = await _serve(Directory('/site'));
  final chrome = await Process.start('/usr/local/bin/chromium-no-sandbox', [
    '--headless=new',
    '--remote-debugging-port=9222',
    '--remote-debugging-address=127.0.0.1',
    '--user-data-dir=/tmp/u3-profile',
    '--window-size=1000,1400',
    '--no-first-run',
    '--no-default-browser-check',
    '--enable-unsafe-swiftshader',
    '--use-angle=swiftshader',
    'about:blank',
  ]);
  chrome.stderr.transform(utf8.decoder).listen(
      (l) => File('${out.path}/chrome_stderr.txt')
          .writeAsStringSync(l, mode: FileMode.append));
  final result = <String, Object?>{};
  try {
    final cdp = await _Cdp.connect();
    await cdp.send('Page.enable');
    await cdp.send('Runtime.enable');
    await cdp.send('Page.addScriptToEvaluateOnNewDocument',
        {'source': _wrapper.replaceAll('__APP_VERSION__', appVersion)});
    cdp.events.listen((e) {
      final m = e['method'];
      if (m == 'Runtime.consoleAPICalled' || m == 'Runtime.exceptionThrown') {
        File('${out.path}/console.jsonl').writeAsStringSync(
            '${jsonEncode(e)}\n',
            mode: FileMode.append);
      }
    });
    const url = 'http://127.0.0.1:8099/#/settings';
    await cdp.send('Page.navigate', {'url': url});
    final loadStart = DateTime.now();
    await _waitFor(cdp, "!!document.querySelector('flt-semantics-placeholder')",
        const Duration(seconds: 60));
    result['has_picker'] = await cdp.eval('window.__u3.hasPicker');
    result['secure_context'] = await cdp.eval('window.isSecureContext');
    result['user_agent'] = await cdp.eval('navigator.userAgent');
    // Control first, before any input on the page: no user activation.
    result['control_no_gesture'] = await cdp.eval(
        "window.showDirectoryPicker({id: 'notechondria-folder', mode: 'readwrite'})"
        ".then(h => 'resolved:' + h.name, e => e.name + ': ' + e.message)",
        awaitPromise: true);
    result['control_user_activation'] = await cdp.eval(
        'JSON.stringify({isActive: navigator.userActivation.isActive, '
        'hasBeenActive: navigator.userActivation.hasBeenActive})');
    await cdp.eval('window.__u3.calls = []; true');
    await cdp.eval(
        "document.querySelector('flt-semantics-placeholder').click(); true");
    await _waitForButton(cdp, const Duration(seconds: 60));
    final readyMs = DateTime.now().difference(loadStart).inMilliseconds;
    result['app_ready_ms'] = readyMs;
    // The startup pass ends (the backend-unavailable banner moves the
    // layout down), then the rectangle is read again.
    await Future<void>.delayed(const Duration(seconds: 8));
    await _screenshot(cdp, 'u3_0_settled.png');
    result['settled_labels'] = await cdp.eval(
        "JSON.stringify([...document.querySelectorAll('flt-semantics')]"
        ".map(e => (e.getAttribute('aria-label') || e.textContent || '')"
        ".trim().slice(0, 60)).filter(t => t))");
    final rect = await _waitForButton(cdp, const Duration(seconds: 10));
    result['button_rect'] = rect;
    await _screenshot(cdp, 'u3_1_before_semantics_click.png');
    final x = (rect['x'] as num) + (rect['w'] as num) / 2;
    final y = (rect['y'] as num) + (rect['h'] as num) / 2;

    // Click 1: semantics on (the button's DOM node receives the click).
    await _click(cdp, x, y);
    await Future<void>.delayed(const Duration(seconds: 4));
    result['semantics_path'] = await cdp.eval('JSON.stringify(window.__u3)');
    await _screenshot(cdp, 'u3_2_after_semantics_click.png');

    // Click 2: a fresh page load with semantics off (Flutter's pointer
    // path, as a mouse user meets it), same settle time, same point.
    await cdp.send('Page.navigate', {'url': 'about:blank'});
    await Future<void>.delayed(const Duration(seconds: 1));
    await cdp.send('Page.navigate', {'url': url});
    await _waitFor(cdp, "!!document.querySelector('flt-semantics-placeholder')",
        const Duration(seconds: 60));
    await Future<void>.delayed(Duration(milliseconds: readyMs + 8000));
    result['pointer_semantics_enabled'] = await cdp.eval(
        "document.querySelectorAll('flt-semantics').length");
    await _screenshot(cdp, 'u3_3_before_pointer_click.png');
    await _click(cdp, x, y);
    await Future<void>.delayed(const Duration(seconds: 4));
    result['pointer_path'] = await cdp.eval('JSON.stringify(window.__u3)');
    await _screenshot(cdp, 'u3_4_after_pointer_click.png');
    await cdp.close();
  } catch (e, s) {
    result['driver_error'] = '$e\n$s';
  } finally {
    final listeners = File('/proc/net/tcp').readAsLinesSync()
        .skip(1)
        .map((l) => l.trim().split(RegExp(r'\s+')))
        .where((f) => f.length > 3 && f[3] == '0A')
        .map((f) => f[1])
        .toList();
    result['tcp_listeners_hex'] = listeners;
    result['pass'] = result['driver_error'] == null &&
        '${result['control_no_gesture']}'.startsWith('SecurityError') &&
        _activeWithoutSecurityError(result['semantics_path']) &&
        _activeWithoutSecurityError(result['pointer_path']);
    exitCode = result['pass'] == true ? 0 : 1;
    File('${out.path}/u3_result.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
    chrome.kill();
    await server.close(force: true);
  }
}

const _wrapper = r'''
(() => {
  // First-run overlays (tour, what's new) would cover the settings page;
  // shared_preferences on web keeps each value JSON-encoded under flutter.*.
  const stats = 'flutter.notechondria.editor.local_stats';
  if (!localStorage.getItem(stats)) {
    localStorage.setItem(stats, JSON.stringify(JSON.stringify({
      onboarding_seen: true, install_hint_dismissed: true,
      last_seen_version: '__APP_VERSION__'})));
  }
  const u3 = window.__u3 = {hasPicker: false, calls: []};
  const orig = window.showDirectoryPicker;
  if (typeof orig !== 'function') return;
  u3.hasPicker = true;
  window.showDirectoryPicker = function (opts) {
    const ua = navigator.userActivation;
    const call = {
      at: new Date().toISOString(),
      isActive: ua ? ua.isActive : null,
      hasBeenActive: ua ? ua.hasBeenActive : null,
      options: JSON.stringify(opts === undefined ? null : opts),
      outcome: 'pending',
    };
    u3.calls.push(call);
    let p;
    try {
      p = orig.apply(window, arguments);
    } catch (e) {
      call.outcome = 'threw:' + e.name + ': ' + e.message;
      throw e;
    }
    p.then(h => { call.outcome = 'resolved:' + (h && h.name); },
           e => { call.outcome = 'rejected:' + e.name + ': ' + e.message; });
    return p;
  };
})();
''';

Future<HttpServer> _serve(Directory root) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8099);
  const types = {
    '.html': 'text/html',
    '.js': 'text/javascript',
    '.mjs': 'text/javascript',
    '.wasm': 'application/wasm',
    '.json': 'application/json',
    '.png': 'image/png',
    '.svg': 'image/svg+xml',
    '.ttf': 'font/ttf',
    '.otf': 'font/otf',
    '.css': 'text/css',
  };
  server.listen((req) async {
    var path = Uri.decodeComponent(req.uri.path);
    if (path.contains('..')) path = '/';
    if (path.startsWith('/api/')) {
      req.response
        ..statusCode = 404
        ..headers.contentType = ContentType.json
        ..write('{"detail": "no backend in the U3 spike"}');
      await req.response.close();
      return;
    }
    if (path.endsWith('/')) path = '${path}index.html';
    final file = File('${root.path}$path');
    if (!file.existsSync()) {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }
    final dot = path.lastIndexOf('.');
    final ext = dot < 0 ? '' : path.substring(dot);
    req.response.headers.set('content-type', types[ext] ?? 'application/octet-stream');
    await req.response.addStream(file.openRead());
    await req.response.close();
  });
  return server;
}

Future<void> _waitFor(_Cdp cdp, String expr, Duration limit) async {
  final end = DateTime.now().add(limit);
  while (DateTime.now().isBefore(end)) {
    if (await cdp.eval(expr) == true) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('waited for $expr');
}

Future<Map<String, Object?>> _waitForButton(_Cdp cdp, Duration limit) async {
  const find = '''
(() => {
  const want = ${'"$label"'};
  let best = null;
  for (const el of document.querySelectorAll('flt-semantics, [role="button"]')) {
    const text = (el.getAttribute('aria-label') || el.textContent || '').trim();
    if (!text.startsWith(want)) continue;
    const r = el.getBoundingClientRect();
    if (r.width <= 0 || r.height <= 0) continue;
    if (!best || r.width * r.height < best.w * best.h) {
      best = {x: r.left, y: r.top, w: r.width, h: r.height, tag: el.tagName,
              role: el.getAttribute('role'), text: text,
              disabled: el.getAttribute('aria-disabled')};
    }
  }
  return best ? JSON.stringify(best) : null;
})()''';
  final end = DateTime.now().add(limit);
  while (DateTime.now().isBefore(end)) {
    final found = await cdp.eval(find);
    if (found is String) return (jsonDecode(found) as Map).cast<String, Object?>();
    // Semantics turn on with a click on the placeholder; repeat it until the
    // engine has attached its handler.
    await cdp.eval("(() => { const p = document.querySelector("
        "'flt-semantics-placeholder'); if (p) p.click(); return true; })()");
    await Future<void>.delayed(const Duration(milliseconds: 1000));
  }
  throw TimeoutException('the "$label" button never appeared');
}

Future<void> _click(_Cdp cdp, num x, num y) async {
  await cdp.send('Input.dispatchMouseEvent',
      {'type': 'mouseMoved', 'x': x, 'y': y});
  await cdp.send('Input.dispatchMouseEvent', {
    'type': 'mousePressed', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1,
  });
  await Future<void>.delayed(const Duration(milliseconds: 80));
  await cdp.send('Input.dispatchMouseEvent', {
    'type': 'mouseReleased', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1,
  });
}

Future<void> _screenshot(_Cdp cdp, String name) async {
  // Best effort: headless Chromium may not produce a frame for a capture.
  try {
    final shot = await cdp.send('Page.captureScreenshot', {'format': 'png'},
        const Duration(seconds: 8));
    File('${out.path}/$name')
        .writeAsBytesSync(base64Decode(shot['data'] as String));
  } on TimeoutException {
    File('${out.path}/$name.skipped').writeAsStringSync('capture timed out');
  }
}

class _Cdp {
  _Cdp(this._ws) {
    _ws.listen((raw) {
      final msg = jsonDecode(raw as String) as Map<String, Object?>;
      final id = msg['id'];
      if (id is int && _pending.containsKey(id)) {
        _pending.remove(id)!.complete(msg);
      } else {
        _events.add(msg);
      }
    });
  }

  final WebSocket _ws;
  final Map<int, Completer<Map<String, Object?>>> _pending = {};
  final StreamController<Map<String, Object?>> _events =
      StreamController.broadcast();
  var _next = 0;

  Stream<Map<String, Object?>> get events => _events.stream;

  static Future<_Cdp> connect() async {
    final client = HttpClient();
    for (var i = 0; i < 80; i++) {
      try {
        final req = await client.getUrl(Uri.parse('http://127.0.0.1:9222/json/list'));
        final res = await req.close();
        final pages = jsonDecode(await res.transform(utf8.decoder).join()) as List;
        final page = pages.cast<Map>().firstWhere((p) => p['type'] == 'page');
        client.close();
        return _Cdp(await WebSocket.connect(page['webSocketDebuggerUrl'] as String));
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    throw StateError('Chromium DevTools did not come up on 127.0.0.1:9222');
  }

  Future<Map<String, Object?>> send(String method,
      [Map<String, Object?> params = const {},
      Duration timeout = const Duration(seconds: 60)]) async {
    final id = ++_next;
    final done = Completer<Map<String, Object?>>();
    _pending[id] = done;
    _ws.add(jsonEncode({'id': id, 'method': method, 'params': params}));
    final msg = await done.future.timeout(timeout);
    if (msg['error'] != null) throw StateError('$method: ${msg['error']}');
    return (msg['result'] as Map?)?.cast<String, Object?>() ?? const {};
  }

  Future<Object?> eval(String expr, {bool awaitPromise = false}) async {
    final r = await send('Runtime.evaluate', {
      'expression': expr,
      'returnByValue': true,
      'awaitPromise': awaitPromise,
      'userGesture': false,
    });
    return (r['result'] as Map?)?['value'];
  }

  Future<void> close() => _ws.close();
}

/// True when [path] (window.__u3 as JSON) recorded at least one picker call,
/// every call had a transient user activation, and none was rejected with
/// SecurityError.
bool _activeWithoutSecurityError(Object? path) {
  if (path is! String) return false;
  final calls = ((jsonDecode(path) as Map)['calls'] as List?) ?? const [];
  return calls.isNotEmpty &&
      calls.every((c) =>
          (c as Map)['isActive'] == true &&
          !'${c['outcome']}'.contains('SecurityError'));
}
