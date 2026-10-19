import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../local_folder/folder_fs.dart';
import '../local_folder/folder_layout.dart' show kAssetsDir;
import '../local_folder/local_folder_controller.dart';
import '../local_folder/note_codec.dart' show kFolderUrlPrefix;

// Folder-aware media (design storage_rules 3.6, design-review-3 T4).
// `nc-folder:` URLs name files under the connected folder's `assets/`;
// every other URL loads from the network as before.

/// Whether [url] is a folder URL (`nc-folder:///assets/...`).
bool isFolderUrl(String url) => url.trim().startsWith('nc-folder:');

/// Folder-relative path of an `nc-folder:` URL, or null when [url] is not a
/// folder URL, carries an invalid path, or points outside `assets/`. A query
/// or fragment (`?v=...`, used to bust the image cache) is dropped.
String? folderPathForUrl(String url) {
  var text = url.trim();
  if (!text.startsWith(kFolderUrlPrefix)) return null;
  text = text.substring(kFolderUrlPrefix.length);
  final cut = text.indexOf(RegExp(r'[?#]'));
  if (cut >= 0) text = text.substring(0, cut);
  final String path;
  try {
    path = Uri.decodeComponent(text);
    splitFolderPath(path, operation: 'read');
  } on Object {
    return null;
  }
  if (!path.startsWith('$kAssetsDir/')) return null;
  return path;
}

/// Thrown when a folder image cannot be read.
class FolderImageException implements Exception {
  const FolderImageException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads the bytes behind an `nc-folder:` URL through [folder]'s open
/// folder. Throws [FolderImageException] when no folder is open, the URL is
/// not a valid folder URL, or the read fails.
Future<Uint8List> readFolderUrlBytes(
    String url, LocalFolderController? folder) async {
  final path = folderPathForUrl(url);
  if (path == null) {
    throw FolderImageException(
        "Image not shown: Shared.LocalFolder/read — '$url' is not a "
        'folder file under assets/.');
  }
  final fs = folder?.folder;
  if (fs == null) {
    throw FolderImageException(
        "Image not shown: Shared.LocalFolder/read — '$path' needs the "
        'connected folder, and no folder is open.');
  }
  try {
    return await fs.readBytes(path);
  } on FolderFsException catch (e) {
    throw FolderImageException(
        "Image not shown: Shared.LocalFolder/read — '$path' could not be "
        'read (${e.domName}).');
  }
}

/// An [ImageProvider] for [url]: folder bytes for `nc-folder:` URLs (decoded
/// like a [MemoryImage]), a [NetworkImage] otherwise.
ImageProvider folderAwareImageProvider(String url,
    {LocalFolderController? folder}) {
  if (isFolderUrl(url)) return FolderImage(url.trim(), folder: folder);
  return NetworkImage(url);
}

/// Image provider over a file of the connected folder. The cache key holds
/// the URL (with its `?v=` query) and the folder's lock name, so two
/// folders, or a re-uploaded cover with a new query, never share an entry.
@immutable
class FolderImage extends ImageProvider<FolderImageKey> {
  const FolderImage(this.url, {this.folder, this.scale = 1.0});

  final String url;
  final LocalFolderController? folder;
  final double scale;

  @override
  Future<FolderImageKey> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<FolderImageKey>(FolderImageKey(
          url, folder?.folder == null ? '' : folder!.lockName, scale));

  @override
  ImageStreamCompleter loadImage(
          FolderImageKey key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(
        codec: _load(decode),
        scale: key.scale,
        debugLabel: url,
        informationCollector: () => <DiagnosticsNode>[
          DiagnosticsProperty<ImageProvider>('Image provider', this),
        ],
      );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await readFolderUrlBytes(url, folder);
    if (bytes.isEmpty) {
      throw FolderImageException(
          "Image not shown: Shared.LocalFolder/read — '$url' is empty.");
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is FolderImage &&
      other.url == url &&
      identical(other.folder, folder) &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(url, identityHashCode(folder), scale);

  @override
  String toString() => 'FolderImage("$url", scale: $scale)';
}

/// Image cache key of a [FolderImage].
@immutable
class FolderImageKey {
  const FolderImageKey(this.url, this.lockName, this.scale);

  final String url;
  final String lockName;
  final double scale;

  @override
  bool operator ==(Object other) =>
      other is FolderImageKey &&
      other.url == url &&
      other.lockName == lockName &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(url, lockName, scale);
}

/// An SVG for [url]: `SvgPicture.memory` over the folder bytes for
/// `nc-folder:` URLs, `SvgPicture.network` otherwise (T4). The arguments are
/// the ones the apps' `_RemoteMedia` passes. [placeholderBuilder] shows while
/// folder bytes load and when they cannot be read or decoded.
Widget folderAwareSvg(
  String url, {
  LocalFolderController? folder,
  Key? key,
  double? width,
  double? height,
  BoxFit fit = BoxFit.contain,
  AlignmentGeometry alignment = Alignment.center,
  WidgetBuilder? placeholderBuilder,
  String? semanticsLabel,
}) {
  if (!isFolderUrl(url)) {
    return SvgPicture.network(
      url,
      key: key,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      placeholderBuilder: placeholderBuilder,
      semanticsLabel: semanticsLabel,
    );
  }
  return _FolderSvg(
    key: key,
    url: url.trim(),
    folder: folder,
    width: width,
    height: height,
    fit: fit,
    alignment: alignment,
    placeholderBuilder: placeholderBuilder,
    semanticsLabel: semanticsLabel,
  );
}

class _FolderSvg extends StatefulWidget {
  const _FolderSvg({
    super.key,
    required this.url,
    required this.folder,
    required this.width,
    required this.height,
    required this.fit,
    required this.alignment,
    required this.placeholderBuilder,
    required this.semanticsLabel,
  });

  final String url;
  final LocalFolderController? folder;
  final double? width;
  final double? height;
  final BoxFit fit;
  final AlignmentGeometry alignment;
  final WidgetBuilder? placeholderBuilder;
  final String? semanticsLabel;

  @override
  State<_FolderSvg> createState() => _FolderSvgState();
}

class _FolderSvgState extends State<_FolderSvg> {
  Future<Uint8List>? _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = readFolderUrlBytes(widget.url, widget.folder);
  }

  @override
  void didUpdateWidget(_FolderSvg old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || !identical(old.folder, widget.folder)) {
      _bytes = readFolderUrlBytes(widget.url, widget.folder);
    }
  }

  Widget _placeholder(BuildContext context) =>
      widget.placeholderBuilder?.call(context) ??
      SizedBox(width: widget.width, height: widget.height);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (snapshot.hasError) {
          debugPrint('${snapshot.error}');
          return _placeholder(context);
        }
        if (bytes == null || bytes.isEmpty) return _placeholder(context);
        return SvgPicture.memory(
          bytes,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          alignment: widget.alignment,
          placeholderBuilder: widget.placeholderBuilder,
          errorBuilder: (context, error, stackTrace) => _placeholder(context),
          semanticsLabel: widget.semanticsLabel,
        );
      },
    );
  }
}
