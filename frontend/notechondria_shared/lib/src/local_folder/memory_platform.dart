import 'dart:async';
import 'dart:collection';

import 'change_channel.dart';
import 'folder_fs.dart';
import 'folder_fs_memory.dart';
import 'folder_lock.dart';
import 'handle_store.dart';
import 'local_folder_platform.dart';
import 'qualification.dart';

// Test doubles for `LocalFolderController.forTest` (8.2). Exported only by
// `package:notechondria_shared/local_folder_testing.dart`.

class MemoryHandleStore implements FolderHandleStore {
  final Map<String, FolderFs> records = <String, FolderFs>{};

  @override
  Future<FolderFs?> load(String folderId) async => records[folderId];

  @override
  Future<void> save(String folderId, FolderFs folder) async {
    records[folderId] = folder;
  }

  @override
  Future<void> delete(String folderId) async {
    records.remove(folderId);
  }
}

/// Stands in for "Choose '<name>' again": returns queued folders in order,
/// or throws `AbortError` when the queue is empty or holds null.
class MemoryFolderPicker implements FolderPicker {
  final Queue<FolderFs?> results = Queue<FolderFs?>();
  int calls = 0;

  void willReturn(FolderFs? folder) => results.add(folder);

  @override
  Future<FolderFs> pickDirectory() async {
    calls++;
    final next = results.isEmpty ? null : results.removeFirst();
    if (next == null) {
      throw const FolderFsException(FolderErrorKind.abort,
          operation: 'pick', cause: 'the picker was closed');
    }
    return next;
  }
}

/// Connects [MemoryFolderChangeChannel]s like one origin's tabs: a post
/// reaches every other open channel, never the sender. [delay] postpones
/// delivery; [dropAll] loses messages (6.2 tests).
class MemoryFolderChangeHub {
  final List<MemoryFolderChangeChannel> _channels = [];
  final List<Map<String, Object?>> posted = [];
  Duration delay = Duration.zero;
  bool dropAll = false;

  MemoryFolderChangeChannel open() {
    final channel = MemoryFolderChangeChannel._(this);
    _channels.add(channel);
    return channel;
  }

  void _post(MemoryFolderChangeChannel from, Map<String, Object?> message) {
    posted.add(message);
    if (dropAll) return;
    for (final to in [..._channels]) {
      if (identical(to, from)) continue;
      if (delay == Duration.zero) {
        scheduleMicrotask(() => to._deliver(message));
      } else {
        Timer(delay, () => to._deliver(message));
      }
    }
  }
}

class MemoryFolderChangeChannel implements FolderChangeChannel {
  MemoryFolderChangeChannel._(this._hub);

  final MemoryFolderChangeHub _hub;
  final StreamController<Map<String, Object?>> _messages =
      StreamController<Map<String, Object?>>.broadcast(sync: true);

  void _deliver(Map<String, Object?> message) {
    if (!_messages.isClosed) _messages.add(Map.of(message));
  }

  @override
  void post(Map<String, Object?> message) => _hub._post(this, message);

  @override
  Stream<Map<String, Object?>> get messages => _messages.stream;

  @override
  void close() {
    _hub._channels.remove(this);
    _messages.close();
  }
}

/// The `LocalFolderPlatform` of VM tests. Several platforms can share one
/// [locks] and one [hub] to act as tabs of one origin.
class MemoryFolderPlatform implements LocalFolderPlatform {
  MemoryFolderPlatform({
    this.isWeb = true,
    Uri? origin,
    MemoryFolderPicker? picker,
    MemoryHandleStore? handleStore,
    MemoryFolderLocks? locks,
    MemoryFolderChangeHub? hub,
    LocalFolderProbeInputs? probeInputs,
  })  : origin = origin ?? Uri.parse('https://trance-0.github.io'),
        picker = picker ?? MemoryFolderPicker(),
        handleStore = handleStore ?? MemoryHandleStore(),
        locks = locks ?? MemoryFolderLocks(),
        hub = hub ?? MemoryFolderChangeHub(),
        probeInputs = probeInputs ??
            const LocalFolderProbeInputs(
              hasDirectoryPicker: true,
              isSecureContext: true,
              hasPermissionApi: true,
              hasDirectoryIteration: true,
              hasWebLocks: true,
              userAgent: 'Mozilla/5.0 (X11; Linux x86_64) Chrome/130.0',
              uaDataMobile: false,
              brands: [('Google Chrome', '130')],
            );

  @override
  final bool isWeb;
  @override
  final Uri origin;
  @override
  final MemoryFolderPicker picker;
  @override
  final MemoryHandleStore handleStore;
  @override
  final MemoryFolderLocks locks;
  final MemoryFolderChangeHub hub;
  final LocalFolderProbeInputs probeInputs;

  /// A second tab of the same origin: shared locks, handle store, and hub.
  MemoryFolderPlatform anotherTab() => MemoryFolderPlatform(
      isWeb: isWeb,
      origin: origin,
      handleStore: handleStore,
      locks: locks,
      hub: hub,
      probeInputs: probeInputs);

  @override
  FolderChangeChannel openChangeChannel(Zone zone) => hub.open();

  @override
  LocalFolderQualification probe() => evaluateLocalFolderSupport(probeInputs);

  /// A fresh in-memory folder.
  static MemoryFolderFs newFolder([String name = 'Notes']) =>
      MemoryFolderFs(name: name);
}
