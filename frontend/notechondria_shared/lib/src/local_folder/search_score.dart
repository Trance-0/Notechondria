// Port of `note_search_score` (`backend/notes/api.py:254-274`) and of the
// parts of Python's `difflib.SequenceMatcher` it uses (`ratio()` with the
// default `isjunk=None, autojunk=True`), so the folder ranks a search the
// way the backend does (F25, U12). Strings are compared as Unicode code
// points, as Python compares `str` elements.

/// `SequenceMatcher(None, a, b).ratio()`: `2 * M / T`, where `M` counts the
/// characters of the matching blocks and `T` is `len(a) + len(b)`.
double sequenceRatio(String a, String b) =>
    sequenceRatioOf(a.runes.toList(), b.runes.toList());

double sequenceRatioOf(List<int> a, List<int> b) {
  final total = a.length + b.length;
  if (total == 0) return 1.0;
  return 2.0 * _SequenceMatcher(a, b).matchingCharacters() / total;
}

class _SequenceMatcher {
  _SequenceMatcher(this.a, this.b) {
    for (var j = 0; j < b.length; j++) {
      (_b2j[b[j]] ??= <int>[]).add(j);
    }
    // autojunk: in a `b` of 200 or more elements, an element that occurs
    // more than `len(b) // 100 + 1` times is "popular" and is left out of
    // the index (it can still extend a match; no element is junk).
    final n = b.length;
    if (n >= 200) {
      final ntest = n ~/ 100 + 1;
      _b2j.removeWhere((_, indices) => indices.length > ntest);
    }
  }

  final List<int> a;
  final List<int> b;
  final Map<int, List<int>> _b2j = <int, List<int>>{};

  /// `find_longest_match(alo, ahi, blo, bhi)`; ties go to the smallest
  /// `i`, then the smallest `j`, as in Python.
  (int, int, int) _longest(int alo, int ahi, int blo, int bhi) {
    var besti = alo, bestj = blo, bestsize = 0;
    var j2len = <int, int>{};
    for (var i = alo; i < ahi; i++) {
      final next = <int, int>{};
      final indices = _b2j[a[i]];
      if (indices != null) {
        for (final j in indices) {
          if (j < blo) continue;
          if (j >= bhi) break;
          final k = (j2len[j - 1] ?? 0) + 1;
          next[j] = k;
          if (k > bestsize) {
            besti = i - k + 1;
            bestj = j - k + 1;
            bestsize = k;
          }
        }
      }
      j2len = next;
    }
    // Extend by equal elements on each end; with no junk these are the
    // popular elements the index left out.
    while (besti > alo && bestj > blo && a[besti - 1] == b[bestj - 1]) {
      besti--;
      bestj--;
      bestsize++;
    }
    while (besti + bestsize < ahi &&
        bestj + bestsize < bhi &&
        a[besti + bestsize] == b[bestj + bestsize]) {
      bestsize++;
    }
    return (besti, bestj, bestsize);
  }

  /// The sum of the sizes of `get_matching_blocks()`.
  int matchingCharacters() {
    var matched = 0;
    final queue = <(int, int, int, int)>[(0, a.length, 0, b.length)];
    while (queue.isNotEmpty) {
      final (alo, ahi, blo, bhi) = queue.removeLast();
      final (i, j, k) = _longest(alo, ahi, blo, bhi);
      if (k == 0) continue;
      matched += k;
      if (alo < i && blo < j) queue.add((alo, i, blo, j));
      if (i + k < ahi && j + k < bhi) queue.add((i + k, ahi, j + k, bhi));
    }
    return matched;
  }
}

String _head(String text, int count) {
  final runes = text.runes;
  return runes.length <= count ? text : String.fromCharCodes(runes.take(count));
}

final RegExp _whitespace = RegExp(r'\s+');

/// `note_search_score(note, query)`: `(score, fuzzy)`, or null when the
/// note does not match. An empty query scores `(1.0, 1.0)`.
(double, double)? noteSearchScore({
  required String title,
  required String description,
  required String content,
  required String query,
}) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return (1.0, 1.0);
  final t = title.toLowerCase();
  final d = description.toLowerCase();
  final c = content.toLowerCase();
  final searchable = [t, d, c].join(' ').trim();
  final tokens = normalized.split(_whitespace).where((s) => s.isNotEmpty);
  final exactHits = tokens.where(searchable.contains).length;
  final titleHits = tokens.where(t.contains).length;
  var fuzzy = 0.0;
  for (final candidate in [t, d, _head(c, 400), _head(searchable, 500)]) {
    if (candidate.isEmpty) continue;
    final r = sequenceRatio(normalized, candidate);
    if (r > fuzzy) fuzzy = r;
  }
  if (exactHits == 0 && fuzzy < 0.45) return null;
  return (exactHits * 10.0 + titleHits * 5.0 + fuzzy, fuzzy);
}
