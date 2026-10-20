// Firefox check (release 0.1.201 and 0.1.202 check 4): an app's release
// build (APP=editor|planner|portal) in Playwright's Firefox 132 (headless)
// shows "Use a local folder (no account)" disabled with the
// noDirectoryPicker gap message (design 1.3, AGENTS.md 1.8). Started by
// scripts/local_folder_verify/firefox.sh. Exit code 0 only on pass.
//
// Runs in a `--network none` container with no -p mapping. Serves the
// release build (base href /Notechondria/<app>/) on 127.0.0.1:8099 and
// drives Firefox over WebDriver BiDi on 127.0.0.1:9223.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

final appName = Platform.environment['APP'] ?? 'planner';
final appVersion = Platform.environment['APP_VERSION'] ?? '0.1.202';
final out = Directory('/work/ff_$appName');
final prefix = '/Notechondria/$appName';
final url = 'http://127.0.0.1:8099$prefix/#/settings';
const label = 'Use a local folder (no account)';
const gapPrefix = 'Local folder mode unavailable: Shared.LocalFolder/qualify';

Future<void> main() async {
  out.createSync(recursive: true);
  final server = await _serve(Directory('/site'));
  Directory('/tmp/ffprof').createSync(recursive: true);
  final ff = await Process.start('/ms-playwright/firefox-1466/firefox/firefox', [
    '-headless', '-no-remote', '-profile', '/tmp/ffprof',
    '--remote-debugging-port=9223', '--width=1280', '--height=1000',
    'about:blank',
  ]);
  ff.stderr.transform(utf8.decoder).listen((l) =>
      File('${out.path}/firefox_stderr.txt').writeAsStringSync(l, mode: FileMode.append));
  ff.stdout.transform(utf8.decoder).listen((l) =>
      File('${out.path}/firefox_stdout.txt').writeAsStringSync(l, mode: FileMode.append));
  final result = <String, Object?>{};
  try {
    final bidi = await _Bidi.connect();
    final session = await bidi.send('session.new', {'capabilities': {}});
    result['browser'] =
        '${(session['capabilities'] as Map)['browserName']} ${(session['capabilities'] as Map)['browserVersion']}';
    final tree = await bidi.send('browsingContext.getTree', {});
    final ctx = ((tree['contexts'] as List).first as Map)['context'] as String;
    await bidi.send('script.addPreloadScript', {
      'functionDeclaration': '''() => {
        const stats = 'flutter.notechondria.$appName.local_stats';
        if (!localStorage.getItem(stats)) {
          localStorage.setItem(stats, JSON.stringify(JSON.stringify({
            onboarding_seen: true, install_hint_dismissed: true,
            last_seen_version: '$appVersion'})));
        }
      }''',
    });
    await bidi.send('browsingContext.navigate',
        {'context': ctx, 'url': url, 'wait': 'complete'});
    Future<Object?> eval(String expr) async {
      final r = await bidi.send('script.evaluate', {
        'expression': expr,
        'target': {'context': ctx},
        'awaitPromise': false,
      });
      return ((r['result'] as Map?) ?? const {})['value'];
    }

    result['user_agent'] = await eval('navigator.userAgent');
    result['has_directory_picker'] =
        await eval("typeof window.showDirectoryPicker");
    result['secure_context'] = await eval('String(window.isSecureContext)');
    Map<String, Object?>? option;
    String? gap;
    final end = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(end)) {
      await eval("(() => { const p = document.querySelector("
          "'flt-semantics-placeholder'); if (p) p.click(); return 'ok'; })()");
      final found = await eval('''
(() => {
  const want = ${jsonEncode(label)};
  let best = null, gap = null;
  for (const el of document.querySelectorAll('flt-semantics')) {
    const text = (el.getAttribute('aria-label') || el.textContent || '').trim();
    if (text.startsWith(${jsonEncode(gapPrefix)}) && (!gap || text.length < gap.length)) gap = text;
    if (!text.startsWith(want)) continue;
    const r = el.getBoundingClientRect();
    if (r.width <= 0) continue;
    if (!best || r.width * r.height < best.w * best.h) {
      best = {w: r.width, h: r.height, role: el.getAttribute('role'),
              text: text.slice(0, 80), disabled: el.getAttribute('aria-disabled'),
              tabindex: el.getAttribute('tabindex')};
    }
  }
  return JSON.stringify({best, gap});
})()''');
      if (found is String) {
        final m = jsonDecode(found) as Map;
        option = (m['best'] as Map?)?.cast<String, Object?>();
        gap = m['gap'] as String?;
        if (option != null && gap != null) break;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    await Future<void>.delayed(const Duration(seconds: 4));
    result['option'] = option;
    result['gap_message'] = gap;
    result['labels'] = await eval(
        "JSON.stringify([...document.querySelectorAll('flt-semantics')]"
        ".map(e => (e.getAttribute('role') || '') + ':' + (e.getAttribute('aria-disabled') || '') + ':' + "
        "(e.getAttribute('aria-label') || e.textContent || '').trim().slice(0, 160))"
        ".filter(t => !t.endsWith(':')))");
    try {
      final shot = await bidi.send('browsingContext.captureScreenshot',
          {'context': ctx}, const Duration(seconds: 20));
      File('${out.path}/firefox_settings.png')
          .writeAsBytesSync(base64Decode(shot['data'] as String));
    } catch (e) {
      result['screenshot_error'] = '$e';
    }
    result['pass'] = option != null &&
        option['disabled'] == 'true' &&
        gap != null &&
        gap.contains('window.showDirectoryPicker');
    exitCode = result['pass'] == true ? 0 : 1;
    await bidi.send('session.end', {});
  } catch (e, s) {
    result['driver_error'] = '$e\n$s';
    exitCode = 1;
  } finally {
    result['tcp_listeners_hex'] = File('/proc/net/tcp')
        .readAsLinesSync()
        .skip(1)
        .map((l) => l.trim().split(RegExp(r'\s+')))
        .where((f) => f.length > 3 && f[3] == '0A')
        .map((f) => f[1])
        .toList();
    result['tcp6_listeners_hex'] = File('/proc/net/tcp6')
        .readAsLinesSync()
        .skip(1)
        .map((l) => l.trim().split(RegExp(r'\s+')))
        .where((f) => f.length > 3 && f[3] == '0A')
        .map((f) => f[1])
        .toList();
    final text = const JsonEncoder.withIndent('  ').convert(result);
    File('${out.path}/ff_result.json').writeAsStringSync(text);
    stdout.writeln(text);
    ff.kill();
    await server.close(force: true);
  }
}

Future<HttpServer> _serve(Directory root) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8099);
  const types = {
    '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript',
    '.wasm': 'application/wasm', '.json': 'application/json',
    '.png': 'image/png', '.svg': 'image/svg+xml', '.ttf': 'font/ttf',
    '.otf': 'font/otf', '.css': 'text/css',
  };
  server.listen((req) async {
    var path = Uri.decodeComponent(req.uri.path);
    File('${out.path}/server_requests.txt')
        .writeAsStringSync('${req.method} $path\n', mode: FileMode.append);
    if (path.contains('..')) path = '/';
    if (path.startsWith('/api/')) {
      req.response
        ..statusCode = 404
        ..headers.contentType = ContentType.json
        ..write('{"detail": "Request not served: release Firefox check static '
            'server/api \\u2014 no backend in this check"}');
      await req.response.close();
      return;
    }
    if (!path.startsWith(prefix)) {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }
    path = path.substring(prefix.length);
    if (path.isEmpty || path.endsWith('/')) path = '${path}index.html';
    final file = File('${root.path}$path');
    if (!file.existsSync()) {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }
    final dot = path.lastIndexOf('.');
    final ext = dot < 0 ? '' : path.substring(dot);
    req.response.headers
        .set('content-type', types[ext] ?? 'application/octet-stream');
    await req.response.addStream(file.openRead());
    await req.response.close();
  });
  return server;
}

class _Bidi {
  _Bidi(this._ws) {
    _ws.listen((raw) {
      final msg = jsonDecode(raw as String) as Map<String, Object?>;
      final id = msg['id'];
      if (id is int && _pending.containsKey(id)) _pending.remove(id)!.complete(msg);
    });
  }

  final WebSocket _ws;
  final Map<int, Completer<Map<String, Object?>>> _pending = {};
  var _next = 0;

  static Future<_Bidi> connect() async {
    Object? last;
    for (var i = 0; i < 120; i++) {
      try {
        return _Bidi(await WebSocket.connect('ws://127.0.0.1:9223/session'));
      } catch (e) {
        last = e;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    throw StateError('Firefox WebDriver BiDi did not come up on 127.0.0.1:9223: $last');
  }

  Future<Map<String, Object?>> send(String method, Map<String, Object?> params,
      [Duration timeout = const Duration(seconds: 60)]) async {
    final id = ++_next;
    final done = Completer<Map<String, Object?>>();
    _pending[id] = done;
    _ws.add(jsonEncode({'id': id, 'method': method, 'params': params}));
    final msg = await done.future.timeout(timeout);
    if (msg['type'] == 'error') {
      throw StateError('$method: ${msg['error']}: ${msg['message']}');
    }
    return (msg['result'] as Map?)?.cast<String, Object?>() ?? const {};
  }
}
