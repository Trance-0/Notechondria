# Release process

How to cut a tagged release and publish desktop + mobile artifacts to
GitHub Releases.

Related: [deployment/overview.md](overview.md),
[`.github/workflows/portal-release.yml`](../../.github/workflows/portal-release.yml).

## TL;DR

```bash
# 1. Make sure `main` is at the commit you want to ship and VERSION
#    has already been bumped to the new semver.
cat VERSION            # 0.1.68

# 2. Tag it and push the tag.
git tag v0.1.68
git push origin v0.1.68
```

That's it. The `portal-release.yml` workflow fires on `v*` tag push,
builds `portal_app` for every desktop + mobile target Flutter
supports, and attaches the archives to a fresh GitHub Release named
`v0.1.68` with auto-generated release notes.

No manual artifact upload, no "draft release" dance. Tag → push → done.

## What gets built

From [`.github/workflows/portal-release.yml`](../../.github/workflows/portal-release.yml):

| Target | Runner | Archive |
| --- | --- | --- |
| `linux-x64` | `ubuntu-latest` | `.tar.gz` |
| `linux-arm64` | `ubuntu-24.04-arm` | `.tar.gz` |
| `windows-x64` | `windows-latest` | `.zip` |
| `macos` | `macos-latest` | `.zip` (`.app` bundle inside) |
| `android-apk` | `ubuntu-latest` | `.apk` (universal) |
| `ios-unsigned` | `macos-latest` | `.zip` (unsigned `Runner.app`) |

Every archive is named
`portal_app-<VERSION>-<target>.<ext>` where `<VERSION>` is read from
the repo-root [`VERSION`](../../VERSION) file at build time and baked
into the app via `--dart-define=APP_VERSION=<value>` so the splash
screen's version text matches the filename.

**Skipped targets (and why):**
- Linux x86 (32-bit): Flutter Linux desktop is x64/arm64 only.
- Windows x86: Flutter Windows desktop is x64 only.
- iOS signed: distribution-signed builds need an Apple Developer
  certificate + provisioning profile stored as GitHub Actions
  secrets. This workflow produces an unsigned `.app` bundle
  suitable for dev install / sideload only.

## Manual runs (no tag)

Triggering the workflow from `Actions → portal-release → Run
workflow` builds all artifacts but **skips the release publish step**
(there's no tag to attach to). Useful for sanity-checking a build
before committing to a tag.

## When something goes wrong

- **A matrix leg fails mid-build.** The job has `fail-fast: false`,
  so the others finish and upload artifacts. The release publish step
  runs regardless as long as at least some artifacts were uploaded.
  If you want the missing targets, fix the cause and re-push the tag
  (delete the local + remote tag first):

  ```bash
  git tag -d v0.1.68
  git push origin :refs/tags/v0.1.68
  # fix
  git tag v0.1.68
  git push origin v0.1.68
  ```

- **Release already exists when the workflow tries to publish.**
  `softprops/action-gh-release@v2` with `draft: false` will either
  update the existing release or fail depending on config. In
  practice the safest recovery is the delete-and-re-push above.

- **Wrong VERSION in the artifact names.** The workflow reads
  `VERSION` at step time. Make sure you commit the VERSION bump
  *before* tagging.

## Pre-release checklist

1. `VERSION` has been bumped to the target semver (third digit
   only — see `agents/AGENTS.md` §1.5).
2. `docs/versions/<VERSION>.md` exists and describes what shipped.
3. `docs/SUMMARY.md` indexes the new version doc.
4. All three frontend smoke tests pass locally:

   ```bash
   for app in frontend/editor_app frontend/planner_app frontend/portal_app; do
     (cd "$app" && flutter test test/smoke_test.dart -r compact)
   done
   ```

5. Commit everything, push `main`, then tag + push tag.

## Not yet automated

- **Editor and planner app releases.** Only `portal_app` has a
  release workflow today. Duplicating this shape for
  `editor_app` + `planner_app` is tracked in
  [`docs/TODO.md`](../TODO.md). Expect a tag-namespacing decision
  then (e.g. `ve0.1.68` for editor, `vp0.1.68` for planner) to
  avoid three workflows racing to publish the same GitHub Release
  for a single `v*` tag.
- **Backend release.** No equivalent for Django. Backend
  "releases" are deploys: Northflank auto-deploys on push to the
  configured branch (see
  [northflank.md](northflank.md)); images are tagged
  `v<VERSION>.<BUILD_NUMBER>` by the Jenkins pipeline (see
  `deployment/jenkins/scripts/prepare_env.sh`). If we ever need
  signed backend artifacts attached to a GitHub Release, that's
  a separate workflow.
- **Windows code signing.** The `.zip` ships unsigned. For a
  real Windows release (SmartScreen-friendly) we'd need an EV
  code-signing cert and a signing step.

## Upstream branch

- As of 0.1.68: upstream target is **`main`**. Previously the
  active branch was `codex` while `main` tracked an earlier
  snapshot. 0.1.68 merged `codex` (188 commits) into `main` and
  archived the pre-merge `main` as a local `human-efforts` branch
  for provenance. Future PRs target `main`.
- The release workflow triggers on tag push, not branch push, so
  the branch flip didn't change anything about the release
  mechanics. You can cut a release from any commit on any branch
  just by tagging it `v*`.
