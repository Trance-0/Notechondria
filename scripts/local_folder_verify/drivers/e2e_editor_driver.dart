// Browser end-to-end run of the editor's local folder mode in headless
// Chromium from Dockerfile.chromium. Started by
// scripts/local_folder_verify/e2e.sh editor; first used for release 0.1.201
// check 3. APP_VERSION must match the build so the "what's new" overlay
// stays closed. Exit code 0 only when every step passed, the driver raised
// no error, and no request after the boot phase went to /api/.
//
// Runs inside a `--network none` container with no -p mapping. Serves the
// editor build (compiled with the OPFS test-hook define) on 127.0.0.1:8099,
// starts Chromium with DevTools on 127.0.0.1:9222, and drives the real UI
// through trusted CDP mouse input and Input.insertText. Headless Chromium
// cannot answer the directory picker (U3: AbortError), and no app code calls
// the OPFS test hook, so an init script makes window.showDirectoryPicker
// resolve with an OPFS subdirectory handle; everything after the picker is
// the production path (WebFolderFs, handle store, Web Locks, transport).
// Every request the page makes is logged from Network.requestWillBeSent and
// from the server, tagged with the driver's phase.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

final out = Directory('/work/e2e');
final appVersion = Platform.environment['APP_VERSION'] ?? '0.1.201';
const base = 'http://127.0.0.1:8099/';
String phase = 'boot';
final steps = <Map<String, Object?>>[];
final netLog = File('/work/e2e/network.jsonl');
final serverLog = File('/work/e2e/server_requests.jsonl');
int shot = 0;

Future<void> main() async {
  out.createSync(recursive: true);
  final server = await _serve(Directory('/site'));
  final chrome = await Process.start('/usr/local/bin/chromium-no-sandbox', [
    '--headless=new',
    '--remote-debugging-port=9222',
    '--remote-debugging-address=127.0.0.1',
    '--user-data-dir=/tmp/e2e-profile',
    '--window-size=1280,1000',
    '--no-first-run',
    '--no-default-browser-check',
    '--enable-unsafe-swiftshader',
    '--use-angle=swiftshader',
    'about:blank',
  ]);
  chrome.stderr.transform(utf8.decoder).listen((l) =>
      File('${out.path}/chrome_stderr.txt')
          .writeAsStringSync(l, mode: FileMode.append));
  final result = <String, Object?>{'steps': steps};
  late _Cdp cdp;
  try {
    cdp = await _Cdp.connect();
    await cdp.send('Page.enable');
    await cdp.send('Runtime.enable');
    await cdp.send('Network.enable');
    await cdp.send('Page.addScriptToEvaluateOnNewDocument',
        {'source': _init.replaceAll('__APP_VERSION__', appVersion)});
    cdp.events.listen((e) {
      final m = e['method'];
      final p = (e['params'] as Map?) ?? const {};
      if (m == 'Network.requestWillBeSent') {
        final req = (p['request'] as Map?) ?? const {};
        netLog.writeAsStringSync(
            '${jsonEncode({
                  'phase': phase,
                  'method': req['method'],
                  'url': req['url'],
                  'type': p['type'],
                })}\n',
            mode: FileMode.append);
      } else if (m == 'Runtime.consoleAPICalled' ||
          m == 'Runtime.exceptionThrown') {
        File('${out.path}/console.jsonl').writeAsStringSync(
            '${jsonEncode({'phase': phase, ...e})}\n',
            mode: FileMode.append);
      }
    });

    await _step('load settings', () async {
      await cdp.send('Page.navigate', {'url': '$base#/settings'});
      await _semanticsOn(cdp);
      await _waitLabel(cdp, 'Use a local folder (no account)',
          const Duration(seconds: 60));
      // Let the cloud-mode startup pass finish (banner moves the layout).
      await Future<void>.delayed(const Duration(seconds: 8));
      final opt = await _find(cdp, 'Use a local folder (no account)');
      result['option'] = opt;
      final remember = await _find(cdp, 'Remember this folder on this browser');
      result['remember_before'] = remember;
      await _dump(cdp, 'settings');
      if (remember != null && remember['checked'] != 'true') {
        await _clickLabel(cdp, 'Remember this folder on this browser');
        await Future<void>.delayed(const Duration(seconds: 1));
        result['remember_after'] =
            await _find(cdp, 'Remember this folder on this browser');
      }
    });

    await _step('choose a local folder', () async {
      phase = 'connect';
      await _clickLabel(cdp, 'Use a local folder (no account)');
      await Future<void>.delayed(const Duration(seconds: 2));
      await _dump(cdp, 'after_option');
      for (final next in ['Choose folder', 'Start empty']) {
        if (await _find(cdp, next) != null) {
          await _clickLabel(cdp, next);
          await Future<void>.delayed(const Duration(seconds: 2));
          await _dump(cdp, 'after_${next.replaceAll(' ', '_')}');
        }
      }
      await _waitLabel(cdp, 'Local folder', const Duration(seconds: 30));
      await Future<void>.delayed(const Duration(seconds: 2));
      result['picker_calls'] = await cdp.eval('JSON.stringify(window.__e2e.calls)');
      result['folder_after_connect'] = await _opfs(cdp);
      await _dump(cdp, 'connected');
    });
    phase = 'folder';

    await _step('create and edit note A', () async {
      await _clickLabel(cdp, 'All Notes');
      await Future<void>.delayed(const Duration(seconds: 2));
      await _createNote(cdp, 'E2E folder note', 'Body written by the e2e check.');
      result['folder_after_edit'] = await _opfs(cdp);
      _expectFile(result['folder_after_edit'], 'notes/', 'E2E folder note');
    });

    await _step('delete note A', () async {
      await _deleteNote(cdp, 'E2E folder note');
      result['folder_after_delete'] = await _opfs(cdp);
      _expectFile(result['folder_after_delete'], 'trash/notes/', 'E2E folder note');
    });

    await _step('restore note A from the recycle bin', () async {
      await _openRecycleBin(cdp);
      await _clickLabel(cdp, 'Restore', exact: true);
      await Future<void>.delayed(const Duration(seconds: 3));
      await _dump(cdp, 'after_restore');
      result['folder_after_restore'] = await _opfs(cdp);
      _expectFile(result['folder_after_restore'], 'notes/', 'E2E folder note');
    });

    await _step('create, delete, and empty note B', () async {
      await _closeDialogs(cdp);
      await _clickLabel(cdp, 'All Notes');
      await Future<void>.delayed(const Duration(seconds: 2));
      await _createNote(cdp, 'E2E trash note', null);
      await _deleteNote(cdp, 'E2E trash note');
      result['folder_before_empty'] = await _opfs(cdp);
      _expectFile(result['folder_before_empty'], 'trash/notes/', 'E2E trash note');
      await _openRecycleBin(cdp);
      await _clickLabel(cdp, 'Empty recycle bin');
      await Future<void>.delayed(const Duration(seconds: 3));
      await _dump(cdp, 'after_empty');
      final after = await _opfs(cdp);
      result['folder_after_empty'] = after;
      if (after.contains('E2E trash note')) {
        throw StateError('note B still in the folder after Empty recycle bin');
      }
      _expectFile(after, 'notes/', 'E2E folder note');
    });

    await _step('reload and find note A', () async {
      await _closeDialogs(cdp);
      phase = 'reload';
      await cdp.send('Page.reload');
      await Future<void>.delayed(const Duration(seconds: 2));
      await _semanticsOn(cdp);
      await Future<void>.delayed(const Duration(seconds: 6));
      await _dump(cdp, 'after_reload');
      for (final gate in ["Reconnect '", "Choose '"]) {
        if (await _find(cdp, gate) != null) {
          result['reload_gate'] = gate;
          await _clickLabel(cdp, gate);
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      }
      if (await _find(cdp, 'All Notes') != null) {
        await _clickLabel(cdp, 'All Notes');
      }
      await _waitLabel(cdp, 'E2E folder note', const Duration(seconds: 30),
          contains: true);
      await _dump(cdp, 'reload_list');
      result['folder_after_reload'] = await _opfs(cdp);
    });
  } catch (e, s) {
    result['driver_error'] = '$e\n$s';
  } finally {
    final listeners = File('/proc/net/tcp')
        .readAsLinesSync()
        .skip(1)
        .map((l) => l.trim().split(RegExp(r'\s+')))
        .where((f) => f.length > 3 && f[3] == '0A')
        .map((f) => f[1])
        .toList();
    result['tcp_listeners_hex'] = listeners;
    result['tcp6_listeners'] = File('/proc/net/tcp6')
        .readAsLinesSync()
        .skip(1)
        .map((l) => l.trim().split(RegExp(r'\s+')))
        .where((f) => f.length > 3 && f[3] == '0A')
        .map((f) => f[1])
        .toList();
    final apiAfterBoot = !netLog.existsSync()
        ? 0
        : netLog.readAsLinesSync().map((l) => jsonDecode(l) as Map).where(
            (r) => r['phase'] != 'boot' && '${r['url']}'.contains('/api/'),
          ).length;
    result['api_after_boot'] = apiAfterBoot;
    result['pass'] = result['driver_error'] == null &&
        steps.isNotEmpty &&
        steps.every((s) => s['ok'] == true) &&
        apiAfterBoot == 0;
    exitCode = result['pass'] == true ? 0 : 1;
    File('${out.path}/e2e_result.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(
        {...result, 'steps': steps.map((s) => '${s['name']}: ${s['ok']}').toList()}));
    try {
      await cdp.close();
    } catch (_) {}
    chrome.kill();
    await server.close(force: true);
  }
}

Future<void> _step(String name, Future<void> Function() body) async {
  final t = DateTime.now();
  stdout.writeln('[e2e] step: $name ${t.toIso8601String()}');
  try {
    await body();
    steps.add({'name': name, 'ok': true,
      'ms': DateTime.now().difference(t).inMilliseconds});
  } catch (e) {
    steps.add({'name': name, 'ok': false, 'error': '$e'});
    rethrow;
  }
}

void _expectFile(Object? listing, String dir, String text) {
  final files = (jsonDecode('$listing') as List).cast<Map>();
  final hit = files.any((f) =>
      '${f['p']}'.startsWith(dir) &&
      !'${f['p']}'.substring(dir.length).contains('/') &&
      '${f['p']}'.endsWith('.md') &&
      '${f['text']}'.contains(text));
  if (!hit) throw StateError('no $dir*.md containing "$text" in the folder');
}

Future<void> _createNote(_Cdp cdp, String title, String? body) async {
  await _clickLabel(cdp, 'Create');
  await Future<void>.delayed(const Duration(seconds: 3));
  await _dump(cdp, 'editor_open_${title.replaceAll(' ', '_')}');
  await _typeInto(cdp, 'Title', title, selectAll: true);
  if (body != null) {
    try {
      await _typeInto(cdp, 'Write your note', body, selectAll: false);
    } catch (e) {
      steps.add({'name': 'body field', 'ok': false, 'error': '$e'});
    }
  }
  await Future<void>.delayed(const Duration(seconds: 1));
  await _dump(cdp, 'editor_typed_${title.replaceAll(' ', '_')}');
  // The close button (Icons.close, no tooltip) saves when dirty. Find it as
  // the unlabeled button nearest the title field's top-right.
  final closed = await cdp.eval(r'''
(() => {
  const btns = [...document.querySelectorAll('flt-semantics[role="button"]')]
    .filter(e => !(e.getAttribute('aria-label') || e.textContent || '').trim());
  const r = btns.map(e => e.getBoundingClientRect()).filter(r => r.width > 0);
  r.sort((a, b) => (a.top - b.top) || (b.left - a.left));
  return r.length ? JSON.stringify({x: r[0].left + r[0].width / 2,
    y: r[0].top + r[0].height / 2, n: r.length}) : null;
})()''');
  if (closed is! String) throw StateError('no unlabeled close button found');
  final c = jsonDecode(closed) as Map;
  await _click(cdp, c['x'] as num, c['y'] as num);
  await Future<void>.delayed(const Duration(seconds: 4));
  await _dump(cdp, 'editor_closed_${title.replaceAll(' ', '_')}');
}

Future<void> _deleteNote(_Cdp cdp, String title) async {
  await _closeDialogs(cdp);
  if (await _find(cdp, 'Options') == null) {
    await _clickLabel(cdp, title, contains: true);
    await Future<void>.delayed(const Duration(seconds: 3));
  }
  await _dump(cdp, 'viewer_${title.replaceAll(' ', '_')}');
  await _clickLabel(cdp, 'Options');
  await Future<void>.delayed(const Duration(seconds: 1));
  await _clickLabel(cdp, 'Delete', exact: true);
  await Future<void>.delayed(const Duration(seconds: 4));
  await _dump(cdp, 'deleted_${title.replaceAll(' ', '_')}');
}

Future<void> _openRecycleBin(_Cdp cdp) async {
  await _closeDialogs(cdp);
  await _clickLabel(cdp, 'Settings', exact: true);
  await Future<void>.delayed(const Duration(seconds: 2));
  await _clickLabel(cdp, 'Recycle bin');
  await Future<void>.delayed(const Duration(seconds: 2));
  await _dump(cdp, 'recycle_page');
  await _clickLabel(cdp, 'Cloud recycle bin');
  await Future<void>.delayed(const Duration(seconds: 2));
  await _dump(cdp, 'recycle_dialog');
}

Future<void> _closeDialogs(_Cdp cdp) async {
  for (var i = 0; i < 4; i++) {
    if (await _find(cdp, 'Close', exact: true) != null) {
      await _clickLabel(cdp, 'Close', exact: true);
    } else if (await _find(cdp, 'Back', exact: true) != null) {
      await _clickLabel(cdp, 'Back', exact: true);
    } else {
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
}

const _init = r'''
(() => {
  const stats = 'flutter.notechondria.editor.local_stats';
  if (!localStorage.getItem(stats)) {
    localStorage.setItem(stats, JSON.stringify(JSON.stringify({
      onboarding_seen: true, install_hint_dismissed: true,
      last_seen_version: '__APP_VERSION__'})));
  }
  const e2e = window.__e2e = {calls: [], perms: []};
  window.showDirectoryPicker = async function (opts) {
    const ua = navigator.userActivation;
    e2e.calls.push({isActive: ua ? ua.isActive : null,
                    options: JSON.stringify(opts === undefined ? null : opts)});
    const root = await navigator.storage.getDirectory();
    return root.getDirectoryHandle('nc-e2e-folder', {create: true});
  };
  const proto = window.FileSystemHandle && FileSystemHandle.prototype;
  for (const m of ['queryPermission', 'requestPermission']) {
    if (!proto || typeof proto[m] !== 'function') { e2e.perms.push(m + ': missing'); continue; }
    const orig = proto[m];
    proto[m] = function () {
      const p = orig.apply(this, arguments);
      p.then(v => e2e.perms.push(m + ': ' + v), e => e2e.perms.push(m + ': ' + e.name));
      return p;
    };
  }
})();
''';

Future<String> _opfs(_Cdp cdp) async {
  final v = await cdp.eval(r'''
(async () => {
  const root = await navigator.storage.getDirectory();
  let dir;
  try { dir = await root.getDirectoryHandle('nc-e2e-folder'); }
  catch (e) { return JSON.stringify([{p: 'ERROR ' + e.name, size: 0}]); }
  const out = [];
  async function walk(d, prefix) {
    for await (const [name, h] of d.entries()) {
      const p = prefix + name;
      if (h.kind === 'directory') { await walk(h, p + '/'); continue; }
      const f = await h.getFile();
      out.push({p, size: f.size,
        text: p.endsWith('.md') ? (await f.text()).slice(0, 300) : null});
    }
  }
  await walk(dir, '');
  out.sort((a, b) => a.p < b.p ? -1 : 1);
  return JSON.stringify(out);
})()''', awaitPromise: true);
  return '$v';
}

Future<void> _semanticsOn(_Cdp cdp) async {
  final end = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(end)) {
    final n = await cdp.eval("document.querySelectorAll('flt-semantics').length");
    if (n is int && n > 3) return;
    await cdp.eval("(() => { const p = document.querySelector("
        "'flt-semantics-placeholder'); if (p) p.click(); return true; })()");
    await Future<void>.delayed(const Duration(milliseconds: 750));
  }
  throw TimeoutException('semantics never turned on');
}

const _findJs = r'''
((want, exact, contains) => {
  let best = null;
  const sel = contains ? '[role="button"]' : 'flt-semantics, [role="button"], input, textarea';
  for (const el of document.querySelectorAll(sel)) {
    const text = (el.getAttribute('aria-label') || el.textContent || '').trim();
    if (contains ? !text.includes(want) : exact ? text !== want : !text.startsWith(want)) continue;
    const r = el.getBoundingClientRect();
    if (r.width <= 0 || r.height <= 0) continue;
    if (!best || r.width * r.height < best.w * best.h) {
      best = {x: r.left, y: r.top, w: r.width, h: r.height, tag: el.tagName,
              role: el.getAttribute('role'), text: text.slice(0, 80),
              disabled: el.getAttribute('aria-disabled'),
              checked: el.getAttribute('aria-checked')};
    }
  }
  return best ? JSON.stringify(best) : null;
})''';

Future<Map<String, Object?>?> _find(_Cdp cdp, String want,
    {bool exact = false, bool contains = false}) async {
  final v = await cdp.eval('$_findJs(${jsonEncode(want)}, $exact, $contains)');
  return v is String ? (jsonDecode(v) as Map).cast<String, Object?>() : null;
}

Future<Map<String, Object?>> _waitLabel(_Cdp cdp, String want, Duration limit,
    {bool exact = false, bool contains = false}) async {
  final end = DateTime.now().add(limit);
  while (DateTime.now().isBefore(end)) {
    final f = await _find(cdp, want, exact: exact, contains: contains);
    if (f != null) return f;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  await _dump(cdp, 'missing_${want.replaceAll(RegExp(r'[^A-Za-z]'), '_')}');
  throw TimeoutException('"$want" never appeared');
}

Future<void> _clickLabel(_Cdp cdp, String want,
    {bool exact = false, bool contains = false}) async {
  final r = await _waitLabel(cdp, want, const Duration(seconds: 20),
      exact: exact, contains: contains);
  await _click(cdp, (r['x'] as num) + (r['w'] as num) / 2,
      (r['y'] as num) + (r['h'] as num) / 2);
}

Future<void> _typeInto(_Cdp cdp, String hint, String text,
    {required bool selectAll}) async {
  final v = await cdp.eval('''
(() => {
  const want = ${jsonEncode(hint)};
  const els = [...document.querySelectorAll('input, textarea')];
  const pick = els.find(e => ((e.getAttribute('aria-label') || '') + ' ' +
      (e.placeholder || '')).includes(want)) ||
    [...document.querySelectorAll('flt-semantics')].find(e =>
      (e.getAttribute('aria-label') || '').includes(want) &&
      e.getBoundingClientRect().width > 0);
  if (!pick) return JSON.stringify({missing: true, inputs: els.map(e =>
      (e.getAttribute('aria-label') || '') + '|' + (e.placeholder || '') +
      '|' + e.value.slice(0, 40))});
  const r = pick.getBoundingClientRect();
  return JSON.stringify({x: r.left + Math.min(r.width / 2, 200),
                         y: r.top + Math.min(r.height / 2, 20)});
})()''');
  final m = jsonDecode('$v') as Map;
  if (m['missing'] == true) {
    throw StateError('no "$hint" field; inputs: ${m['inputs']}');
  }
  await _click(cdp, m['x'] as num, m['y'] as num);
  await Future<void>.delayed(const Duration(milliseconds: 600));
  if (selectAll) {
    for (final type in ['keyDown', 'keyUp']) {
      await cdp.send('Input.dispatchKeyEvent', {
        'type': type, 'key': 'a', 'code': 'KeyA', 'modifiers': 2,
        'windowsVirtualKeyCode': 65, 'nativeVirtualKeyCode': 65,
        if (type == 'keyDown') 'commands': ['selectAll'],
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  await cdp.send('Input.insertText', {'text': text});
  await Future<void>.delayed(const Duration(milliseconds: 600));
}

Future<void> _dump(_Cdp cdp, String name) async {
  final labels = await cdp.eval(
      "JSON.stringify([...document.querySelectorAll('flt-semantics, input, textarea')]"
      ".filter(e => e.getBoundingClientRect().width > 0)"
      ".map(e => e.tagName[0] + ':' + (e.getAttribute('role') || '') + ':' + "
      "(e.getAttribute('aria-label') || e.value || e.textContent || '')"
      ".trim().slice(0, 90)).filter(t => !t.endsWith(':')))");
  final n = (++shot).toString().padLeft(2, '0');
  File('${out.path}/labels_${n}_$name.json').writeAsStringSync('$labels');
  try {
    final s = await cdp.send('Page.captureScreenshot', {'format': 'png'},
        const Duration(seconds: 8));
    File('${out.path}/${n}_$name.png')
        .writeAsBytesSync(base64Decode(s['data'] as String));
  } on TimeoutException {
    File('${out.path}/${n}_$name.png.skipped').writeAsStringSync('timed out');
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
    serverLog.writeAsStringSync(
        '${jsonEncode({'phase': phase, 'method': req.method, 'path': path})}\n',
        mode: FileMode.append);
    if (path.contains('..')) path = '/';
    if (path.startsWith('/api/')) {
      req.response
        ..statusCode = 404
        ..headers.contentType = ContentType.json
        ..write('{"detail": "Request not served: release e2e static server/api '
            '\\u2014 no backend in this check"}');
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
    req.response.headers
        .set('content-type', types[ext] ?? 'application/octet-stream');
    await req.response.addStream(file.openRead());
    await req.response.close();
  });
  return server;
}

Future<void> _click(_Cdp cdp, num x, num y) async {
  await cdp.send('Input.dispatchMouseEvent', {'type': 'mouseMoved', 'x': x, 'y': y});
  await cdp.send('Input.dispatchMouseEvent', {
    'type': 'mousePressed', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1,
  });
  await Future<void>.delayed(const Duration(milliseconds: 80));
  await cdp.send('Input.dispatchMouseEvent', {
    'type': 'mouseReleased', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1,
  });
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
        final req =
            await client.getUrl(Uri.parse('http://127.0.0.1:9222/json/list'));
        final res = await req.close();
        final pages =
            jsonDecode(await res.transform(utf8.decoder).join()) as List;
        final page = pages.cast<Map>().firstWhere((p) => p['type'] == 'page');
        client.close();
        return _Cdp(
            await WebSocket.connect(page['webSocketDebuggerUrl'] as String));
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
    final ex = r['exceptionDetails'];
    if (ex != null) throw StateError('eval failed: ${jsonEncode(ex)}');
    return (r['result'] as Map?)?['value'];
  }

  Future<void> close() => _ws.close();
}
