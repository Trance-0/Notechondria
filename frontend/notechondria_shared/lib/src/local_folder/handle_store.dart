import 'folder_fs.dart';

// Remembered folder handles (security and tabs 6.1, 6.2) and the T3
// "Remember this folder" default per origin.

/// IndexedDB database and object store of the web handle store (6.2).
const String kHandleDatabaseName = 'notechondria_local_folder';
const String kHandleStoreName = 'handles';

/// Stores folder handles keyed by `folder_id`. Used only while the shared
/// key's `remember` flag is on (T3); session-only mode keeps the handle in
/// page memory.
abstract class FolderHandleStore {
  /// The remembered handle, or null when there is no record.
  Future<FolderFs?> load(String folderId);

  Future<void> save(String folderId, FolderFs folder);

  /// Deletes the record; a missing record is not an error.
  Future<void> delete(String folderId);
}

/// Where an app is served from, for the 6.1 mitigations.
enum LocalFolderOriginKind {
  /// `*.github.io`, shared with other Trance-0 Pages projects.
  sharedPages,

  /// `127.0.0.1`, `localhost`, `[::1]`: the loopback preview serves backend
  /// `/media/` uploads on the app origin.
  loopback,

  /// Any other host, for example a Docker self-host, which also serves
  /// `/media/` next to the apps.
  other,
}

LocalFolderOriginKind classifyLocalFolderOrigin(Uri origin) {
  final host = origin.host.toLowerCase();
  if (host == 'github.io' || host.endsWith('.github.io')) {
    return LocalFolderOriginKind.sharedPages;
  }
  if (host == '127.0.0.1' ||
      host == 'localhost' ||
      host == '::1' ||
      host == '[::1]') {
    return LocalFolderOriginKind.loopback;
  }
  return LocalFolderOriginKind.other;
}

/// Origins (`scheme://host:port`) known to serve no same-origin uploads and
/// host no other project, where "Remember this folder" may default to on.
/// None exists today: a dedicated origin is Q4, and media hardening is Q19.
const Set<String> kRememberDefaultOnOrigins = <String>{};

String _originKey(Uri origin) =>
    '${origin.scheme}://${origin.host}${origin.hasPort ? ':${origin.port}' : ''}';

/// T3: the default of the "Remember this folder" checkbox. It is off
/// wherever the 6.1 residual risk applies: `*.github.io`, the loopback
/// preview, and any self-host, and an origin cannot show that it serves no
/// uploads, so it is off unless listed in [kRememberDefaultOnOrigins].
bool rememberDefaultForOrigin(Uri origin) =>
    kRememberDefaultOnOrigins.contains(_originKey(origin));

/// Whether the one-time shared-origin notice (6.1 mitigation 2) applies.
bool needsSharedOriginNotice(Uri origin) =>
    classifyLocalFolderOrigin(origin) == LocalFolderOriginKind.sharedPages;
