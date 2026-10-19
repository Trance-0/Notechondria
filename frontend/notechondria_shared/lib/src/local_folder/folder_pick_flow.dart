import 'folder_fs.dart';
import 'folder_layout.dart';
import 'folder_messages.dart';

// "Choose '<name>' again" (2.9) and the copy check (3.7). The picker is
// always the first browser call of its click handler; only after it returns
// does the app read the picked folder's manifest.json.

sealed class PickOutcome {
  const PickOutcome();
}

/// The picker closed without a folder (AbortError); the view stays.
class PickCancelled extends PickOutcome {
  const PickCancelled();
  String get message => LocalFolderMessages.pickCancelled;
}

class PickFailed extends PickOutcome {
  const PickFailed(this.message);
  final String message;
}

/// The picked folder is the connected one; it is open (or opening).
class PickOpened extends PickOutcome {
  const PickOpened();
}

/// Refused, nothing written: no manifest.json, a newer layout, or another
/// folder_id ([canSwitch], with "Switch to this folder").
class PickRefused extends PickOutcome {
  const PickRefused(this.message, {this.canSwitch = false});
  final String message;
  final bool canSwitch;
}

/// Same folder_id as a remembered folder that is still readable: "Give it
/// its own identity?" (3.7).
class PickLooksLikeCopy extends PickOutcome {
  const PickLooksLikeCopy(this.message);
  final String message;
}

/// Same folder_id as a remembered folder that needs a grant to check, with
/// "Check '<other>'", "Give it its own identity", and "It is the same
/// folder, moved".
class PickMayBeCopy extends PickOutcome {
  const PickMayBeCopy(this.message);
  final String message;
}

/// The message an outcome shows, or null for one that needs none.
String? pickOutcomeMessage(PickOutcome outcome) => switch (outcome) {
      PickOpened() || PickCancelled() => null,
      PickFailed(:final message) ||
      PickRefused(:final message) ||
      PickLooksLikeCopy(:final message) ||
      PickMayBeCopy(:final message) =>
        message,
    };

/// A folder picked for a first connect (1.3 step 3).
class ConnectPick {
  const ConnectPick({
    required this.folder,
    required this.manifest,
    required this.entryCount,
    this.refusal,
  });

  final FolderFs folder;

  /// Null for a folder that is not a Notechondria folder yet.
  final FolderManifest? manifest;

  /// Entries in the folder root; without a manifest, a non-zero count must
  /// be confirmed by the user before the folder is initialized (6.1
  /// mitigation 3). Zero offers "Start empty" and "Start from an archive".
  final int entryCount;

  /// Set when the folder cannot be used (a newer layout_version).
  final String? refusal;

  bool get isEmpty => manifest == null && entryCount == 0;
}

/// Result of comparing a picked folder with the same-tab or remembered
/// handle of the same folder_id (3.7).
enum CopyCheck { same, moved, looksLikeCopy, needsAccess }

/// 3.7: [other] is the handle this tab holds, or the remembered one.
/// `isSameEntry` needs no permission; reading [other] needs a read grant,
/// which this never requests (each activation-gated call is the first call
/// of its own click handler, 1.3).
Future<CopyCheck> checkPickedAgainst(FolderFs picked, FolderFs? other,
    {required String folderId}) async {
  if (other == null || await picked.isSameEntry(other)) return CopyCheck.same;
  if (await other.queryPermission(write: false) != FolderPermission.granted) {
    return CopyCheck.needsAccess;
  }
  return readOtherForCopyCheck(other, folderId: folderId);
}

/// Reads a granted [other]: same folder_id means the picked folder is a
/// copy; gone (NotFoundError) or no longer this folder means it moved.
Future<CopyCheck> readOtherForCopyCheck(FolderFs other,
    {required String folderId}) async {
  try {
    final manifest = await readFolderManifest(other);
    return manifest?.folderId == folderId
        ? CopyCheck.looksLikeCopy
        : CopyCheck.moved;
  } on FolderFsException catch (e) {
    if (e.kind == FolderErrorKind.notFound) return CopyCheck.moved;
    rethrow;
  } on FolderLayoutException {
    return CopyCheck.moved;
  }
}

/// Reads the picked folder for "Choose again": a manifest with
/// [expectedFolderId] returns null (continue); anything else a refusal.
Future<PickRefused?> refusalForPicked(FolderFs picked,
    {required String expectedFolderId, required String name}) async {
  final FolderManifest? manifest;
  try {
    manifest = await readFolderManifest(picked);
  } on FolderLayoutException catch (e) {
    return PickRefused(e.message);
  }
  if (manifest == null) {
    return PickRefused(LocalFolderMessages.pickNoManifest(picked.name, name));
  }
  if (manifest.folderId != expectedFolderId) {
    return PickRefused(
        LocalFolderMessages.pickDifferentFolder(
            picked.name, manifest.folderId, name, expectedFolderId),
        canSwitch: true);
  }
  return null;
}

/// Inspects a folder picked for a first connect.
Future<ConnectPick> inspectConnectPick(FolderFs picked) async {
  FolderManifest? manifest;
  String? refusal;
  try {
    manifest = await readFolderManifest(picked);
  } on FolderLayoutException catch (e) {
    refusal = e.message;
  }
  final entries = await listOrEmpty(picked, '');
  return ConnectPick(
      folder: picked,
      manifest: manifest,
      entryCount: entries.length,
      refusal: refusal);
}
