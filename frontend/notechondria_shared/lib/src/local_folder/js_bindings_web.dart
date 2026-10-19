import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'folder_fs.dart';

// Hand-written bindings for what `package:web` 1.1.1 lacks (main 1.4, 9.2),
// and the two zone helpers of main 2.5. Web builds only.

// --- showDirectoryPicker ---

extension type DirectoryPickerOptions._(JSObject _) implements JSObject {
  external factory DirectoryPickerOptions({String id, String mode});
}

@JS('showDirectoryPicker')
external JSPromise<web.FileSystemDirectoryHandle> _showDirectoryPicker(
    DirectoryPickerOptions options);

/// Every directory picker in the app passes this `id` (main 1.3).
const String kFolderPickerId = 'notechondria-folder';

bool get hasShowDirectoryPicker => globalContext.has('showDirectoryPicker');

/// `showDirectoryPicker({id, mode: 'readwrite'})`. Call it before any
/// `await` in a click handler: the picker needs transient activation.
JSPromise<web.FileSystemDirectoryHandle> showDirectoryPicker() =>
    _showDirectoryPicker(
        DirectoryPickerOptions(id: kFolderPickerId, mode: 'readwrite'));

// --- queryPermission / requestPermission ---

extension type FileSystemPermissionDescriptor._(JSObject _)
    implements JSObject {
  external factory FileSystemPermissionDescriptor({String mode});
}

extension FileSystemHandlePermissions on web.FileSystemHandle {
  external JSPromise<JSString> queryPermission(
      FileSystemPermissionDescriptor descriptor);

  external JSPromise<JSString> requestPermission(
      FileSystemPermissionDescriptor descriptor);
}

FolderPermission folderPermissionFromJs(String state) => switch (state) {
      'granted' => FolderPermission.granted,
      'denied' => FolderPermission.denied,
      _ => FolderPermission.prompt,
    };

// --- async directory iteration (values()) ---

extension type _IteratorResult._(JSObject _) implements JSObject {
  external JSBoolean? get done;
  external JSAny? get value;
}

extension type _AsyncIterator._(JSObject _) implements JSObject {
  external JSPromise<_IteratorResult> next();
}

extension _DirectoryValues on web.FileSystemDirectoryHandle {
  @JS('values')
  external _AsyncIterator _values();
}

/// Every child handle of [directory], through its async `values()` iterator.
Future<List<web.FileSystemHandle>> directoryChildren(
    web.FileSystemDirectoryHandle directory) async {
  final iterator = directory._values();
  final out = <web.FileSystemHandle>[];
  while (true) {
    final result = await iterator.next().toDart;
    if (result.done?.toDart ?? false) break;
    out.add(result.value as web.FileSystemHandle);
  }
  return out;
}

// --- createWritable({mode}) ---

extension type WritableOptions._(JSObject _) implements JSObject {
  external factory WritableOptions({bool keepExistingData, String mode});
}

extension FileSystemFileHandleWritable on web.FileSystemFileHandle {
  /// `createWritable({keepExistingData: false, mode: 'exclusive'})`; the
  /// `mode` member is ignored before Chrome 121 (3.4).
  @JS('createWritable')
  external JSPromise<web.FileSystemWritableFileStream> createWritableWith(
      WritableOptions options);
}

// --- navigator.userAgentData ---

extension type NavigatorUABrandVersion._(JSObject _) implements JSObject {
  external String get brand;
  external String get version;
}

extension type NavigatorUAData._(JSObject _) implements JSObject {
  external JSArray<NavigatorUABrandVersion> get brands;
  external bool get mobile;
}

extension NavigatorUserAgentData on web.Navigator {
  external NavigatorUAData? get userAgentData;
}

// --- FileSystemObserver (desktop Chrome 133+, Phase 4) ---

bool get hasFileSystemObserver => globalContext.has('FileSystemObserver');

extension type FileSystemObserver._(JSObject _) implements JSObject {
  external factory FileSystemObserver(JSFunction callback);
  external JSPromise<JSAny?> observe(
      web.FileSystemHandle handle, JSObject options);
  external void disconnect();
}

// --- feature checks for the qualification probe (main 1.2) ---

/// Whether `globalThis[constructor].prototype` has [member].
bool prototypeHas(String constructor, String member) {
  final ctor = globalContext.getProperty<JSAny?>(constructor.toJS);
  if (ctor == null || !ctor.isA<JSObject>()) return false;
  final proto = (ctor as JSObject).getProperty<JSAny?>('prototype'.toJS);
  if (proto == null || !proto.isA<JSObject>()) return false;
  return (proto as JSObject).has(member);
}

/// Whether `navigator.locks` exists.
bool get hasWebLocks => (web.window.navigator as JSObject).has('locks');

// --- Zone helpers (main 2.5, table in 9.2) ---

/// Void listeners (`BroadcastChannel`, `FileSystemObserver`, `focus`,
/// IndexedDB `onsuccess`/`onerror`/`onupgradeneeded`/`oncomplete`): the
/// captured zone's guarded wrapper, so an exception reaches `runGuardedApp`
/// and a later refresh never runs inside a startup budget.
void Function(T) bindListener<T extends JSAny?>(
        Zone zone, void Function(T) listener) =>
    zone.bindUnaryCallbackGuarded<T>(listener);

/// The `navigator.locks.request` grant callback: the NON-guarded wrapper in
/// the requesting zone, because the browser holds the lock until the
/// returned promise settles. A guarded (`void`) wrapper would hand
/// JavaScript `undefined` and release the lock in an upcoming microtask.
JSPromise<JSAny?> Function(web.Lock?) bindLockCallback(
        JSPromise<JSAny?> Function(web.Lock?) callback) =>
    Zone.current.bindUnaryCallback<JSPromise<JSAny?>, web.Lock?>(callback);

/// The `DOMException` name inside a JS error, if one can be found.
String? jsErrorName(Object error) => findDomErrorName('$error');

/// Wraps a JS error from a folder call as a [FolderFsException].
FolderFsException folderErrorFromJs(Object error,
    {required String operation, String path = ''}) {
  if (error is FolderFsException) return error;
  return FolderFsException(folderErrorKindForDomName(jsErrorName(error)),
      operation: operation, path: path, cause: '$error');
}
