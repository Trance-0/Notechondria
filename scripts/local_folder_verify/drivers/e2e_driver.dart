// Browser end-to-end run of local folder mode in the planner (APP=planner)
// and the portal (APP=portal), headless Chromium from Dockerfile.chromium.
// Started by scripts/local_folder_verify/e2e.sh; first used for release
// 0.1.202 check 3 and adapted from the editor driver (e2e_editor_driver.dart).
// APP_VERSION must match the build so the "what's new" overlay stays closed.
// Exit code 0 only when every step passed, the driver raised no error, and
// no request after the boot phase went to /api/.
//
// Runs inside a `--network none` container with no -p mapping. Serves the
// app build (compiled with the OPFS test-hook define, base href "/") on
// 127.0.0.1:8099, starts Chromium with DevTools on 127.0.0.1:9222, and
// drives the real UI through trusted CDP mouse input and Input.insertText.
// Headless Chromium cannot answer the directory picker (U3: AbortError), so
// an init script makes window.showDirectoryPicker resolve with an OPFS
// subdirectory handle; everything after the picker is the production path.
// Every request the page makes is logged from Network.requestWillBeSent and
// from the server, tagged with the driver's phase.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

final appName = Platform.environment['APP'] ?? 'planner';
final appVersion = Platform.environment['APP_VERSION'] ?? '0.1.202';
final out = Directory('/work/e2e_$appName');
const base = 'http://127.0.0.1:8099/';
String phase = 'boot';
final steps = <Map<String, Object?>>[];
late final File netLog = File('${out.path}/network.jsonl');
late final File serverLog = File('${out.path}/server_requests.jsonl');
int shot = 0;
final fileChoosers = StreamController<Map>.broadcast();
final String _roboto = base64Encode(File(
        '/sdks/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf')
    .readAsBytesSync());

const fabEvent = 'Tap to create a new event';
const fabNote = 'Create note. Long press to import markdown.';

Future<void> main() async {
  if (appName != 'planner' && appName != 'portal') {
    stderr.writeln('Check not run: LocalFolderVerify/e2e.driver — APP is '
        '"$appName"; this driver covers planner and portal '
        '(the editor uses e2e_editor_driver.dart).');
    exitCode = 2;
    return;
  }
  out.createSync(recursive: true);
  final server = await _serve(Directory('/site'));
  final chrome = await Process.start('/usr/local/bin/chromium-no-sandbox', [
    '--headless=new',
    '--remote-debugging-port=9222',
    '--remote-debugging-address=127.0.0.1',
    '--user-data-dir=/tmp/e2e-profile',
    '--window-size=900,1800',
    '--no-first-run',
    '--no-default-browser-check',
    '--enable-unsafe-swiftshader',
    '--use-angle=swiftshader',
    'about:blank',
  ]);
  chrome.stderr.transform(utf8.decoder).listen((l) =>
      File('${out.path}/chrome_stderr.txt')
          .writeAsStringSync(l, mode: FileMode.append));
  final result = <String, Object?>{'app': appName, 'steps': steps};
  late _Cdp cdp;
  try {
    cdp = await _Cdp.connect();
    await cdp.send('Page.enable');
    await cdp.send('Runtime.enable');
    await cdp.send('Network.enable');
    await cdp.send('DOM.enable');
    await cdp.send('Page.addScriptToEvaluateOnNewDocument', {'source': _init});
    if (Platform.environment['LOCAL_ROBOTO'] == '1') {
      // Screenshots only: answer fonts.gstatic.com Roboto requests in the
      // browser with the Flutter SDK's Roboto (the container has no network;
      // the request is still logged by Network.requestWillBeSent).
      await cdp.send('Fetch.enable', {
        'patterns': [
          {'urlPattern': 'https://fonts.gstatic.com/*', 'requestStage': 'Request'}
        ]
      });
    }
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
      } else if (m == 'Fetch.requestPaused') {
        final id = p['requestId'];
        final url = '${(p['request'] as Map?)?['url']}';
        if (url.contains('/roboto/')) {
          cdp.send('Fetch.fulfillRequest', {
            'requestId': id,
            'responseCode': 200,
            'responseHeaders': [
              {'name': 'Content-Type', 'value': 'font/ttf'},
              {'name': 'Access-Control-Allow-Origin', 'value': '*'},
            ],
            'body': _roboto,
          }).ignore();
        } else {
          cdp.send('Fetch.failRequest',
              {'requestId': id, 'errorReason': 'InternetDisconnected'}).ignore();
        }
      } else if (m == 'Page.fileChooserOpened') {
        fileChoosers.add(p);
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
      result['option'] = await _find(cdp, 'Use a local folder (no account)');
      result['remember_before'] =
          await _find(cdp, 'Remember this folder on this browser');
      await _dump(cdp, 'settings');
      final remember = result['remember_before'] as Map?;
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
      result['picker_calls'] =
          await cdp.eval('JSON.stringify(window.__e2e.calls)');
      result['folder_after_connect'] = await _opfs(cdp);
      await _dump(cdp, 'connected');
    });
    phase = 'folder';

    if (appName == 'planner') {
      await _plannerFlow(cdp, result);
    } else {
      await _portalFlow(cdp, result);
    }
  } catch (e, s) {
    result['driver_error'] = '$e\n$s';
    try {
      await _dump(cdp, 'driver_error');
    } catch (_) {}
  } finally {
    final summary = _requestSummary();
    result['request_summary'] = summary;
    result['tcp_listeners_hex'] = _listeners('/proc/net/tcp');
    result['tcp6_listeners_hex'] = _listeners('/proc/net/tcp6');
    final apiAfterBoot = summary.entries
        .where((e) => e.key != 'boot')
        .fold<int>(0, (n, e) => n + ((e.value as Map)['api'] as int));
    result['api_after_boot'] = apiAfterBoot;
    result['pass'] = result['driver_error'] == null &&
        steps.isNotEmpty &&
        steps.every((s) => s['ok'] == true) &&
        apiAfterBoot == 0;
    exitCode = result['pass'] == true ? 0 : 1;
    File('${out.path}/e2e_result.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln(const JsonEncoder.withIndent('  ').convert({
      'app': appName,
      'pass': result['pass'],
      'api_after_boot': apiAfterBoot,
      'steps': steps.map((s) => '${s['name']}: ${s['ok']}').toList(),
      'driver_error': result['driver_error'],
      'request_summary': result['request_summary'],
      'tcp_listeners_hex': result['tcp_listeners_hex'],
      'tcp6_listeners_hex': result['tcp6_listeners_hex'],
    }));
    try {
      await cdp.close();
    } catch (_) {}
    chrome.kill();
    await server.close(force: true);
  }
}

// ---------------------------------------------------------------- planner

const plannerEvent = 'E2E planner event';
const icsCalendar = 'E2E Calendar';
const icsSummary = 'E2E Lecture';

Future<void> _plannerFlow(_Cdp cdp, Map<String, Object?> result) async {
  await _step('create a planner event', () async {
    await _openTab(cdp, 'Activity');
    await _createEvent(cdp, plannerEvent);
    final files = await _opfs(cdp);
    result['folder_after_create'] = files;
    _expectText(files, 'planner/events.json', plannerEvent);
  });

  await _step('toggle the event complete', () async {
    final box = await _reveal(cdp, plannerEvent,
        contains: true, role: 'checkbox');
    result['checkbox_before'] = box;
    await _clickBox(cdp, box);
    await Future<void>.delayed(const Duration(seconds: 3));
    await _dump(cdp, 'after_toggle');
    result['checkbox_after'] =
        await _find(cdp, plannerEvent, contains: true, role: 'checkbox');
    final files = await _opfs(cdp);
    result['folder_after_toggle'] = files;
    final event = _eventRow(files, plannerEvent);
    if (event?['is_completed'] != true) {
      throw StateError('events.json: "$plannerEvent" is_completed is '
          '${event?['is_completed']} after the toggle');
    }
  });

  await _step('import a small .ics file', () async {
    File('/work/e2e.ics').writeAsStringSync(_ics());
    await cdp.send('Page.setInterceptFileChooserDialog', {'enabled': true});
    final chooser = fileChoosers.stream.first
        .timeout(const Duration(seconds: 20));
    chooser.ignore();
    await _openFabMenu(cdp, fabEvent, 'Import iCal');
    await _clickLabel(cdp, 'Import iCal', exact: true);
    final opened = await chooser;
    result['file_chooser'] = opened;
    await cdp.send('DOM.setFileInputFiles', {
      'files': ['/work/e2e.ics'],
      'backendNodeId': opened['backendNodeId'],
    });
    await _waitLabel(cdp, 'Confirm import', const Duration(seconds: 20));
    await _dump(cdp, 'import_review');
    result['import_review_parsed'] =
        await _find(cdp, '1 event parsed', contains: false);
    await _clickLabel(cdp, 'Confirm import');
    await Future<void>.delayed(const Duration(seconds: 4));
    await _dump(cdp, 'after_import');
    final files = await _opfs(cdp);
    result['folder_after_import'] = files;
    _expectText(files, 'planner/feeds.json', icsCalendar);
    _expectSuffix(files, '.ics', 'SUMMARY:$icsSummary');
  });

  await _step('reload: the event stays complete and the calendar stays',
      () async {
    await _closeDialogs(cdp);
    phase = 'reload';
    await cdp.send('Page.reload');
    await Future<void>.delayed(const Duration(seconds: 2));
    await _semanticsOn(cdp);
    await Future<void>.delayed(const Duration(seconds: 6));
    await _dump(cdp, 'after_reload');
    await _reconnectIfAsked(cdp, result);
    await _openTab(cdp, 'Activity');
    final box = await _waitLabel(cdp, plannerEvent, const Duration(seconds: 30),
        contains: true, role: 'checkbox');
    result['checkbox_after_reload'] = box;
    if (box['checked'] != 'true') {
      throw StateError('"$plannerEvent" not checked after the reload: $box');
    }
    final lecture = await _waitLabel(cdp, icsSummary,
        const Duration(seconds: 20), contains: true);
    result['lecture_after_reload'] = lecture;
    await _dump(cdp, 'reload_activity');
    final files = await _opfs(cdp);
    result['folder_after_reload'] = files;
    _expectText(files, 'planner/feeds.json', icsCalendar);
    if (_eventRow(files, plannerEvent)?['is_completed'] != true) {
      throw StateError('events.json lost is_completed after the reload');
    }
  });
}

/// A one-event calendar for tomorrow 10:00-11:00 (browser time zone).
String _ics() {
  String two(int v) => v.toString().padLeft(2, '0');
  final day = DateTime.now().add(const Duration(days: 1));
  final date = '${day.year}${two(day.month)}${two(day.day)}';
  return 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//rel202-e2e//EN\r\n'
      'X-WR-CALNAME:$icsCalendar\r\n'
      'BEGIN:VEVENT\r\nUID:rel202-e2e-1\r\nSUMMARY:$icsSummary\r\n'
      'DTSTART:${date}T100000\r\nDTEND:${date}T110000\r\nEND:VEVENT\r\n'
      'END:VCALENDAR\r\n';
}

Map? _eventRow(String files, String title) {
  final text = _fileText(files, 'planner/events.json');
  if (text == null) return null;
  final decoded = jsonDecode(text);
  final rows = (decoded is Map ? decoded['events'] : decoded) as List;
  for (final row in rows.cast<Map>()) {
    if (row['title'] == title) return row;
  }
  return null;
}

// ----------------------------------------------------------------- portal

const portalEvent = 'E2E portal event';
const portalNote = 'E2E portal note';

Future<void> _portalFlow(_Cdp cdp, Map<String, Object?> result) async {
  await _step('create a planner event', () async {
    await _openTab(cdp, 'Activity');
    await _createEvent(cdp, portalEvent);
    final files = await _opfs(cdp);
    result['folder_after_event'] = files;
    _expectText(files, 'planner/events.json', portalEvent);
  });

  await _step('create a note', () async {
    await _openTab(cdp, 'Learner');
    await _clickLabel(cdp, fabNote);
    await Future<void>.delayed(const Duration(seconds: 3));
    await _dump(cdp, 'note_editor_open');
    await _typeInto(cdp, 'Title', portalNote, selectAll: true);
    await Future<void>.delayed(const Duration(seconds: 1));
    await _dump(cdp, 'note_editor_typed');
    await _closeEditor(cdp);
    await Future<void>.delayed(const Duration(seconds: 3));
    await _dump(cdp, 'note_editor_closed');
    final files = await _opfs(cdp);
    result['folder_after_note'] = files;
    _expectNote(files, portalNote);
    result['note_uuid'] = _noteUuid(files, portalNote);
  });

  await _step('reload: the event and the note stay', () async {
    await _closeDialogs(cdp);
    phase = 'reload';
    await cdp.send('Page.reload');
    await Future<void>.delayed(const Duration(seconds: 2));
    await _semanticsOn(cdp);
    await Future<void>.delayed(const Duration(seconds: 6));
    await _dump(cdp, 'after_reload');
    await _reconnectIfAsked(cdp, result);
    await _openTab(cdp, 'Learner');
    result['note_after_reload'] = await _waitLabel(
        cdp, portalNote, const Duration(seconds: 30),
        contains: true);
    await _dump(cdp, 'reload_learner');
    // Control for the cold route: the same note opened in session.
    await _clickLabel(cdp, portalNote, contains: true);
    await Future<void>.delayed(const Duration(seconds: 3));
    result['in_session_viewer_url'] = await cdp.eval('location.href');
    result['in_session_viewer_title'] =
        await _find(cdp, portalNote, contains: true);
    result['in_session_viewer_diag'] = await _diag(cdp);
    await _dump(cdp, 'in_session_viewer');
    await _closeEditor(cdp);
    await Future<void>.delayed(const Duration(seconds: 2));
    await _openTab(cdp, 'Activity');
    result['event_after_reload'] = await _waitLabel(
        cdp, portalEvent, const Duration(seconds: 30),
        contains: true);
    await _dump(cdp, 'reload_activity');
  });

  await _step('cold #/note/<uuid> of the folder note', () async {
    final uuid = result['note_uuid'];
    if (uuid is! String) throw StateError('no uuid for "$portalNote"');
    phase = 'cold_note';
    await cdp.send('Page.navigate', {'url': 'about:blank'});
    await Future<void>.delayed(const Duration(seconds: 1));
    await cdp.send('Page.navigate', {'url': '$base#/note/$uuid'});
    await Future<void>.delayed(const Duration(seconds: 2));
    await _semanticsOn(cdp);
    await Future<void>.delayed(const Duration(seconds: 6));
    await _dump(cdp, 'cold_note');
    await _reconnectIfAsked(cdp, result);
    result['cold_note_diag_1'] = await _diag(cdp);
    if (await _find(cdp, portalNote, contains: true) == null) {
      // Semantics may have been turned on before the routed page built.
      await cdp.eval("(() => { const p = document.querySelector("
          "'flt-semantics-placeholder'); if (p) p.click(); return true; })()");
      await Future<void>.delayed(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(seconds: 15));
      result['cold_note_diag_2'] = await _diag(cdp);
    }
    result['cold_note_title'] = await _find(cdp, portalNote, contains: true);
    result['cold_note_url'] = await cdp.eval('location.href');
    result['cold_note_sign_in_prompt'] =
        await _find(cdp, 'Continue with Casdoor SSO');
    await _dump(cdp, 'cold_note_open');
  });
}

Future<Object?> _diag(_Cdp cdp) => cdp.eval('''
(() => {
  const all = [...document.querySelectorAll('flt-semantics')];
  const logs = localStorage.getItem('flutter.notechondria.$appName.local_logs') || '';
  let tail = [];
  try { tail = JSON.parse(JSON.parse(logs)).filter(l => /uuid|note|local_folder|Folder|error|\\[E\\]|\\[W\\]/i.test(l)).slice(0, 40); } catch (e) { tail = [String(logs).slice(0, 3000)]; }
  const dlg = document.querySelector('flt-semantics[role="dialog"]');
  return JSON.stringify({
    href: location.href,
    semantics: all.length,
    placeholder: !!document.querySelector('flt-semantics-placeholder'),
    labels: all.map(e => { const r = e.getBoundingClientRect();
      return Math.round(r.width) + 'x' + Math.round(r.height) + ':' + (e.getAttribute('role') || '') + ':' +
        (e.getAttribute('aria-label') || e.textContent || '').trim().slice(0, 80); }).slice(0, 40),
    logs: tail,
    dialog_html: dlg ? dlg.outerHTML.slice(0, 4000) : null,
  });
})()''');

void _expectNote(String files, String title) {
  final rows = (jsonDecode(files) as List).cast<Map>();
  final hit = rows.any((f) =>
      '${f['p']}'.startsWith('notes/') &&
      '${f['p']}'.endsWith('.md') &&
      '${f['text']}'.contains(title));
  if (!hit) throw StateError('no notes/*.md containing "$title"');
}

String? _noteUuid(String files, String title) {
  final rows = (jsonDecode(files) as List).cast<Map>();
  final re = RegExp(
      r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}');
  for (final f in rows) {
    final p = '${f['p']}';
    if (!p.startsWith('notes/') || !p.endsWith('.md')) continue;
    if (!'${f['text']}'.contains(title)) continue;
    final stem = p.substring('notes/'.length, p.length - '.md'.length);
    final meta = rows.where((m) => m['p'] == 'notes/$stem.meta.json');
    for (final m in meta) {
      final hit = RegExp(r'"uuid"\s*:\s*"([0-9a-f-]{36})"')
          .firstMatch('${m['text']}');
      if (hit != null) return hit.group(1);
    }
    final front = RegExp(r'uuid:\s*"?([0-9a-f-]{36})').firstMatch('${f['text']}');
    if (front != null) return front.group(1);
    if (RegExp(r'^[0-9a-f]{32}$').hasMatch(stem)) {
      return '${stem.substring(0, 8)}-${stem.substring(8, 12)}-'
          '${stem.substring(12, 16)}-${stem.substring(16, 20)}-'
          '${stem.substring(20)}';
    }
    final any = re.firstMatch('${f['text']}');
    if (any != null) return any.group(0);
  }
  return null;
}

// ------------------------------------------------------------ shared steps

Future<void> _openTab(_Cdp cdp, String label) async {
  await _closeDialogs(cdp);
  await _clickLabel(cdp, label, exact: true);
  await Future<void>.delayed(const Duration(seconds: 3));
  await _dump(cdp, 'tab_$label');
}

Future<void> _createEvent(_Cdp cdp, String title) async {
  // A SnackBar can cover the FAB right after connect; retry once.
  for (var attempt = 0; attempt < 3; attempt++) {
    await _clickLabel(cdp, fabEvent);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (await _find(cdp, 'Event title') != null) break;
    await _dump(cdp, 'no_event_dialog_$attempt');
    await Future<void>.delayed(const Duration(seconds: 5));
  }
  await _dump(cdp, 'event_dialog');
  await _typeInto(cdp, 'Event title', title, selectAll: false);
  await _dump(cdp, 'event_typed');
  await _clickLabel(cdp, 'Create', exact: true);
  await Future<void>.delayed(const Duration(seconds: 4));
  await _dump(cdp, 'event_created');
  if (await _find(cdp, 'Event title') != null) {
    throw StateError('the New event dialog is still open after Create');
  }
}

Future<void> _openFabMenu(_Cdp cdp, String fab, String item) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    final r = await _reveal(cdp, fab);
    final x = (r['x'] as num) + (r['w'] as num) / 2;
    final y = (r['y'] as num) + (r['h'] as num) / 2;
    await _click(cdp, x, y, button: 'right');
    await Future<void>.delayed(const Duration(seconds: 1));
    if (await _find(cdp, item, exact: true) != null) return;
    await _dump(cdp, 'no_menu_$attempt');
    await Future<void>.delayed(const Duration(seconds: 4));
  }
  throw StateError('"$item" menu never opened from the FAB');
}

Future<void> _reconnectIfAsked(_Cdp cdp, Map<String, Object?> result) async {
  for (final gate in ["Reconnect '", "Choose '"]) {
    if (await _find(cdp, gate) != null) {
      (result['gates'] ??= <String>[]) as List;
      (result['gates'] as List).add('$phase: $gate');
      await _clickLabel(cdp, gate);
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }
}

/// The editor dialog's close button (Icons.close, no tooltip) saves when
/// dirty: the unlabeled button nearest the top-right.
Future<void> _closeEditor(_Cdp cdp) async {
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
}

Future<void> _closeDialogs(_Cdp cdp) async {
  for (var i = 0; i < 4; i++) {
    if (await _find(cdp, 'Close', exact: true) != null) {
      await _clickLabel(cdp, 'Close', exact: true);
    } else if (await _find(cdp, 'Cancel', exact: true) != null) {
      await _clickLabel(cdp, 'Cancel', exact: true);
    } else if (await _find(cdp, 'Back', exact: true) != null) {
      await _clickLabel(cdp, 'Back', exact: true);
    } else {
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
}

Future<void> _clickBox(_Cdp cdp, Map<String, Object?> r) async {
  // The checkbox sits at the leading edge of the CheckboxListTile.
  await _click(cdp, (r['x'] as num) + 28, (r['y'] as num) + 28);
}

// ------------------------------------------------------------ evidence

Future<void> _step(String name, Future<void> Function() body) async {
  final t = DateTime.now();
  stdout.writeln('[e2e:$appName] step: $name ${t.toIso8601String()}');
  try {
    await body();
    steps.add({'name': name, 'ok': true,
      'ms': DateTime.now().difference(t).inMilliseconds});
  } catch (e) {
    steps.add({'name': name, 'ok': false, 'error': '$e'});
    rethrow;
  }
}

String? _fileText(String files, String path) {
  for (final f in (jsonDecode(files) as List).cast<Map>()) {
    if (f['p'] == path) return f['text'] as String?;
  }
  return null;
}

void _expectText(String files, String path, String text) {
  final body = _fileText(files, path);
  if (body == null || !body.contains(text)) {
    throw StateError('$path does not contain "$text"');
  }
}

void _expectSuffix(String files, String suffix, String text) {
  final hit = (jsonDecode(files) as List).cast<Map>().any((f) =>
      '${f['p']}'.endsWith(suffix) && '${f['text']}'.contains(text));
  if (!hit) throw StateError('no *$suffix containing "$text"');
}

Map<String, Object?> _requestSummary() {
  final byPhase = <String, Map<String, Object?>>{};
  if (!netLog.existsSync()) return {};
  for (final line in netLog.readAsLinesSync()) {
    final r = jsonDecode(line) as Map;
    final url = '${r['url']}';
    final p = byPhase.putIfAbsent('${r['phase']}',
        () => {'total': 0, 'api': 0, 'api_urls': <String>[], 'off_host': <String>[]});
    p['total'] = (p['total'] as int) + 1;
    if (url.contains('/api/')) {
      p['api'] = (p['api'] as int) + 1;
      (p['api_urls'] as List).add('${r['method']} $url');
    }
    if (!url.startsWith('http://127.0.0.1:8099/') &&
        !url.startsWith('data:') &&
        !url.startsWith('blob:') &&
        !url.startsWith('about:')) {
      final list = p['off_host'] as List;
      if (!list.contains(url)) list.add(url);
    }
  }
  return byPhase;
}

List<String> _listeners(String path) => File(path)
    .readAsLinesSync()
    .skip(1)
    .map((l) => l.trim().split(RegExp(r'\s+')))
    .where((f) => f.length > 3 && f[3] == '0A')
    .map((f) => f[1])
    .toList();

String get _init => '''
(() => {
  const stats = 'flutter.notechondria.$appName.local_stats';
  if (!localStorage.getItem(stats)) {
    localStorage.setItem(stats, JSON.stringify(JSON.stringify({
      onboarding_seen: true, install_hint_dismissed: true,
      last_seen_version: '$appVersion'})));
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
      const textual = /\.(md|json|ics)$/.test(p) && p !== 'index.json';
      out.push({p, size: f.size, text: textual ? (await f.text()).slice(0, 4000) : null});
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
((want, exact, contains, role) => {
  let best = null;
  const sel = role ? `[role="${role}"]`
    : contains ? '[role="button"], flt-semantics' : 'flt-semantics, [role="button"], input, textarea';
  for (const el of document.querySelectorAll(sel)) {
    const text = (el.getAttribute('aria-label') || el.textContent || '').trim();
    if (contains ? !text.includes(want) : exact ? text !== want : !text.startsWith(want)) continue;
    const r = el.getBoundingClientRect();
    if (r.width <= 0 || r.height <= 0) continue;
    if (!best || r.width * r.height < best.w * best.h) {
      best = {x: r.left, y: r.top, w: r.width, h: r.height, tag: el.tagName,
              role: el.getAttribute('role'), text: text.slice(0, 120),
              disabled: el.getAttribute('aria-disabled'),
              checked: el.getAttribute('aria-checked')};
    }
  }
  return best ? JSON.stringify(best) : null;
})''';

Future<Map<String, Object?>?> _find(_Cdp cdp, String want,
    {bool exact = false, bool contains = false, String? role}) async {
  final v = await cdp.eval(
      '$_findJs(${jsonEncode(want)}, $exact, $contains, ${jsonEncode(role)})');
  return v is String ? (jsonDecode(v) as Map).cast<String, Object?>() : null;
}

Future<Map<String, Object?>> _waitLabel(_Cdp cdp, String want, Duration limit,
    {bool exact = false, bool contains = false, String? role}) async {
  final end = DateTime.now().add(limit);
  while (DateTime.now().isBefore(end)) {
    final f =
        await _find(cdp, want, exact: exact, contains: contains, role: role);
    if (f != null) return f;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  await _dump(cdp, 'missing_${want.replaceAll(RegExp(r'[^A-Za-z]'), '_')}');
  throw TimeoutException('"$want" never appeared');
}

Future<void> _clickLabel(_Cdp cdp, String want,
    {bool exact = false, bool contains = false}) async {
  final r = await _reveal(cdp, want, exact: exact, contains: contains);
  await _click(cdp, (r['x'] as num) + (r['w'] as num) / 2,
      (r['y'] as num) + (r['h'] as num) / 2);
}

/// Waits for [want] and wheel-scrolls until its center sits inside the
/// viewport above the bottom navigation bar (semantics rects are not
/// clipped by the bar, so a click there would hit the bar).
Future<Map<String, Object?>> _reveal(_Cdp cdp, String want,
    {bool exact = false, bool contains = false, String? role}) async {
  var r = await _waitLabel(cdp, want, const Duration(seconds: 20),
      exact: exact, contains: contains, role: role);
  for (var i = 0; i < 6; i++) {
    final height = (await cdp.eval('window.innerHeight')) as num;
    final mid = (r['y'] as num) + (r['h'] as num) / 2;
    final small = (r['h'] as num) < 16;
    if (mid > 70 && mid < height - 110 && !small) return r;
    await cdp.send('Input.dispatchMouseEvent', {
      'type': 'mouseWheel', 'x': 450, 'y': height / 2,
      'deltaX': 0, 'deltaY': mid - height / 2,
    });
    await Future<void>.delayed(const Duration(milliseconds: 900));
    r = await _waitLabel(cdp, want, const Duration(seconds: 10),
        exact: exact, contains: contains, role: role);
  }
  return r;
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
      "(e.getAttribute('aria-checked') || '') + ':' + "
      "(e.getAttribute('aria-label') || e.value || e.textContent || '')"
      ".trim().slice(0, 120)).filter(t => !t.endsWith(':')))");
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

Future<void> _click(_Cdp cdp, num x, num y, {String button = 'left'}) async {
  final buttons = button == 'right' ? 2 : 1;
  await cdp.send('Input.dispatchMouseEvent', {'type': 'mouseMoved', 'x': x, 'y': y});
  await cdp.send('Input.dispatchMouseEvent', {
    'type': 'mousePressed', 'x': x, 'y': y, 'button': button,
    'buttons': buttons, 'clickCount': 1,
  });
  await Future<void>.delayed(const Duration(milliseconds: 80));
  await cdp.send('Input.dispatchMouseEvent', {
    'type': 'mouseReleased', 'x': x, 'y': y, 'button': button,
    'buttons': 0, 'clickCount': 1,
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
