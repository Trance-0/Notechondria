# Local folder mode verification scripts

Rerunnable versions of the checks used for local folder mode Phases 1 to 3
and releases 0.1.201 and 0.1.202 (recipes: `docs/development/local_folder_mode/testing.md`
8.3 and `.agents/tasks/local-folder-phase{1,2,3}-progress.md`). Run them
from any directory; each script prints its usage with `--help`.

## Prerequisites

- Docker, plus `git`, `tar`, `flock`, `timeout`; `rsync` for `OVERLAY` and
  `gen_l10n.sh`; `python3` for `gen_l10n.sh`.
- A host with at least 16 GB RAM (`docs/AGENTS.md`). Follow its host
  resource budget: check `free -h`, `nproc`, and `docker ps` first.
- Network access to pull `ghcr.io/cirruslabs/flutter:stable` (3.44.0 was
  verified), `mcr.microsoft.com/playwright/python:v1.49.1-noble`,
  `python:3.11-slim`, and pub/pip packages.
- One-time: `scripts/local_folder_verify/build_image.sh` builds
  `nc-flutter-chromium:local` from `Dockerfile.chromium` (on the original
  host it reproduced the earlier `nc-lf1a-flutter-chromium:local` image ID).

## Settings (environment)

| Variable | Default |
|---|---|
| `NC_VERIFY_DIR` | `${TMPDIR:-/tmp}/nc_verify`: scratch copies, logs, pub/pip caches, `flutter.lock` |
| `FLUTTER_IMAGE` | `ghcr.io/cirruslabs/flutter:stable` |
| `CHROMIUM_IMAGE` | `nc-flutter-chromium:local` |
| `NC_MEMORY` | `6g` (`--memory` of every container; the backend uses `BACKEND_MEMORY=2g`) |
| `APP_VERSION` | contents of `VERSION` |
| `OVERLAY` | empty; working-tree paths (e.g. `frontend/planner_app`) copied over the `git archive HEAD` scratch copy |

## Scripts and baselines (0.1.202)

| Script | What it proves | Baseline |
|---|---|---|
| `ci.sh` (`APPS=`, `HOOK_APPS=`, `SKIP_SHARED=1`) | The `frontend-pages.yml` sequence: smoke test and release build per app, shared `test/local_folder/ -r compact` without `pub get`, OPFS hook builds; no hook strings in release bundles; dominant bundle version = `VERSION` | smoke editor 15, planner 22, portal 23; shared 353 passed; 0 hook strings |
| `analyze_smoke.sh <editor\|planner\|portal\|shared>` | `flutter analyze` (fails only on errors) and the smoke test, or `TEST=...` | analyze editor 99, planner 105, portal 123, shared 7 issues, 0 errors each |
| `chrome_tests.sh` (`TESTS=`) | Shared OPFS and lock-timing tests in Chromium with `NOTECHONDRIA_TEST_OPFS_FOLDER=true`; every sampled listener on loopback | 8 passed (7 OPFS, 1 timing) |
| `backend_contract.sh` | `notes.test_api_contract`: fixture keys and JSON types match the real Django API | OK, 42 live responses (44 fixture files, 2 not backend routes) |
| `e2e.sh <editor\|planner\|portal>` | Real UI in headless Chromium against a folder (OPFS-backed picker): create, edit, delete, reload; no `/api/` after boot | editor 7/7 (0.1.201), planner 6/6, portal 6/6 steps |
| `firefox.sh <app>` | Firefox 132 shows the folder option disabled with the noDirectoryPicker message | editor, planner pass; portal not run yet |
| `u3_spike.sh` | A real click reaches `showDirectoryPicker` with user activation | both clicks isActive true then AbortError; control SecurityError |
| `gen_l10n.sh` | Regenerates shared l10n with the `activityWeightN` workaround; writes into the working tree | three files rewritten; review `git diff` |

The full shared suite (`analyze_smoke.sh shared` with `TEST=test/`) has 3
pre-existing failures in `test/version_update_banner_test.dart`; only
`test/local_folder/` runs in CI.

`e2e.sh`, `firefox.sh`, and `u3_spike.sh` reuse the builds in
`$NC_VERIFY_DIR/lfv_sites/` that `ci.sh` leaves for the current HEAD, and
build them otherwise (`REBUILD=1` forces it). `drivers/e2e.ics` is the
calendar file the planner/portal driver writes and imports. Each script
exits 0 on pass, 1 on a failed check, and 2 when the check could not run.

## Security rules

- No container publishes a port (`run_heavy` refuses `-p`, `--publish*`,
  and host networking). The repo is never mounted.
- `e2e.sh`, `firefox.sh`, and `u3_spike.sh` run with `--network none`.
  Their static server (127.0.0.1:8099) and browser debugging ports
  (127.0.0.1:9222 DevTools, 127.0.0.1:9223 WebDriver BiDi) exist only
  inside the container, and the scripts fail if any recorded listener is
  not on loopback. `chrome_tests.sh` needs the network for the web test
  runner's `pub get` and samples `/proc/net/tcp{,6}` the same way.
- No credentials in the scripts; the backend test uses its own test settings.

## Known gotchas

- On some hosts the kernel ignores `--memory` ("Limitation discarded") and
  `--cpus` fails (cgroup v2 threaded mode). The real bounds are then the
  `timeout` wrappers and one container at a time (`flutter.lock`).
- Headless Chromium answers the real directory picker with AbortError, so
  the e2e drivers stub `showDirectoryPicker` with an OPFS directory.
- With `--network none`, fonts from fonts.gstatic.com are retried and
  fail, so screenshots draw no text; use the label dumps, or `LOCAL_ROBOTO=1`.
- `lib/main.dart` in all three apps (Phase 3 hit it in the portal) and the
  shared barrel `lib/notechondria_shared.dart` use CRLF line endings; keep
  CRLF when a script or editor rewrites lines there.
- `flutter gen-l10n` rejects the `activityWeightN` int placeholder; use
  `gen_l10n.sh`, never a plain `flutter gen-l10n`. The same error makes a
  plain `flutter pub get` in `notechondria_shared` exit 1 after it resolves
  packages; the scripts accept exactly that case.
- After a host reboot the local preview containers can fail to restart
  with containerd "file exists"; `scripts/local_remote_deploy.sh up`
  recreates them.
