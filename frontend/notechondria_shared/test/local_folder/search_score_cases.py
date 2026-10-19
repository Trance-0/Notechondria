"""Expected values of test/local_folder/search_score_test.dart.

Run with CPython (3.9 was used): `python3 search_score_cases.py`. It prints
the `ratio` and `score` cases embedded in the test's `_cases` constant,
from difflib.SequenceMatcher and a copy of note_search_score
(backend/notes/api.py:254-274). The API ranking case of the test was
computed with the same function over its `_apiNotes`.
"""
import json, re, sys
from difflib import SequenceMatcher

def note_search_score(title, description, content, query):
    normalized = query.strip().lower()
    if not normalized:
        return (1.0, 1.0)
    title = (title or "").lower()
    description = (description or "").lower()
    content = (content or "").lower()
    searchable = " ".join([title, description, content]).strip()
    tokens = [t for t in re.split(r"\s+", normalized) if t]
    exact_hits = sum(1 for t in tokens if t in searchable)
    title_hits = sum(1 for t in tokens if t in title)
    fuzzy = max(
        SequenceMatcher(None, normalized, title).ratio() if title else 0.0,
        SequenceMatcher(None, normalized, description).ratio() if description else 0.0,
        SequenceMatcher(None, normalized, content[:400]).ratio() if content else 0.0,
        SequenceMatcher(None, normalized, searchable[:500]).ratio() if searchable else 0.0,
    )
    if exact_hits == 0 and fuzzy < 0.45:
        return None
    return ((exact_hits * 10.0) + (title_hits * 5.0) + fuzzy, fuzzy)

lorem = ("Mitochondria are membrane-bound organelles that generate most of the "
         "chemical energy needed to power the cell's biochemical reactions. ")
long_body = lorem * 8  # > 400 chars: exercises slicing and autojunk
ratio_cases = [
    ("", ""), ("a", ""), ("", "abc"), ("abc", "abc"), ("abcd", "bcde"),
    ("kitten", "sitting"), ("mitochondria", "mitochondrion"),
    ("krebs cycle", "the krebs cycle and atp"),
    ("atp", lorem), ("energy cell", long_body[:400]),
    ("membrane", ("ab" * 150) + "membrane" + ("cd" * 60)),
    ("eeee", "e" * 250 + "x" * 10),
    ("photosynthesis", "photo synthesis light reactions"),
    ("café", "cafe café"), ("名词", "名词解释 和 动词"), ("🧬 dna", "dna 🧬 helix"),
]
score_cases = [
    ("Krebs cycle", "Citric acid cycle", "# Krebs cycle\n\nAcetyl-CoA enters.", "krebs"),
    ("Krebs cycle", "Citric acid cycle", "# Krebs cycle\n\nAcetyl-CoA enters.", "  Citric ACID  "),
    ("Glycolysis", "", "Glucose to pyruvate", "pyruvate glucose"),
    ("Glycolysis", "", "Glucose to pyruvate", "glycolisys"),
    ("Glycolysis", "", "Glucose to pyruvate", "zzzz"),
    ("Cell energy", "notes", long_body, "mitochondria power"),
    ("Cell energy", "notes", long_body, "biochemical"),
    ("", "", "", "anything"),
    ("Anything", "", "", ""),
    ("Photosynthesis", "light", "Chlorophyll absorbs light.", "photosinthesis"),
    ("名词解释", "", "生物学 名词", "名词"),
    ("DNA 🧬", "", "Double helix", "🧬"),
]
out = {
    "ratio": [[a, b, SequenceMatcher(None, a, b).ratio()] for a, b in ratio_cases],
    "score": [[t, d, c, q, (list(s) if s else None)] for t, d, c, q in [x for x in score_cases]
              for s in [note_search_score(t, d, c, q)]],
}
json.dump(out, sys.stdout, ensure_ascii=False, indent=1)
