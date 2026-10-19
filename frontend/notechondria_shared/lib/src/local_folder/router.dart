import 'dart:typed_data';

import 'folder_fs.dart';
import 'folder_index.dart';
import 'folder_journal.dart';
import 'folder_lock.dart';
import 'folder_messages.dart';

// The in-page `/api/v1` router (main 2.5, 4.1): the `(method, path)` table,
// `/api/v1/` segment matching, and the 501 and 404 fallbacks. Handlers live
// in `handlers/`; `LocalFolderTransport` decodes requests and runs them.

/// The header every in-page answer carries, and its value (main 2.5).
const String kLocalBackendHeader = 'x-notechondria-backend';
const String kLocalBackendHeaderValue = 'local-folder';

/// One uploaded file of a multipart request.
class LocalUpload {
  const LocalUpload({
    required this.field,
    required this.bytes,
    this.filename,
    this.contentType,
  });

  final String field;
  final Uint8List bytes;
  final String? filename;
  final String? contentType;
}

/// A decoded request. [json] is the JSON body; multipart requests carry
/// [fields] and [files] instead.
class LocalRequest {
  LocalRequest({
    required this.method,
    required this.url,
    required this.segments,
    this.headers = const {},
    this.json,
    this.fields = const {},
    this.files = const [],
    this.params = const {},
  });

  final String method;
  final Uri url;

  /// Path segments after `/api/v1/`, without the trailing empty one.
  final List<String> segments;
  final Map<String, String> headers;
  final Object? json;
  final Map<String, String> fields;
  final List<LocalUpload> files;

  /// Values of the route pattern's `{name}` segments.
  Map<String, String> params;

  bool get isRead => method == 'GET' || method == 'HEAD';
  String get path => url.path;
  Map<String, String> get query => url.queryParameters;

  /// The JSON object body, or the multipart fields; empty otherwise.
  Map<String, Object?> get body {
    final value = json;
    if (value is Map) return Map<String, Object?>.from(value);
    return Map<String, Object?>.from(fields);
  }

  /// The token of the `Authorization` header. The folder has one user, so
  /// the transport never checks it (main 2.5); the session route echoes it.
  String? get token {
    final raw = headers['authorization'] ?? headers['Authorization'];
    if (raw == null || raw.trim().isEmpty) return null;
    final parts = raw.trim().split(RegExp(r'\s+'));
    return parts.length > 1 ? parts.sublist(1).join(' ') : parts.first;
  }

  int intParam(String name) => int.parse(params[name]!);
}

/// A JSON answer; a null [body] is sent as an empty body (204).
class LocalResponse {
  const LocalResponse(this.status, [this.body]);

  static const LocalResponse noContent = LocalResponse(204);

  final int status;
  final Object? body;
}

/// Thrown by a handler for a 4xx/5xx answer with a 1.8 [detail].
class LocalHttpError implements Exception {
  const LocalHttpError(this.status, this.detail);
  final int status;
  final String detail;
  @override
  String toString() => detail;
}

/// What a handler may use. The transport implements it per request.
abstract class LocalHandlerContext {
  LocalRequest get request;
  FolderFs get fs;
  FolderJournal get journal;
  FolderLocks get locks;
  String get lockName;
  String get app;
  String get appVersion;
  String get folderName;

  /// Paths of a pending journal record that failed to roll forward; reads
  /// skip them (6.2 R3). Write lookups do not, so [commit] and [writeText]
  /// refuse a write that touches one (P1B-3).
  Set<String> get skipPaths;
  DateTime now();

  /// The controller's in-memory index (6.2 R2): a cache for locating notes
  /// and for list summaries, never the base of a write. [commit] and
  /// [writeText] keep it current for this tab's own writes.
  FolderIndex get index;

  /// Whether the entry at [path] came from `index.json` and has not been
  /// compared with the disk yet; list routes check such entries first (3.8).
  bool isUnverified(String path);

  /// Replaces index entries (a null value drops one) after a handler
  /// re-read files the index had out of date or did not have; [verified]
  /// paths were compared with the disk and kept.
  void updateIndex(Map<String, IndexedFile?> changes,
      {Iterable<String> verified = const []});

  /// Per note UUID, the body `lastModified` this tab last served (3.8).
  Map<String, int> get servedLastModified;

  /// Journal commit (3.4.1 steps 2 to 5) under the current exclusive hold,
  /// then the `md_size`/`md_last_modified` stamp of each body it wrote and
  /// the index entries of every path it wrote or removed. Before the first
  /// write it checks the 7 s write deadline (2.9) and the pending paths of
  /// a failed roll-forward.
  Future<void> commit(JournalRecord record);

  /// A single-file write under the current exclusive hold, with the same
  /// checks as [commit].
  Future<void> writeText(String path, String text);

  /// One chunk of a chunked operation (6.2 R4): an exclusive hold of its
  /// own with roll-forward first. Only routes marked `chunked` call it.
  Future<T> chunk<T>(Future<T> Function() step);

  /// The status card's busy line (6.2 R4), or null when done.
  void setBusy(String? line);

  void log(LocalFolderLogLevel level, String message);
}

typedef LocalHandler = Future<LocalResponse> Function(LocalHandlerContext ctx);

class LocalRoute {
  LocalRoute(this.method, String pattern, this.handler,
      {this.chunked = false, this.everyState = false})
      : pattern = pattern.split('/');

  final String method;
  final List<String> pattern;
  final LocalHandler handler;

  /// Takes the lock per chunk through [LocalHandlerContext.chunk] (R4).
  final bool chunked;

  /// Answered from memory in every folder state, without the lock
  /// (`GET /handshake/`, `GET /ping/`, 2.8 rule 4).
  final bool everyState;
}

/// The router's answer: a [route] with [params], or a fallback [status]
/// with its [detail].
class LocalRouteMatch {
  const LocalRouteMatch.route(this.route, this.params)
      : status = 0,
        detail = null;
  const LocalRouteMatch.fallback(this.status, this.detail)
      : route = null,
        params = const {};

  final LocalRoute? route;
  final Map<String, String> params;
  final int status;
  final String? detail;
}

/// Segments after the first `/api/v1/` in [path] (a base URL may carry a
/// prefix), or null when the path has none.
List<String>? apiV1Segments(String path) {
  const marker = '/api/v1/';
  final at = path.indexOf(marker);
  if (at < 0) return path.endsWith('/api/v1') ? const [] : null;
  final rest = path.substring(at + marker.length);
  final segments = rest.split('/');
  if (segments.isNotEmpty && segments.last.isEmpty) segments.removeLast();
  return segments;
}

final RegExp _intSegment = RegExp(r'^\d{1,15}$');
final RegExp _uuidSegment = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false);

Map<String, String>? _matchPattern(List<String> pattern, List<String> path) {
  if (pattern.length != path.length) return null;
  final params = <String, String>{};
  for (var i = 0; i < pattern.length; i++) {
    final p = pattern[i];
    final s = path[i];
    if (p.startsWith('{') && p.endsWith('}')) {
      final name = p.substring(1, p.length - 1);
      final ok = name == 'uuid' ? _uuidSegment.hasMatch(s) : _intSegment.hasMatch(s);
      if (!ok) return null;
      params[name] = name == 'uuid' ? s.toLowerCase() : s;
    } else if (p != s) {
      return null;
    }
  }
  return params;
}

/// A route the folder answers with 501: a class (c) feature (4.2) or one
/// whose handler arrives in a later phase (9.1). [methods] is null for all.
class _Fallback {
  _Fallback(this.methods, String pattern, this.detail)
      : pattern = pattern.split('/');
  final Set<String>? methods;
  final List<String> pattern;
  final String Function(String method, String path) detail;
}

_Fallback _serverOnly(Set<String>? methods, String pattern, String detail) =>
    _Fallback(methods, pattern, (_, __) => detail);

_Fallback _later(String pattern, String feature, {Set<String>? methods}) =>
    _Fallback(methods, pattern,
        (m, p) => LocalFolderMessages.laterRelease(feature, m, p));

/// The (c) routes of 4.1 and the routes of Phases 2 to 5. Every detail
/// contains "—" and no session-rejection sentinel or deep-link marker.
final List<_Fallback> _fallbacks = [
  _serverOnly({'POST'}, 'auth/login', LocalFolderMessages.emailSignIn),
  _serverOnly({'POST'}, 'auth/casdoor/exchange', LocalFolderMessages.casdoorSignIn),
  _serverOnly({'POST'}, 'auth/casdoor/bind', LocalFolderMessages.accountLinking),
  _serverOnly({'POST'}, 'auth/casdoor/link/bind', LocalFolderMessages.accountLinking),
  _serverOnly({'POST'}, 'auth/casdoor/link/create', LocalFolderMessages.accountLinking),
  _serverOnly({'DELETE'}, 'auth/casdoor/unlink', LocalFolderMessages.accountLinking),
  _serverOnly({'POST'}, 'auth/rotate-api-key', LocalFolderMessages.mcpUnavailable),
  _serverOnly(null, 'courses/{id}/subscribe', LocalFolderMessages.courseNotSubscribed),
  _serverOnly(null, 'courses/{id}/subscribe-private',
      LocalFolderMessages.courseNotSubscribed),
  _serverOnly(null, 'courses/{id}/transfer', LocalFolderMessages.courseNotTransferred),
  // T7(f): F18 answers 501; the app gates its callback with cloudOnly(...).
  _serverOnly(null, 'admin/template-courses/restore',
      LocalFolderMessages.templateCoursesNotRestored),
  _serverOnly(null, 'integrations/github/callback',
      LocalFolderMessages.githubAppUnavailable),
  _later('front-page', 'The front page'),
  _later('notes/{id}/history', 'Note history'),
  _later('notes/{id}/snapshot', 'Note history'),
  _later('notes/{id}/restore/{version}', 'Note history'),
  _later('note-sessions', 'Study sessions'),
  _later('note-sessions/{id}', 'Study sessions'),
  _later('notes/{id}/attachments', 'Attachments'),
  _later('notes/{id}/attachments/{aid}', 'Attachments'),
  _later('notes/uuid/{uuid}/attachments', 'Attachments'),
  _later('notes/uuid/{uuid}/attachments/{aid}', 'Attachments'),
  _later('notes/{id}/cover', 'Note covers'),
  _later('planner-events', 'Planner events'),
  _later('planner-events/{id}', 'Planner events'),
  _later('activity', 'The deadline list'),
  _later('activity/week', 'The week view'),
  _later('heatmap', 'The activity heatmap'),
  _later('calendar-feeds', 'Calendar feeds'),
  _later('calendar-feeds/{id}', 'Calendar feeds'),
  _later('courses/{id}/git', 'Course repository sync'),
  _later('courses/{id}/git/import', 'Course repository sync'),
  _later('courses/{id}/git/sync', 'Course repository sync'),
  _later('integrations/github/status', 'GitHub data sync'),
  _later('integrations/github/repos', 'GitHub data sync'),
  _later('integrations/github/push', 'GitHub data sync'),
];

/// The `(method, path)` table. A path without `/api/v1/` answers 404; an
/// `/api/v1/` path without a handler answers 501 (2.8 rule 2).
class LocalBackendRouter {
  LocalBackendRouter(List<LocalRoute> routes) : _routes = List.unmodifiable(routes);

  final List<LocalRoute> _routes;

  List<LocalRoute> get routes => _routes;

  LocalRouteMatch match(String method, String path) {
    final upper = method.toUpperCase();
    final segments = apiV1Segments(path);
    if (segments == null) {
      return LocalRouteMatch.fallback(
          404, scrubRouteDetail(LocalFolderMessages.notApiRoute(upper, path)));
    }
    for (final route in _routes) {
      if (route.method != upper) continue;
      final params = _matchPattern(route.pattern, segments);
      if (params != null) return LocalRouteMatch.route(route, params);
    }
    for (final f in _fallbacks) {
      if (f.methods != null && !f.methods!.contains(upper)) continue;
      if (_matchPattern(f.pattern, segments) != null) {
        return LocalRouteMatch.fallback(501, scrubRouteDetail(f.detail(upper, path)));
      }
    }
    return LocalRouteMatch.fallback(
        501, scrubRouteDetail(LocalFolderMessages.routeUnsupported(upper, path)));
  }
}
