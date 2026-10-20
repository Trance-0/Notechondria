import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'folder_fs.dart';
import 'folder_index.dart';
import 'folder_journal.dart';
import 'folder_layout.dart';
import 'folder_lock.dart';
import 'folder_messages.dart';
import 'folder_scanner.dart' show isIndexedPath;
import 'handlers/activity.dart';
import 'handlers/attachments.dart';
import 'handlers/auth_settings.dart';
import 'handlers/courses.dart';
import 'handlers/history_sessions.dart';
import 'handlers/notes.dart';
import 'handlers/trash.dart';
import 'local_folder_controller.dart';
import 'note_codec.dart';
import 'router.dart';

// `LocalFolderTransport` (main 2.5): decodes each request (JSON or
// multipart), applies the folder states of 2.8 rule 4 (the `opening` hold
// and the 503 details), takes the folder lock in the mode of 6.2 R1, runs
// the handler within the read and write deadlines of 2.9, and answers JSON
// with `x-notechondria-backend: local-folder`. No request reaches the
// network from here.

/// Every route the folder answers (9.1): Phase 1, and the Phase 2 content
/// routes (attachments, covers, history, sessions, front page, heatmap).
LocalBackendRouter localFolderRouter() => LocalBackendRouter([
      ...authSettingsRoutes(),
      ...courseRoutes(),
      ...trashRoutes(),
      ...noteRoutes(),
      ...attachmentRoutes(),
      ...historySessionRoutes(),
      ...activityRoutes(),
    ]);

/// A deadline passed; [cause] is one of the 2.9 causes.
class _Deadline implements Exception {
  const _Deadline(this.cause);
  final String cause;
}

/// Reads a request into a [LocalRequest]: multipart fields and files, a
/// form body, or JSON.
Future<LocalRequest> decodeLocalRequest(
    http.BaseRequest request, LocalRouteMatch match) async {
  final headers = {
    for (final e in request.headers.entries) e.key.toLowerCase(): e.value,
  };
  Object? json;
  var fields = <String, String>{};
  final files = <LocalUpload>[];
  if (request is http.MultipartRequest) {
    fields = Map.of(request.fields);
    for (final f in request.files) {
      files.add(LocalUpload(
        field: f.field,
        filename: f.filename,
        contentType: f.contentType.mimeType,
        bytes: await f.finalize().toBytes(),
      ));
    }
  } else {
    final Uint8List bytes = request is http.Request
        ? request.bodyBytes
        : await request.finalize().toBytes();
    if (bytes.isNotEmpty) {
      final text = utf8.decode(bytes, allowMalformed: true);
      if ((headers['content-type'] ?? '')
          .contains('application/x-www-form-urlencoded')) {
        fields = Uri.splitQueryString(text);
      } else {
        try {
          json = jsonDecode(text);
        } on FormatException {
          throw LocalHttpError(
              400,
              LocalFolderMessages.invalidField('Request not answered', 'route',
                  '${request.method} ${request.url.path} sent a body that is not JSON'));
        }
      }
    }
  }
  return LocalRequest(
    method: request.method.toUpperCase(),
    url: request.url,
    segments: apiV1Segments(request.url.path) ?? const [],
    headers: headers,
    json: json,
    fields: fields,
    files: files,
    params: match.params,
  );
}

class LocalFolderTransport extends http.BaseClient {
  LocalFolderTransport(
    this.controller, {
    LocalBackendRouter? router,
    this.readDeadline = kFolderReadDeadline,
    this.writeDeadline = kFolderWriteDeadline,
  }) : router = router ?? localFolderRouter();

  final LocalFolderController controller;
  final LocalBackendRouter router;
  final Duration readDeadline;
  final Duration writeDeadline;

  /// Per note UUID, the body `lastModified` last served to this tab (3.8).
  final Map<String, int> servedLastModified = <String, int>{};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final watch = Stopwatch()..start();
    final method = request.method.toUpperCase();
    final isRead = method == 'GET' || method == 'HEAD';
    final deadline = isRead ? readDeadline : writeDeadline;
    final path = request.url.path;
    Duration left() => deadline - watch.elapsed;
    final match = router.match(method, path);
    final route = match.route;
    if (match.status == 404) return _detail(request, 404, match.detail!);
    try {
      if (route != null && route.everyState) {
        final ctx = _Context(this, await decodeLocalRequest(request, match),
            watch: watch, deadline: deadline);
        return _encode(request, await route.handler(ctx));
      }
      if (controller.state == LocalFolderState.opening &&
          !await controller.waitWhileOpening(left())) {
        throw const _Deadline(kDeadlineCauseOpening);
      }
      final unavailable = controller.unavailableDetail(isRead: isRead);
      if (unavailable != null) return _detail(request, 503, unavailable);
      if (route == null) return _detail(request, match.status, match.detail!);
      final ctx = _Context(this, await decodeLocalRequest(request, match),
          watch: watch, deadline: deadline);
      final answer = isRead
          ? await _read(route, ctx, left)
          : await _write(route, ctx, left);
      return _encode(request, answer);
    } on LocalHttpError catch (e) {
      return _detail(request, e.status, e.detail);
    } on _Deadline catch (e) {
      return _detail(
          request,
          503,
          isRead
              ? LocalFolderMessages.readDeadline(path, e.cause)
              : LocalFolderMessages.writeDeadline(method, path, e.cause));
    } on FolderLockTimeout catch (e) {
      return _detail(
          request,
          503,
          LocalFolderMessages.lockWaitFailed(
              method: method, path: path, cutByDeadline: e.cutByDeadline));
    } on FolderFsException catch (e) {
      final process = isRead ? 'read' : 'write';
      final lost = e.kind == FolderErrorKind.notAllowed ||
          (e.kind == FolderErrorKind.notFound && e.path.isEmpty);
      if (lost) controller.reportFolderError(e, process: process);
      final detail = (lost ? controller.unavailableDetail(isRead: isRead) : null) ??
          LocalFolderMessages.requestFailed(method, path, '$e');
      return _detail(request, lost ? 503 : 500, detail);
    } on FolderLayoutException catch (e) {
      return _detail(request, 503, e.message);
    } on FolderJournalException catch (e) {
      return _detail(request, 503, e.message);
    } catch (e) {
      final detail = LocalFolderMessages.requestFailed(method, path, '$e');
      controller.log(LocalFolderLogLevel.warning, scrubSessionSentinels(detail));
      return _detail(request, 500, detail);
    }
  }

  /// R1 and R3: the shared lock, with roll-forward when the journal is not
  /// empty; every wait and the handler count against the 8 s deadline.
  Future<LocalResponse> _read(
      LocalRoute route, _Context ctx, Duration Function() left) {
    final remaining = left();
    if (remaining <= Duration.zero) {
      throw const _Deadline(kDeadlineCauseLockWait);
    }
    var stage = kDeadlineCauseLockWait;
    return readWithJournalCheck<LocalResponse>(
      locks: controller.locks,
      lockName: controller.lockName,
      journal: controller.journal!,
      timeLeft: left,
      read: (skip) {
        stage = kDeadlineCauseStalled;
        ctx.skipPaths = skip;
        return route.handler(ctx);
      },
    ).timeout(remaining, onTimeout: () => throw _Deadline(stage));
  }

  /// R1: the exclusive lock for every other method; chunked routes take it
  /// per chunk (R4).
  Future<LocalResponse> _write(
      LocalRoute route, _Context ctx, Duration Function() left) {
    if (route.chunked) return route.handler(ctx);
    return ctx.chunk(() => route.handler(ctx));
  }

  http.StreamedResponse _encode(http.BaseRequest request, LocalResponse r) {
    final body = r.body;
    final Uint8List bytes =
        body == null ? Uint8List(0) : utf8.encode(jsonEncode(body));
    return http.StreamedResponse(http.ByteStream.fromBytes(bytes), r.status,
        contentLength: bytes.length,
        request: request,
        headers: kLocalResponseHeaders);
  }

  /// Every detail goes through the sentinel scrub (2.5); every 404 and 501,
  /// from the router or thrown by a handler, also through the deep-link
  /// marker scrub, because they may interpolate the request path (12.4,
  /// P1B-4).
  http.StreamedResponse _detail(
          http.BaseRequest request, int status, String detail) =>
      _encode(
          request,
          LocalResponse(status, {
            'detail': status == 404 || status == 501
                ? scrubRouteDetail(detail)
                : scrubSessionSentinels(detail),
          }));
}

class _Context implements LocalHandlerContext {
  _Context(this._transport, this.request,
      {required Stopwatch watch, required Duration deadline})
      : _watch = watch,
        _deadline = deadline;

  final LocalFolderTransport _transport;
  final Stopwatch _watch;
  final Duration _deadline;
  bool _started = false;

  LocalFolderController get _controller => _transport.controller;

  @override
  final LocalRequest request;

  @override
  Set<String> skipPaths = const <String>{};

  @override
  FolderFs get fs => _controller.folder!;
  @override
  FolderJournal get journal => _controller.journal!;
  @override
  FolderLocks get locks => _controller.locks;
  @override
  String get lockName => _controller.lockName;
  @override
  String get app => _controller.app;
  @override
  String get appVersion => _controller.appVersion;
  @override
  String get folderName => _controller.folderName;
  @override
  Map<String, int> get servedLastModified => _transport.servedLastModified;
  @override
  DateTime now() => _controller.now();

  @override
  FolderIndex get index =>
      _controller.index ??
      FolderIndex(folderId: '', generatedAt: '', files: const {});

  @override
  bool isUnverified(String path) => _controller.isUnverified(path);

  @override
  void updateIndex(Map<String, IndexedFile?> changes,
          {Iterable<String> verified = const []}) =>
      _controller.updateIndex(changes, verified: verified);

  /// P1B-1: the index entries of the paths this request wrote (from the
  /// text it wrote and a fresh stat) and removed. They reach `index.json`
  /// through the controller's coalesced flush (L2A-1).
  Future<void> _reindex(Map<String, String> written,
      {Iterable<String> removed = const [],
      Iterable<String> removedDirs = const []}) async {
    final changes = <String, IndexedFile?>{
      for (final path in removed)
        if (isIndexedPath(path)) path: null,
    };
    for (final e in written.entries) {
      if (!isIndexedPath(e.key)) continue;
      final stat = await fs.stat(e.key);
      changes[e.key] = stat == null
          ? null
          : indexFile(e.key, stat, indexReadsContent(e.key) ? e.value : null);
    }
    _controller.updateIndex(changes, removedDirs: removedDirs, written: true);
  }

  /// 2.9: a write that has not started by the deadline changes nothing;
  /// once it has started it runs to the end.
  void _beforeWrite(Iterable<String> paths) {
    if (!_started) {
      if (_watch.elapsed > _deadline) {
        throw const _Deadline(kDeadlineCauseStalled);
      }
      _started = true;
    }
    if (skipPaths.isNotEmpty && paths.any(skipPaths.contains)) {
      throw const LocalHttpError(503, LocalFolderMessages.writeBlockedByJournal);
    }
  }

  @override
  Future<void> commit(JournalRecord record) async {
    _beforeWrite(record.touchedPaths);
    await journal.commit(record);
    for (final w in record.writes) {
      if (isNoteBodyPath(w.path)) await stampNoteSidecar(fs, w.path);
    }
    await _reindex({for (final w in record.writes) w.path: w.text},
        removed: [
          for (final r in record.removals)
            if (!r.directory) r.path,
        ],
        removedDirs: [
          for (final r in record.removals)
            if (r.directory) r.path,
        ]);
  }

  @override
  Future<void> writeText(String path, String text) async {
    _beforeWrite([path]);
    await fs.writeText(path, text);
    await _reindex({path: text});
  }

  @override
  Future<void> writeBytes(String path, Uint8List bytes) async {
    _beforeWrite([path]);
    await fs.writeBytes(path, bytes);
    await _reindex({path: ''});
  }

  @override
  Future<T> chunk<T>(Future<T> Function() step) {
    final left = _started ? null : _deadline - _watch.elapsed;
    return locks.run(lockName, FolderLockMode.exclusive, () async {
      final rolled = await rollForwardHeld(journal);
      if (rolled.failed) {
        final failure = rolled.failure;
        if (failure is FolderFsException &&
            failure.kind == FolderErrorKind.notAllowed) {
          throw failure;
        }
        skipPaths = await journal.pendingPaths();
      }
      return step();
    }, timeLeft: left);
  }

  @override
  void setBusy(String? line) => _controller.setBusy(line);

  @override
  void log(LocalFolderLogLevel level, String message) =>
      _controller.log(level, scrubSessionSentinels(message));
}
