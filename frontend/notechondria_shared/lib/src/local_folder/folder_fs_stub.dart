import 'dart:async';

import 'change_channel.dart';
import 'folder_fs.dart';
import 'folder_lock.dart';
import 'handle_store.dart';
import 'local_folder_platform.dart';
import 'qualification.dart';

// Non-web stub of `folder_fs_web.dart`, selected when `dart.library.js_interop`
// is unavailable (VM tests, the native portal build). Every call reports
// "unsupported"; folder mode is hidden on native builds (main 1.3, Q11).

const bool kLocalFolderOpfsTestHook = false;

FolderFsException _unsupported(String operation) => FolderFsException(
    FolderErrorKind.unsupported,
    operation: operation,
    cause: 'local folder mode needs a web build');

class _UnsupportedPicker implements FolderPicker {
  @override
  Future<FolderFs> pickDirectory() => Future.error(_unsupported('pick'));
}

class _UnsupportedHandleStore implements FolderHandleStore {
  @override
  Future<FolderFs?> load(String folderId) async => null;

  @override
  Future<void> save(String folderId, FolderFs folder) =>
      Future.error(_unsupported('handle_store.save'));

  @override
  Future<void> delete(String folderId) async {}
}

class _UnsupportedLocks implements FolderLocks {
  @override
  Future<T> run<T>(String name, FolderLockMode mode,
          Future<T> Function() operation,
          {Duration? timeLeft}) =>
      Future.error(_unsupported('lock'));
}

class _NativePlatform implements LocalFolderPlatform {
  @override
  bool get isWeb => false;

  @override
  Uri get origin => Uri();

  @override
  final FolderPicker picker = _UnsupportedPicker();

  @override
  final FolderHandleStore handleStore = _UnsupportedHandleStore();

  @override
  final FolderLocks locks = _UnsupportedLocks();

  @override
  FolderChangeChannel openChangeChannel(Zone zone) =>
      NoopFolderChangeChannel();

  @override
  LocalFolderQualification probe() => evaluateLocalFolderSupport(
      const LocalFolderProbeInputs.unsupported());
}

LocalFolderPlatform createBrowserLocalFolderPlatform(Zone zone) =>
    _NativePlatform();

LocalFolderProbeInputs readLocalFolderProbeInputs() =>
    const LocalFolderProbeInputs.unsupported();

Future<FolderFs> openOpfsTestFolder(String name) =>
    Future.error(_unsupported('opfs_test_hook'));
