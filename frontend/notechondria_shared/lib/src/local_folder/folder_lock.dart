import 'dart:async';
import 'dart:collection';

// Folder lock (security and tabs 6.2 R1, R4, R5). The web implementation is
// `folder_lock_web.dart` over `navigator.locks`; [MemoryFolderLocks] is the
// in-process double for VM tests (8.2).

enum FolderLockMode { shared, exclusive }

/// R5: the longest a request waits for the lock.
const Duration kFolderLockWait = Duration(seconds: 5);

/// R4: the target length of one hold; longer operations are chunked.
const Duration kFolderLockHoldTarget = Duration(seconds: 2);

/// `navigator.locks` name of a folder (3.7 "Folder identity").
String folderLockName(String folderId) => 'notechondria.local_folder.$folderId';

/// Called after every hold with its length, for hold-time logging.
typedef FolderLockHoldObserver = void Function(
    String name, FolderLockMode mode, Duration held);

/// A lock wait ended before the lock was granted.
class FolderLockTimeout implements Exception {
  const FolderLockTimeout({
    required this.name,
    required this.mode,
    required this.waited,
    required this.cutByDeadline,
  });

  final String name;
  final FolderLockMode mode;
  final Duration waited;

  /// True when the request deadline, not the 5 s cap, ended the wait
  /// (T7(h)): the message then names the deadline, not "more than 5 s".
  final bool cutByDeadline;

  @override
  String toString() => 'Folder lock $name (${mode.name}) not granted within '
      '${waited.inMilliseconds} ms${cutByDeadline ? ' (request deadline)' : ''}';
}

/// Serializes folder access across tabs. Locks are not re-entrant: take the
/// lock once per request and call `FolderFs` directly inside the hold.
abstract class FolderLocks {
  /// Runs [operation] while holding [name] in [mode], and releases the lock
  /// exactly when [operation] completes or throws. Waits at most
  /// min([kFolderLockWait], [timeLeft]); a wait that ends first throws
  /// [FolderLockTimeout].
  Future<T> run<T>(
    String name,
    FolderLockMode mode,
    Future<T> Function() operation, {
    Duration? timeLeft,
  });
}

/// The wait for one lock request: the cap, or less when the request
/// deadline is closer (2.9 "Bounds").
({Duration wait, bool cutByDeadline}) folderLockWait(
    Duration? timeLeft, Duration cap) {
  if (timeLeft == null || timeLeft >= cap) {
    return (wait: cap, cutByDeadline: false);
  }
  return (
    wait: timeLeft.isNegative ? Duration.zero : timeLeft,
    cutByDeadline: true,
  );
}

class _MemoryRequest {
  _MemoryRequest(this.mode);
  final FolderLockMode mode;
  final Completer<void> granted = Completer<void>();
}

class _MemoryQueue {
  final Queue<_MemoryRequest> pending = Queue<_MemoryRequest>();
  final List<_MemoryRequest> held = <_MemoryRequest>[];

  /// Web Locks grant order: FIFO; an exclusive request needs nothing held,
  /// a shared one needs no exclusive hold and no exclusive request ahead.
  void process() {
    while (pending.isNotEmpty) {
      final next = pending.first;
      if (next.mode == FolderLockMode.exclusive) {
        if (held.isNotEmpty) return;
        _grant(next);
        return;
      }
      if (held.any((r) => r.mode == FolderLockMode.exclusive)) return;
      _grant(next);
    }
  }

  void _grant(_MemoryRequest request) {
    pending.removeFirst();
    held.add(request);
    request.granted.complete();
  }
}

/// In-process readers-writer lock with the Web Locks grant order and abort
/// timeouts, shared by several transports in one test (8.2). It holds the
/// lock for as long as the Dart operation runs, so it cannot show the
/// JavaScript return-value bug of main 2.5; `local_folder_opfs_test.dart`
/// covers that in Chromium.
class MemoryFolderLocks implements FolderLocks {
  MemoryFolderLocks({this.maxWait = kFolderLockWait, this.onHold});

  final Duration maxWait;
  final FolderLockHoldObserver? onHold;
  final Map<String, _MemoryQueue> _queues = <String, _MemoryQueue>{};

  /// Number of granted holds on [name].
  int heldCount(String name) => _queues[name]?.held.length ?? 0;

  int pendingCount(String name) => _queues[name]?.pending.length ?? 0;

  bool isHeldExclusive(String name) =>
      _queues[name]?.held.any((r) => r.mode == FolderLockMode.exclusive) ??
      false;

  @override
  Future<T> run<T>(
    String name,
    FolderLockMode mode,
    Future<T> Function() operation, {
    Duration? timeLeft,
  }) async {
    final bound = folderLockWait(timeLeft, maxWait);
    if (timeLeft != null && timeLeft <= Duration.zero) {
      throw FolderLockTimeout(
          name: name, mode: mode, waited: Duration.zero, cutByDeadline: true);
    }
    final queue = _queues.putIfAbsent(name, _MemoryQueue.new);
    final request = _MemoryRequest(mode);
    queue.pending.add(request);
    queue.process();
    if (!request.granted.isCompleted) {
      final timer = Timer(bound.wait, () {
        if (request.granted.isCompleted) return;
        queue.pending.remove(request);
        request.granted.completeError(FolderLockTimeout(
            name: name,
            mode: mode,
            waited: bound.wait,
            cutByDeadline: bound.cutByDeadline));
        queue.process();
      });
      try {
        await request.granted.future;
      } finally {
        timer.cancel();
      }
    }
    final started = DateTime.now();
    try {
      return await operation();
    } finally {
      queue.held.remove(request);
      onHold?.call(name, mode, DateTime.now().difference(started));
      queue.process();
    }
  }
}
