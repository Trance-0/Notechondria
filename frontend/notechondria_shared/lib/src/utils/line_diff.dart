/// Line-level text diff for the note-conflict resolver (#31).
///
/// Produces side-by-side rows (local on the left, remote on the right)
/// with git-diff-style kinds, so the conflict dialog can highlight what
/// actually changed instead of only summarising each side. Pure and
/// dependency-free so it can be unit-tested in CI (the shared package's
/// own tests are not CI-run; a host app's `smoke_test.dart` covers it).
library;

import 'dart:math' as math;

enum DiffLineKind {
  /// Identical on both sides.
  equal,

  /// A line replaced by another — `left` is the local text, `right` the
  /// remote text (both non-null).
  changed,

  /// Present only locally (dropped on the remote side); `right` is null.
  removed,

  /// Present only remotely (added on the remote side); `left` is null.
  added,
}

class DiffRow {
  const DiffRow({this.left, this.right, required this.kind});

  /// The local line for this row, or null when the row is remote-only.
  final String? left;

  /// The remote line for this row, or null when the row is local-only.
  final String? right;

  final DiffLineKind kind;

  @override
  String toString() => 'DiffRow($kind, left=$left, right=$right)';
}

List<String> _splitLines(String text) {
  if (text.isEmpty) return const [];
  // Normalise CRLF/CR so a line-ending difference alone isn't a "change".
  return text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
}

/// Diffs [localText] against [remoteText] line-by-line (LCS) and returns
/// aligned side-by-side rows. A run of removed lines immediately followed
/// by added lines is paired into [DiffLineKind.changed] rows so edits show
/// old-vs-new on the same row; leftovers fall back to removed / added.
List<DiffRow> diffLines(String localText, String remoteText) {
  final a = _splitLines(localText); // local (left)
  final b = _splitLines(remoteText); // remote (right)
  final n = a.length;
  final m = b.length;

  // LCS length table (suffix DP): dp[i][j] = LCS(a[i..], b[j..]).
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i][j] = a[i] == b[j]
          ? dp[i + 1][j + 1] + 1
          : math.max(dp[i + 1][j], dp[i][j + 1]);
    }
  }

  // Walk to a raw {equal, removed, added} sequence. At a divergence we
  // emit removed before added, so removed runs precede added runs.
  final raw = <DiffRow>[];
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      raw.add(DiffRow(left: a[i], right: b[j], kind: DiffLineKind.equal));
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      raw.add(DiffRow(left: a[i], kind: DiffLineKind.removed));
      i++;
    } else {
      raw.add(DiffRow(right: b[j], kind: DiffLineKind.added));
      j++;
    }
  }
  while (i < n) {
    raw.add(DiffRow(left: a[i], kind: DiffLineKind.removed));
    i++;
  }
  while (j < m) {
    raw.add(DiffRow(right: b[j], kind: DiffLineKind.added));
    j++;
  }

  // Pair removed-runs with the following added-run into changed rows.
  final out = <DiffRow>[];
  var k = 0;
  while (k < raw.length) {
    if (raw[k].kind == DiffLineKind.removed) {
      final rem = <String>[];
      while (k < raw.length && raw[k].kind == DiffLineKind.removed) {
        rem.add(raw[k].left!);
        k++;
      }
      final add = <String>[];
      while (k < raw.length && raw[k].kind == DiffLineKind.added) {
        add.add(raw[k].right!);
        k++;
      }
      final maxLen = math.max(rem.length, add.length);
      for (var x = 0; x < maxLen; x++) {
        final l = x < rem.length ? rem[x] : null;
        final r = x < add.length ? add[x] : null;
        out.add(DiffRow(
          left: l,
          right: r,
          kind: l != null && r != null
              ? DiffLineKind.changed
              : (l != null ? DiffLineKind.removed : DiffLineKind.added),
        ));
      }
    } else {
      out.add(raw[k]);
      k++;
    }
  }
  return out;
}
