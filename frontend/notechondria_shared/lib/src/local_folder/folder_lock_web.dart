import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'folder_lock.dart';
import 'js_bindings_web.dart';

/// [FolderLocks] over `navigator.locks` (6.2). The grant callback is bound
/// with the non-guarded `Zone.current.bindUnaryCallback<JSPromise<JSAny?>,
/// Lock?>` (through [bindLockCallback]) in the zone of the request that asked
/// for the lock. Its body runs the operation inside a try/catch, completes
/// the caller's completer with the result or the error, and returns that
/// block's `Future<void>` as a promise, so the promise always resolves and
/// the browser releases the lock exactly when the operation ends (main 2.5).
class WebFolderLocks implements FolderLocks {
  WebFolderLocks({this.maxWait = kFolderLockWait, this.onHold});

  /// Shortened only by the Chromium tests (8.3).
  final Duration maxWait;
  final FolderLockHoldObserver? onHold;

  @override
  Future<T> run<T>(
    String name,
    FolderLockMode mode,
    Future<T> Function() operation, {
    Duration? timeLeft,
  }) {
    final bound = folderLockWait(timeLeft, maxWait);
    if (timeLeft != null && timeLeft <= Duration.zero) {
      return Future<T>.error(FolderLockTimeout(
          name: name, mode: mode, waited: Duration.zero, cutByDeadline: true));
    }
    final result = Completer<T>();
    var granted = false;
    final callback = bindLockCallback((web.Lock? lock) {
      granted = true;
      final started = DateTime.now();
      return () async {
        try {
          result.complete(await operation());
        } catch (error, stack) {
          result.completeError(error, stack);
        } finally {
          onHold?.call(name, mode, DateTime.now().difference(started));
        }
      }()
          .toJS;
    });
    final JSPromise<JSAny?> released;
    try {
      released = web.window.navigator.locks.request(
        name,
        web.LockOptions(
          mode: mode == FolderLockMode.exclusive ? 'exclusive' : 'shared',
          signal: web.AbortSignal.timeout(bound.wait.inMilliseconds),
        ),
        callback.toJS,
      );
    } catch (error) {
      return Future<T>.error(StateError(
          'Folder lock not requested: Shared.LocalFolder/lock — '
          'navigator.locks.request threw ($error).'));
    }
    // The request promise settles after the callback's promise does. It
    // rejects before a grant when the abort signal fires (TimeoutError).
    released.toDart.then<void>((_) {}, onError: (Object error) {
      if (result.isCompleted) return;
      if (!granted) {
        final text = '$error';
        result.completeError(
            text.contains('TimeoutError') || text.contains('AbortError')
                ? FolderLockTimeout(
                    name: name,
                    mode: mode,
                    waited: bound.wait,
                    cutByDeadline: bound.cutByDeadline)
                : StateError('Folder lock not granted: Shared.LocalFolder/lock '
                    '— navigator.locks.request rejected ($text).'));
      }
    });
    return result.future;
  }
}
