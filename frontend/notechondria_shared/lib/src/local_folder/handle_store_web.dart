import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'folder_fs.dart';
import 'folder_fs_web.dart';
import 'handle_store.dart';
import 'js_bindings_web.dart';

/// Remembered handles in IndexedDB `notechondria_local_folder`, object store
/// `handles`, keyed by `folder_id`; the value is the
/// `FileSystemDirectoryHandle` itself (structured-cloneable in Chrome). It
/// uses `package:web` rather than `idb_shim`, since storing a raw JS handle
/// through `idb_shim` is unverified (U2).
///
/// T5: every IndexedDB event handler is a void listener, bound with the
/// captured zone's guarded wrapper ([bindListener]). The bodies only
/// complete a [Completer], except `onupgradeneeded`, which must create the
/// object store synchronously because the upgrade transaction is active
/// only while that event is dispatched.
class WebFolderHandleStore implements FolderHandleStore {
  WebFolderHandleStore(this._zone);

  final Zone _zone;
  Future<web.IDBDatabase>? _db;

  Future<web.IDBDatabase> _open() => _db ??= () {
        final done = Completer<web.IDBDatabase>();
        final request = web.window.indexedDB.open(kHandleDatabaseName, 1);
        request.onupgradeneeded = bindListener<web.Event>(_zone, (_) {
          final db = request.result as web.IDBDatabase;
          if (!db.objectStoreNames.contains(kHandleStoreName)) {
            db.createObjectStore(kHandleStoreName);
          }
        }).toJS;
        request.onsuccess = bindListener<web.Event>(_zone, (_) {
          if (!done.isCompleted) {
            done.complete(request.result as web.IDBDatabase);
          }
        }).toJS;
        request.onerror = bindListener<web.Event>(_zone, (_) {
          if (!done.isCompleted) {
            _db = null;
            done.completeError(_error('open', '${request.error?.name}'));
          }
        }).toJS;
        return done.future;
      }();

  FolderFsException _error(String operation, String cause) => FolderFsException(
      folderErrorKindForDomName(cause),
      operation: 'handle_store.$operation',
      cause: cause);

  Future<JSAny?> _request(String mode, String operation,
      web.IDBRequest Function(web.IDBObjectStore store) start) async {
    final db = await _open();
    final tx = db.transaction(kHandleStoreName.toJS, mode);
    final request = start(tx.objectStore(kHandleStoreName));
    final done = Completer<JSAny?>();
    JSAny? value;
    request.onsuccess = bindListener<web.Event>(_zone, (_) {
      value = request.result;
    }).toJS;
    tx.oncomplete = bindListener<web.Event>(_zone, (_) {
      if (!done.isCompleted) done.complete(value);
    }).toJS;
    tx.onerror = bindListener<web.Event>(_zone, (_) {
      if (!done.isCompleted) {
        done.completeError(_error(operation, '${tx.error?.name}'));
      }
    }).toJS;
    tx.onabort = bindListener<web.Event>(_zone, (_) {
      if (!done.isCompleted) {
        done.completeError(
            _error(operation, tx.error?.name ?? 'AbortError'));
      }
    }).toJS;
    return done.future;
  }

  @override
  Future<FolderFs?> load(String folderId) async {
    final value = await _request(
        'readonly', 'load', (store) => store.get(folderId.toJS));
    if (value == null || !value.isA<JSObject>()) return null;
    return WebFolderFs(value as web.FileSystemDirectoryHandle);
  }

  @override
  Future<void> save(String folderId, FolderFs folder) async {
    if (folder is! WebFolderFs) {
      throw const FolderFsException(FolderErrorKind.unsupported,
          operation: 'handle_store.save', cause: 'not a browser folder');
    }
    await _request('readwrite', 'save',
        (store) => store.put(folder.root, folderId.toJS));
  }

  @override
  Future<void> delete(String folderId) async {
    await _request(
        'readwrite', 'delete', (store) => store.delete(folderId.toJS));
  }
}
