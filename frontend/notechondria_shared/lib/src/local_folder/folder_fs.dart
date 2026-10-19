import 'dart:typed_data';

/// Kind of an entry returned by [FolderFs.list].
enum FolderEntryKind { file, directory }

/// One child of a listed directory.
class FolderEntry {
  const FolderEntry(this.name, this.kind);

  final String name;
  final FolderEntryKind kind;

  bool get isFile => kind == FolderEntryKind.file;
  bool get isDirectory => kind == FolderEntryKind.directory;
}

/// Size (bytes) and `lastModified` (milliseconds since the epoch) of a file.
class FolderStat {
  const FolderStat({required this.size, required this.lastModified});

  final int size;
  final int lastModified;

  bool sameAs(int? size, int? lastModified) =>
      this.size == size && this.lastModified == lastModified;
}

/// Result of `queryPermission` / `requestPermission` (main 6.3).
enum FolderPermission { granted, prompt, denied }

/// Failure classes the folder code distinguishes. Each maps to the
/// `DOMException` name the File System Access API throws.
enum FolderErrorKind {
  notAllowed,
  notFound,
  abort,
  typeMismatch,
  noModificationAllowed,
  invalidModification,
  quotaExceeded,
  invalidPath,
  unsupported,
  other,
}

const Map<String, FolderErrorKind> _kindByDomName = {
  'NotAllowedError': FolderErrorKind.notAllowed,
  'SecurityError': FolderErrorKind.notAllowed,
  'NotFoundError': FolderErrorKind.notFound,
  'AbortError': FolderErrorKind.abort,
  'TypeMismatchError': FolderErrorKind.typeMismatch,
  'NoModificationAllowedError': FolderErrorKind.noModificationAllowed,
  'InvalidModificationError': FolderErrorKind.invalidModification,
  'QuotaExceededError': FolderErrorKind.quotaExceeded,
  'NotSupportedError': FolderErrorKind.unsupported,
};

/// Maps a `DOMException.name` to a [FolderErrorKind] (`other` if unknown).
FolderErrorKind folderErrorKindForDomName(String? name) =>
    _kindByDomName[name] ?? FolderErrorKind.other;

/// Finds a known `DOMException` name inside an error's text, for errors
/// whose `name` property could not be read.
String? findDomErrorName(String text) {
  for (final name in _kindByDomName.keys) {
    if (text.contains(name)) return name;
  }
  return null;
}

/// Every [FolderFs] failure surfaces as this exception.
class FolderFsException implements Exception {
  const FolderFsException(
    this.kind, {
    required this.operation,
    this.path = '',
    this.cause,
  });

  final FolderErrorKind kind;

  /// The [FolderFs] call that failed (`read`, `write`, `list`, ...).
  final String operation;

  /// Folder-relative path, empty for the root.
  final String path;

  /// Browser or fake message, if any.
  final String? cause;

  String get domName => switch (kind) {
        FolderErrorKind.notAllowed => 'NotAllowedError',
        FolderErrorKind.notFound => 'NotFoundError',
        FolderErrorKind.abort => 'AbortError',
        FolderErrorKind.typeMismatch => 'TypeMismatchError',
        FolderErrorKind.noModificationAllowed => 'NoModificationAllowedError',
        FolderErrorKind.invalidModification => 'InvalidModificationError',
        FolderErrorKind.quotaExceeded => 'QuotaExceededError',
        FolderErrorKind.invalidPath => 'TypeError',
        FolderErrorKind.unsupported => 'NotSupportedError',
        FolderErrorKind.other => 'Error',
      };

  @override
  String toString() {
    final where = path.isEmpty ? '' : " '$path'";
    final why = (cause == null || cause!.isEmpty) ? '' : ': $cause';
    return '$domName during $operation$where$why';
  }
}

/// A user-chosen folder (main 2.5). Paths are folder-relative, use `/`, and
/// never contain `.`, `..`, or empty segments. Writes create missing parent
/// directories. [list] never returns Chrome's `*.crswap` swap files (3.4).
abstract class FolderFs {
  /// Display name of the folder root.
  String get name;

  /// UTF-8 text of a file; throws `notFound` when it is missing.
  Future<String> readText(String path);

  Future<Uint8List> readBytes(String path);

  /// Replace-on-close write (3.4): the target changes only when it completes.
  Future<void> writeText(String path, String text);

  Future<void> writeBytes(String path, Uint8List bytes);

  /// Children of [directory] (`''` is the root); throws `notFound` when the
  /// directory is missing.
  Future<List<FolderEntry>> list(String directory);

  /// Stat of a file, or null when no file exists at [path].
  Future<FolderStat?> stat(String path);

  /// Removes a file, or a directory with [recursive]; throws `notFound`.
  Future<void> remove(String path, {bool recursive = false});

  Future<FolderPermission> queryPermission({bool write = true});

  /// Needs transient user activation in a browser (main 1.3).
  Future<FolderPermission> requestPermission({bool write = true});

  /// Whether [other] refers to the same folder on disk (3.7 copy check).
  Future<bool> isSameEntry(FolderFs other);
}

/// Whether a file name is a Chrome `createWritable` swap file (3.4, U17).
bool isSwapFileName(String name) => name.endsWith('.crswap');

/// Splits and validates a folder-relative path. `''` is the root.
List<String> splitFolderPath(String path, {String operation = 'path'}) {
  if (path.isEmpty) return const <String>[];
  if (path.startsWith('/') || path.endsWith('/') || path.contains('\\')) {
    throw FolderFsException(FolderErrorKind.invalidPath,
        operation: operation, path: path, cause: 'not a folder-relative path');
  }
  final segments = path.split('/');
  for (final segment in segments) {
    if (segment.isEmpty || segment == '.' || segment == '..') {
      throw FolderFsException(FolderErrorKind.invalidPath,
          operation: operation, path: path, cause: 'invalid segment');
    }
  }
  return segments;
}

String joinFolderPath(String directory, String name) =>
    directory.isEmpty ? name : '$directory/$name';

String folderPathParent(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i);
}

String folderPathBasename(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? path : path.substring(i + 1);
}

/// [FolderFs.list] that answers an empty list for a missing directory.
Future<List<FolderEntry>> listOrEmpty(FolderFs fs, String directory) async {
  try {
    return await fs.list(directory);
  } on FolderFsException catch (e) {
    if (e.kind == FolderErrorKind.notFound ||
        e.kind == FolderErrorKind.typeMismatch) {
      return const <FolderEntry>[];
    }
    rethrow;
  }
}

/// [FolderFs.readText] that answers null for a missing file.
Future<String?> readTextOrNull(FolderFs fs, String path) async {
  try {
    return await fs.readText(path);
  } on FolderFsException catch (e) {
    if (e.kind == FolderErrorKind.notFound ||
        e.kind == FolderErrorKind.typeMismatch) {
      return null;
    }
    rethrow;
  }
}

/// [FolderFs.remove] that ignores a path that is already gone.
Future<void> removeIfPresent(FolderFs fs, String path,
    {bool recursive = false}) async {
  try {
    await fs.remove(path, recursive: recursive);
  } on FolderFsException catch (e) {
    if (e.kind != FolderErrorKind.notFound) rethrow;
  }
}
