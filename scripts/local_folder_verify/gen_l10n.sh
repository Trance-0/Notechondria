#!/usr/bin/env bash
# Regenerates the shared package's l10n Dart files from the working-tree ARB
# files, with the workaround for `activityWeightN`: `flutter gen-l10n`
# rejects that select's pre-existing int placeholder, so a scratch copy
# declares it a String, the generator runs there, and splice_l10n.py puts
# the committed activityWeightN members back before the three generated
# files are written into frontend/notechondria_shared/lib/src/l10n/.
# This is the one script that writes into the working tree.
set -euo pipefail
CHECK_NAME=gen_l10n
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
  cat <<'EOF'
Usage: scripts/local_folder_verify/gen_l10n.sh

Reads frontend/notechondria_shared/lib/l10n/*.arb (working tree) and
rewrites app_localizations{,_en,_zh}.dart in
frontend/notechondria_shared/lib/src/l10n/. Review `git diff` afterwards.
EOF
}
case "${1:-}" in
  -h | --help) usage; exit 0 ;;
  "") ;;
  *) usage >&2; not_run "unexpected argument '$1'." ;;
esac

require_docker
require_tools python3 rsync
shared="${REPO_ROOT}/frontend/notechondria_shared"
work="${NC_VERIFY_DIR}/lfv_l10n"
rm -rf "${work}"
mkdir -p "${work}" "${NC_VERIFY_DIR}/pub-cache"
rsync -a --exclude build/ --exclude .dart_tool/ --exclude '.flutter-plugins*' \
  "${shared}/" "${work}/notechondria_shared/"

python3 - "${work}/notechondria_shared/lib/l10n/app_en.arb" <<'EOF'
import sys
p = sys.argv[1]
text = open(p, encoding='utf-8').read()
old = '"@activityWeightN": {\n    "placeholders": { "n": { "type": "int" } }'
if text.count(old) != 1:
    raise SystemExit('l10n files not updated: LocalFolderVerify/gen_l10n.arb_patch — '
                     'the @activityWeightN metadata in app_en.arb changed shape; '
                     'update the pattern in gen_l10n.sh.')
open(p, 'w', encoding='utf-8').write(text.replace(old, old.replace('"int"', '"String"')))
EOF

script="$(cat <<'EOF'
cd /work/notechondria_shared
step pubget_shared 300 flutter pub get
step gen_l10n 300 flutter gen-l10n
EOF
)"
run_heavy "$(lfv_name l10n)" 900 "${FLUTTER_DOCKER[@]}" -v "${work}:/work" \
  -w /work/notechondria_shared "${FLUTTER_IMAGE}" bash -c "${CONTAINER_PRELUDE}
${script}" || fail "the gen-l10n container did not finish: exit $? (137 = killed by the timeout)."
summarize "${work}"

python3 "${LFV_DIR}/splice_l10n.py" "${work}/notechondria_shared/lib/src/l10n" "${shared}/lib/src/l10n"
say "wrote ${shared}/lib/src/l10n/app_localizations{,_en,_zh}.dart; review git diff"
