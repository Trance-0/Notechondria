import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../components/debug_log.dart' show PingResult;

/// Issues a `GET <apiBaseUrl>/ping/` probe to measure backend
/// round-trip latency and surface the response in the debug-log
/// terminal. Shared across editor / planner / portal so the three
/// apps don't each hand-roll their own HTTP probe.
///
/// `apiBaseUrl` is expected to already include the `/api/v1` suffix
/// that the rest of the client code uses (every app's
/// `HttpNotechondriaClient` normalizes it the same way). If the
/// caller can pass `null` (e.g. when the app hasn't resolved its
/// base URL yet), the helper returns a `PingResult` with `ok=false`
/// instead of throwing, because the terminal treats the return
/// value as the line to print.
///
/// Times out after 10 seconds. A slow response that exceeds that
/// comes back as `ok=false` so the terminal can show the failure
/// without hanging the debug log card.
Future<PingResult> pingBackend(String? apiBaseUrl) async {
  if (apiBaseUrl == null || apiBaseUrl.trim().isEmpty) {
    return const PingResult(
      ok: false,
      latencyMs: 0,
      detail: 'no API base URL configured',
    );
  }
  final base = apiBaseUrl.trim().endsWith('/')
      ? apiBaseUrl.trim().substring(0, apiBaseUrl.trim().length - 1)
      : apiBaseUrl.trim();
  final uri = Uri.parse('$base/ping/');
  final started = DateTime.now();
  try {
    final response = await http.get(uri, headers: {
      'Accept': 'application/json'
    }).timeout(const Duration(seconds: 10));
    final latency = DateTime.now().difference(started).inMilliseconds;
    if (response.statusCode != 200) {
      return PingResult(
        ok: false,
        latencyMs: latency,
        detail: 'HTTP ${response.statusCode} from ${uri.path}',
      );
    }
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final pong = body['pong'] == true;
      final service = body['service']?.toString() ?? '';
      final detail = pong
          ? (service.isEmpty ? 'pong' : 'pong from $service')
          : 'unexpected payload: ${body.keys.join(", ")}';
      return PingResult(ok: pong, latencyMs: latency, detail: detail);
    } on FormatException {
      return PingResult(
        ok: false,
        latencyMs: latency,
        detail: 'non-JSON response (${response.body.length} bytes)',
      );
    }
  } on TimeoutException {
    final latency = DateTime.now().difference(started).inMilliseconds;
    return PingResult(
      ok: false,
      latencyMs: latency,
      detail: 'timed out waiting for ${uri.host}',
    );
  } catch (error) {
    final latency = DateTime.now().difference(started).inMilliseconds;
    final cause = error.toString().replaceFirst('Exception: ', '');
    return PingResult(ok: false, latencyMs: latency, detail: cause);
  }
}
