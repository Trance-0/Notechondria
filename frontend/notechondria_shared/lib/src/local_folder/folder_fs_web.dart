import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'change_channel.dart';
import 'change_channel_web.dart';
import 'folder_fs.dart';
import 'folder_lock.dart';
import 'folder_lock_web.dart';
import 'handle_store.dart';
import 'handle_store_web.dart';
import 'js_bindings_web.dart';
import 'local_folder_platform.dart';
import 'qualification.dart';
import 'qualification_web.dart' as probe;

/// Compile-time OPFS test hook (8.3). Only the Chromium tests set it, with
/// `--dart-define=NOTECHONDRIA_TEST_OPFS_FOLDER=true`; release builds pass
/// only `APP_VERSION`, so the compiler drops every branch it guards.
const bool kLocalFolderOpfsTestHook =
    bool.fromEnvironment('NOTECHONDRIA_TEST_OPFS_FOLDER');

/// [FolderFs] over a `FileSystemDirectoryHandle` (File System Access API).
/// Picker, permission, and file promises need no zone wrapper: each is
/// awaited in Dart through `toDart` (9.2 table).
class WebFolderFs implements FolderFs {
  WebFolderFs(this.root) : _opfs = false;

  WebFolderFs._opfsRoot(this.root) : _opfs = true;

  final web.FileSystemDirectoryHandle root;
  final bool _opfs;

  @override
  String get name => root.name;

  Future<T> _guard<T>(
      String operation, String path, Future<T> Function() body) async {
    try {
      return await body();
    } catch (error) {
      throw folderErrorFromJs(error, operation: operation, path: path);
    }
  }

  Future<web.FileSystemDirectoryHandle> _directory(List<String> segments,
      {bool create = false}) async {
    var dir = root;
    for (final segment in segments) {
      dir = await dir
          .getDirectoryHandle(
              segment, web.FileSystemGetDirectoryOptions(create: create))
          .toDart;
    }
    return dir;
  }

  Future<web.FileSystemFileHandle> _file(String path, String operation,
      {bool create = false}) async {
    final segments = splitFolderPath(path, operation: operation);
    if (segments.isEmpty) {
      throw FolderFsException(FolderErrorKind.invalidPath,
          operation: operation, path: path, cause: 'the root is a directory');
    }
    final dir = await _directory(segments.sublist(0, segments.length - 1),
        create: create);
    return dir
        .getFileHandle(segments.last, web.FileSystemGetFileOptions(create: create))
        .toDart;
  }

  @override
  Future<String> readText(String path) => _guard('read', path, () async {
        final file = await (await _file(path, 'read')).getFile().toDart;
        return (await file.text().toDart).toDart;
      });

  @override
  Future<Uint8List> readBytes(String path) => _guard('read', path, () async {
        final file = await (await _file(path, 'read')).getFile().toDart;
        return (await file.arrayBuffer().toDart).toDart.asUint8List();
      });

  Future<void> _write(String path, JSAny data) =>
      _guard('write', path, () async {
        final handle = await _file(path, 'write', create: true);
        final stream = await handle
            .createWritableWith(
                WritableOptions(keepExistingData: false, mode: 'exclusive'))
            .toDart;
        try {
          await stream.write(data).toDart;
          await stream.close().toDart;
        } catch (_) {
          try {
            await stream.abort().toDart;
          } catch (_) {
            // The original error is the one to report.
          }
          rethrow;
        }
      });

  @override
  Future<void> writeText(String path, String text) => _write(path, text.toJS);

  @override
  Future<void> writeBytes(String path, Uint8List bytes) =>
      _write(path, bytes.toJS);

  @override
  Future<List<FolderEntry>> list(String directory) =>
      _guard('list', directory, () async {
        final dir = await _directory(
            splitFolderPath(directory, operation: 'list'));
        final children = await directoryChildren(dir);
        return [
          for (final child in children)
            if (!isSwapFileName(child.name))
              FolderEntry(
                  child.name,
                  child.kind == 'directory'
                      ? FolderEntryKind.directory
                      : FolderEntryKind.file),
        ]..sort((a, b) => a.name.compareTo(b.name));
      });

  @override
  Future<FolderStat?> stat(String path) => _guard('stat', path, () async {
        try {
          final file = await (await _file(path, 'stat')).getFile().toDart;
          return FolderStat(size: file.size, lastModified: file.lastModified);
        } catch (error) {
          final kind = folderErrorFromJs(error, operation: 'stat').kind;
          if (kind == FolderErrorKind.notFound ||
              kind == FolderErrorKind.typeMismatch) {
            return null;
          }
          rethrow;
        }
      });

  @override
  Future<void> remove(String path, {bool recursive = false}) =>
      _guard('remove', path, () async {
        final segments = splitFolderPath(path, operation: 'remove');
        if (segments.isEmpty) {
          throw FolderFsException(FolderErrorKind.invalidPath,
              operation: 'remove', path: path, cause: 'cannot remove the root');
        }
        final dir =
            await _directory(segments.sublist(0, segments.length - 1));
        await dir
            .removeEntry(
                segments.last, web.FileSystemRemoveOptions(recursive: recursive))
            .toDart;
      });

  FileSystemPermissionDescriptor _descriptor(bool write) =>
      FileSystemPermissionDescriptor(mode: write ? 'readwrite' : 'read');

  @override
  Future<FolderPermission> queryPermission({bool write = true}) =>
      _guard('permission', '', () async {
        if (kLocalFolderOpfsTestHook && _opfs) return FolderPermission.granted;
        final state = await root.queryPermission(_descriptor(write)).toDart;
        return folderPermissionFromJs(state.toDart);
      });

  @override
  Future<FolderPermission> requestPermission({bool write = true}) {
    if (kLocalFolderOpfsTestHook && _opfs) {
      return Future.value(FolderPermission.granted);
    }
    // Called before any await: requestPermission needs user activation.
    final pending = root.requestPermission(_descriptor(write));
    return _guard('permission', '', () async {
      final state = await pending.toDart;
      return folderPermissionFromJs(state.toDart);
    });
  }

  @override
  Future<bool> isSameEntry(FolderFs other) async {
    if (other is! WebFolderFs) return false;
    return _guard('same_entry', '', () async {
      final same = await root.isSameEntry(other.root).toDart;
      return same.toDart;
    });
  }
}

class WebFolderPicker implements FolderPicker {
  @override
  Future<FolderFs> pickDirectory() {
    final JSPromise<web.FileSystemDirectoryHandle> pending;
    try {
      pending = showDirectoryPicker();
    } catch (error) {
      return Future.error(folderErrorFromJs(error, operation: 'pick'));
    }
    return pending.toDart.then<FolderFs>(WebFolderFs.new,
        onError: (Object error) =>
            throw folderErrorFromJs(error, operation: 'pick'));
  }
}

class _BrowserPlatform implements LocalFolderPlatform {
  _BrowserPlatform(Zone zone) : handleStore = WebFolderHandleStore(zone);

  @override
  bool get isWeb => true;

  @override
  Uri get origin => Uri.base;

  @override
  final FolderPicker picker = WebFolderPicker();

  @override
  final FolderHandleStore handleStore;

  @override
  final FolderLocks locks = WebFolderLocks();

  @override
  FolderChangeChannel openChangeChannel(Zone zone) {
    try {
      return WebFolderChangeChannel(zone);
    } catch (_) {
      return NoopFolderChangeChannel();
    }
  }

  @override
  LocalFolderQualification probe() =>
      evaluateLocalFolderSupport(readLocalFolderProbeInputs());
}

LocalFolderPlatform createBrowserLocalFolderPlatform(Zone zone) =>
    _BrowserPlatform(zone);

LocalFolderProbeInputs readLocalFolderProbeInputs() =>
    probe.readLocalFolderProbeInputs();

/// The OPFS stand-in of 8.3: a per-test subdirectory of
/// `navigator.storage.getDirectory()` that reports permissions as granted.
/// Throws unless the test hook is compiled in.
Future<FolderFs> openOpfsTestFolder(String name) async {
  if (!kLocalFolderOpfsTestHook) {
    throw const FolderFsException(FolderErrorKind.unsupported,
        operation: 'opfs_test_hook',
        cause: 'built without NOTECHONDRIA_TEST_OPFS_FOLDER');
  }
  final storageRoot = await web.window.navigator.storage.getDirectory().toDart;
  final dir = await storageRoot
      .getDirectoryHandle('notechondria-opfs-test-hook-$name',
          web.FileSystemGetDirectoryOptions(create: true))
      .toDart;
  return WebFolderFs._opfsRoot(dir);
}
