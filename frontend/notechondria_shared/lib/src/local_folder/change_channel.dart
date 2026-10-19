import 'dart:async';

// Cross-tab messages (security and tabs 6.2 "Change channel"). Phase 1
// carries the connect, disconnect, and switch messages of 2.9 and 2.10;
// change messages arrive in Phase 4. No message ever carries a handle.

/// `BroadcastChannel` name shared by every app tab of the origin.
const String kFolderChangeChannelName = 'notechondria.local_folder.changes';

/// `op` values of Phase 1 messages.
const String kChangeOpConnect = 'connect';
const String kChangeOpDisconnect = 'disconnect';
const String kChangeOpSwitch = 'switch';

/// A message is a JSON-compatible map with at least `op`, plus `folder_id`
/// and `folder_name` for connect and switch.
abstract class FolderChangeChannel {
  void post(Map<String, Object?> message);

  /// Messages from other tabs (never this tab's own posts).
  Stream<Map<String, Object?>> get messages;

  void close();
}

/// Used where no channel exists (native builds).
class NoopFolderChangeChannel implements FolderChangeChannel {
  @override
  void post(Map<String, Object?> message) {}

  @override
  Stream<Map<String, Object?>> get messages =>
      const Stream<Map<String, Object?>>.empty();

  @override
  void close() {}
}
