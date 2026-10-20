"""Splice the committed activityWeightN members into freshly generated
l10n files, then write them into the repo's l10n directory. Called by
scripts/local_folder_verify/gen_l10n.sh (the gen-l10n placeholder
workaround, first used in local folder Phase 2).

Usage: splice_l10n.py <generated dir> <repo l10n dir>
"""
import re
import sys

if len(sys.argv) != 3:
    raise SystemExit('Check not run: LocalFolderVerify/gen_l10n.splice — '
                     'usage: splice_l10n.py <generated dir> <repo l10n dir>')
gen_dir, repo_dir = sys.argv[1], sys.argv[2]
NAME = 'activityWeightN'


def member_span(text, start_pat):
    """(start, end) of the member whose signature matches start_pat: the
    doc comments above it are not included; a body is matched by braces."""
    m = re.search(start_pat, text)
    if m is None:
        raise SystemExit('l10n files not updated: LocalFolderVerify/'
                         f'gen_l10n.splice — member {NAME} not found')
    start = text.rfind('\n', 0, m.start()) + 1
    i = m.end()
    # Abstract declaration: ends at ';' before any '{'.
    semi = text.find(';', i)
    brace = text.find('{', i)
    if brace < 0 or (0 <= semi < brace):
        return start, semi + 1
    depth = 0
    for j in range(brace, len(text)):
        if text[j] == '{':
            depth += 1
        elif text[j] == '}':
            depth -= 1
            if depth == 0:
                return start, j + 1
    raise SystemExit('l10n files not updated: LocalFolderVerify/'
                     f'gen_l10n.splice — unbalanced braces after {NAME}')


pat = r'String ' + NAME + r'\('
for name in ('app_localizations.dart', 'app_localizations_en.dart',
             'app_localizations_zh.dart'):
    gen = open(f'{gen_dir}/{name}', encoding='utf-8').read()
    old = open(f'{repo_dir}/{name}', encoding='utf-8').read()
    gs, ge = member_span(gen, pat)
    os_, oe = member_span(old, pat)
    # Keep the @override line above an implementation, as generated.
    out = gen[:gs] + old[os_:oe] + gen[ge:]
    open(f'{repo_dir}/{name}', 'w', encoding='utf-8').write(out)
    print(f'{name}: spliced {NAME} ({oe - os_} chars committed form)')
