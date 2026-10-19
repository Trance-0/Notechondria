import 'dart:convert';
import 'dart:typed_data';

import 'folder_fs.dart';

/// Thrown by a [MemoryFolderFs] crash point: the tab "died" before the
/// mutation, which did not happen (8.2 "throw after the n-th write").
class MemoryFolderCrash implements Exception {
  const MemoryFolderCrash(this.operation, this.path);
  final String operation;
  final String path;
  @override
  String toString() => 'Simulated crash before $operation $path';
}

class _MemoryFile {
  _MemoryFile(this.bytes, this.lastModified);
  Uint8List bytes;
  int lastModified;
}

class _Failure {
  _Failure(this.kind, this.operation, this.pathPrefix, this.count);
  final FolderErrorKind kind;
  final String? operation;
  final String? pathPrefix;
  int count;
}

class _MemoryStore {
  _MemoryStore(this.clock);
  final Map<String, _MemoryFile> files = <String, _MemoryFile>{};
  final Set<String> dirs = <String>{''};
  int clock;
  FolderPermission permission = FolderPermission.granted;
  FolderPermission requestAnswer = FolderPermission.granted;
  final List<_Failure> failures = <_Failure>[];
  int? mutationsBeforeCrash;
  int mutations = 0;
  bool rootGone = false;

  int tick() => ++clock;
}

/// In-memory [FolderFs] for VM tests (8.2): injectable failures
/// ([failNext]), permission loss ([revoke], [grant], [deny]), crash points
/// ([crashAfterWrites]), and external edits with a new `lastModified`
/// ([externalEdit]). [view] is a second handle on the same folder;
/// [copy] is a file-manager copy (a different entry with the same files).
class MemoryFolderFs implements FolderFs {
  MemoryFolderFs({this.name = 'Notes', int startTime = 1700000000000})
      : _store = _MemoryStore(startTime);

  MemoryFolderFs._(this.name, this._store);

  @override
  final String name;
  final _MemoryStore _store;

  MemoryFolderFs view() => MemoryFolderFs._(name, _store);

  MemoryFolderFs copy({String? name}) {
    final store = _MemoryStore(_store.clock);
    _store.files.forEach((path, file) {
      store.files[path] =
          _MemoryFile(Uint8List.fromList(file.bytes), file.lastModified);
    });
    store.dirs.addAll(_store.dirs);
    return MemoryFolderFs._(name ?? this.name, store);
  }

  // --- test controls ---

  /// Permission becomes `prompt`; every call throws `NotAllowedError`.
  void revoke() => _store.permission = FolderPermission.prompt;

  void grant() => _store.permission = FolderPermission.granted;

  void deny() => _store.permission = FolderPermission.denied;

  /// The folder was moved, renamed, or deleted: every call on it throws
  /// `NotFoundError` with an empty path (6.3).
  void removeRoot() => _store.rootGone = true;

  /// What [requestPermission] answers while access is not granted.
  set requestAnswer(FolderPermission value) => _store.requestAnswer = value;

  /// The next [count] calls of [operation] (`read`, `write`, `list`, `stat`,
  /// `remove`; any when null) on paths starting with [pathPrefix] throw
  /// [kind]. A failed write leaves the old file (abort mid-write).
  void failNext(FolderErrorKind kind,
      {String? operation, String? pathPrefix, int count = 1}) {
    _store.failures.add(_Failure(kind, operation, pathPrefix, count));
  }

  /// Allows [n] more mutations (writes and removals); the next one throws
  /// [MemoryFolderCrash] without changing anything. Fires once.
  void crashAfterWrites(int n) => _store.mutationsBeforeCrash = n;

  void cancelCrash() => _store.mutationsBeforeCrash = null;

  /// Mutations made through any handle so far.
  int get mutationCount => _store.mutations;

  /// Writes [text] as another editor would: new `lastModified`, no crash
  /// point or failure applies.
  void externalEdit(String path, String text) {
    _ensureParents(splitFolderPath(path));
    _store.files[path] =
        _MemoryFile(Uint8List.fromList(utf8.encode(text)), _store.tick());
  }

  void externalRemove(String path) {
    _store.files.remove(path);
    _store.files.removeWhere((p, _) => p.startsWith('$path/'));
    _store.dirs.removeWhere((d) => d == path || d.startsWith('$path/'));
  }

  bool exists(String path) => _store.files.containsKey(path);

  String? textOf(String path) {
    final file = _store.files[path];
    return file == null ? null : utf8.decode(file.bytes);
  }

  /// Every file path, sorted.
  List<String> get paths => _store.files.keys.toList()..sort();

  // --- FolderFs ---

  void _check(String operation, String path) {
    if (_store.rootGone) {
      throw FolderFsException(FolderErrorKind.notFound,
          operation: operation, cause: 'the folder is gone');
    }
    if (_store.permission != FolderPermission.granted) {
      throw FolderFsException(FolderErrorKind.notAllowed,
          operation: operation, path: path, cause: 'access revoked');
    }
    final match = _store.failures.where((f) =>
        f.count > 0 &&
        (f.operation == null || f.operation == operation) &&
        (f.pathPrefix == null || path.startsWith(f.pathPrefix!)));
    if (match.isEmpty) return;
    final failure = match.first;
    failure.count--;
    if (failure.count <= 0) _store.failures.remove(failure);
    throw FolderFsException(failure.kind,
        operation: operation, path: path, cause: 'injected');
  }

  void _mutation(String operation, String path) {
    final left = _store.mutationsBeforeCrash;
    if (left != null) {
      if (left <= 0) {
        _store.mutationsBeforeCrash = null;
        throw MemoryFolderCrash(operation, path);
      }
      _store.mutationsBeforeCrash = left - 1;
    }
    _store.mutations++;
  }

  void _ensureParents(List<String> segments) {
    var dir = '';
    for (var i = 0; i < segments.length - 1; i++) {
      dir = joinFolderPath(dir, segments[i]);
      if (_store.files.containsKey(dir)) {
        throw FolderFsException(FolderErrorKind.typeMismatch,
            operation: 'write', path: dir, cause: 'a file is in the way');
      }
      _store.dirs.add(dir);
    }
  }

  _MemoryFile _fileAt(String operation, String path) {
    splitFolderPath(path, operation: operation);
    final file = _store.files[path];
    if (file != null) return file;
    throw FolderFsException(
        _store.dirs.contains(path)
            ? FolderErrorKind.typeMismatch
            : FolderErrorKind.notFound,
        operation: operation,
        path: path);
  }

  @override
  Future<String> readText(String path) async {
    _check('read', path);
    return utf8.decode(_fileAt('read', path).bytes);
  }

  @override
  Future<Uint8List> readBytes(String path) async {
    _check('read', path);
    return Uint8List.fromList(_fileAt('read', path).bytes);
  }

  Future<void> _write(String path, Uint8List bytes) async {
    final segments = splitFolderPath(path, operation: 'write');
    _check('write', path);
    if (_store.dirs.contains(path)) {
      throw FolderFsException(FolderErrorKind.typeMismatch,
          operation: 'write', path: path);
    }
    _mutation('write', path);
    _ensureParents(segments);
    _store.files[path] = _MemoryFile(bytes, _store.tick());
  }

  @override
  Future<void> writeText(String path, String text) =>
      _write(path, Uint8List.fromList(utf8.encode(text)));

  @override
  Future<void> writeBytes(String path, Uint8List bytes) =>
      _write(path, Uint8List.fromList(bytes));

  @override
  Future<List<FolderEntry>> list(String directory) async {
    splitFolderPath(directory, operation: 'list');
    _check('list', directory);
    if (!_store.dirs.contains(directory)) {
      throw FolderFsException(
          _store.files.containsKey(directory)
              ? FolderErrorKind.typeMismatch
              : FolderErrorKind.notFound,
          operation: 'list',
          path: directory);
    }
    final prefix = directory.isEmpty ? '' : '$directory/';
    final out = <String, FolderEntryKind>{};
    for (final path in _store.files.keys) {
      if (!path.startsWith(prefix)) continue;
      final rest = path.substring(prefix.length);
      if (!rest.contains('/')) out[rest] = FolderEntryKind.file;
    }
    for (final dir in _store.dirs) {
      if (dir.isEmpty || !dir.startsWith(prefix)) continue;
      final rest = dir.substring(prefix.length);
      if (rest.isNotEmpty && !rest.contains('/')) {
        out[rest] = FolderEntryKind.directory;
      }
    }
    final names = out.keys.where((n) => !isSwapFileName(n)).toList()..sort();
    return [for (final n in names) FolderEntry(n, out[n]!)];
  }

  @override
  Future<FolderStat?> stat(String path) async {
    splitFolderPath(path, operation: 'stat');
    _check('stat', path);
    final file = _store.files[path];
    return file == null
        ? null
        : FolderStat(size: file.bytes.length, lastModified: file.lastModified);
  }

  @override
  Future<void> remove(String path, {bool recursive = false}) async {
    final segments = splitFolderPath(path, operation: 'remove');
    if (segments.isEmpty) {
      throw const FolderFsException(FolderErrorKind.invalidPath,
          operation: 'remove', cause: 'cannot remove the root');
    }
    _check('remove', path);
    final isFile = _store.files.containsKey(path);
    final isDir = _store.dirs.contains(path);
    if (!isFile && !isDir) {
      throw FolderFsException(FolderErrorKind.notFound,
          operation: 'remove', path: path);
    }
    if (isDir && !recursive) {
      final hasChildren = _store.files.keys.any((p) => p.startsWith('$path/')) ||
          _store.dirs.any((d) => d.startsWith('$path/'));
      if (hasChildren) {
        throw FolderFsException(FolderErrorKind.invalidModification,
            operation: 'remove', path: path, cause: 'directory not empty');
      }
    }
    _mutation('remove', path);
    if (isFile) {
      _store.files.remove(path);
    } else {
      externalRemove(path);
    }
  }

  @override
  Future<FolderPermission> queryPermission({bool write = true}) async =>
      _store.permission;

  @override
  Future<FolderPermission> requestPermission({bool write = true}) async {
    if (_store.permission != FolderPermission.granted) {
      _store.permission = _store.requestAnswer;
    }
    return _store.permission;
  }

  @override
  Future<bool> isSameEntry(FolderFs other) async =>
      other is MemoryFolderFs && identical(other._store, _store);
}
