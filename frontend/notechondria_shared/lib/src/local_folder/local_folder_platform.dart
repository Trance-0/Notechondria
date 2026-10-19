import 'dart:async';

import 'change_channel.dart';
import 'folder_fs.dart';
import 'folder_fs_stub.dart' if (dart.library.js_interop) 'folder_fs_web.dart'
    as impl;
import 'folder_lock.dart';
import 'handle_store.dart';
import 'qualification.dart';

/// Opens the directory picker. [pickDirectory] must call the browser picker
/// before its first `await` (main 1.3); a closed picker throws a
/// [FolderFsException] of kind `abort`.
abstract class FolderPicker {
  Future<FolderFs> pickDirectory();
}

/// Everything the controller needs from the browser, so VM tests can pass
/// `MemoryFolderPlatform` (8.2) and the web check comes from the platform
/// (design review 3 T7(b)).
abstract class LocalFolderPlatform {
  /// The "build is web" input of `decideStorageMode` (2.8).
  bool get isWeb;

  /// The page origin, for the T3 remember default and the 6.1 notice.
  Uri get origin;

  FolderPicker get picker;
  FolderHandleStore get handleStore;
  FolderLocks get locks;

  /// Opens the change channel; void listeners are bound to [zone] (2.5).
  FolderChangeChannel openChangeChannel(Zone zone);

  LocalFolderQualification probe();
}

/// The browser platform on web builds; on native builds a platform whose
/// [LocalFolderPlatform.isWeb] is false and whose calls report unsupported.
LocalFolderPlatform browserLocalFolderPlatform({Zone? zone}) =>
    impl.createBrowserLocalFolderPlatform(zone ?? Zone.current);

/// Capability probe (main 1.2); on native builds every API is reported
/// missing, and the option is hidden there anyway (1.3).
LocalFolderQualification probeLocalFolderSupport() =>
    evaluateLocalFolderSupport(impl.readLocalFolderProbeInputs());
