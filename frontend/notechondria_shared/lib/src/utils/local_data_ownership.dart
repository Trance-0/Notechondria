/// Cross-user offline-cache protection (0.1.192).
///
/// Local drafts, courses, and events live in the browser's storage for
/// this ORIGIN — shared by every user who signs in on this device. Without
/// an owner stamp, user B signing in on a machine where user A worked
/// offline would see A's drafts and could push them into B's cloud
/// account. [resolveLocalDataOwner] decides, at sign-in, whether the
/// existing local data belongs to the person now signing in.
library;

enum LocalDataOwnership {
  /// No owner was recorded yet — claim the local data for the current
  /// user (anonymous/first-run drafts become theirs). Harmless when there
  /// is no local data.
  claimed,

  /// The recorded owner matches the current user — normal case.
  sameUser,

  /// The recorded owner is a DIFFERENT user. The local data must not sync
  /// to the current account and the user should be warned.
  foreignUser,
}

class LocalOwnerDecision {
  const LocalOwnerDecision(this.status, {this.owner = '', this.priorOwner = ''});

  final LocalDataOwnership status;

  /// Owner to record after this decision (the current user for
  /// [claimed]/[sameUser]; unchanged for [foreignUser]).
  final String owner;

  /// The other user's identifier, set only for [foreignUser].
  final String priorOwner;

  bool get isForeign => status == LocalDataOwnership.foreignUser;
}

/// Decides local-data ownership at sign-in. [recordedOwner] is the stamp
/// persisted from a previous session (empty if never stamped);
/// [currentUser] is the username signing in now. Case-insensitive,
/// whitespace-tolerant; an empty current user is treated as a no-op
/// same-user (nothing to decide).
LocalOwnerDecision resolveLocalDataOwner({
  required String? recordedOwner,
  required String currentUser,
}) {
  final recorded = (recordedOwner ?? '').trim();
  final current = currentUser.trim();
  if (current.isEmpty) {
    return LocalOwnerDecision(LocalDataOwnership.sameUser, owner: recorded);
  }
  if (recorded.isEmpty) {
    return LocalOwnerDecision(LocalDataOwnership.claimed, owner: current);
  }
  if (recorded.toLowerCase() == current.toLowerCase()) {
    return LocalOwnerDecision(LocalDataOwnership.sameUser, owner: current);
  }
  return LocalOwnerDecision(
    LocalDataOwnership.foreignUser,
    owner: recorded,
    priorOwner: recorded,
  );
}
