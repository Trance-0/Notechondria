# LLM_CHECK

Use this checklist at the end of each modification round.

## Common mistakes seen in prior rounds

1. Claiming UI capture work without a runnable Flutter toolchain.
2. Adding docs or scripts without checking that file paths still match the current repo layout.
3. Writing pipeline and shell scripts whose argument order does not actually line up.
4. Leaving visible text encoding artifacts in UI copy.
5. Reporting success without clearly separating verified work from unverified work.
6. Expanding scope without checking whether there were already user changes in the worktree.

## Round-end checklist

- Confirm every command or test reported as passed was actually run in the current environment.
- Confirm every command or test not run is called out explicitly with the reason.
- Confirm docs reference current paths such as `backend/`, `frontend/`, `docs/`, and `deployment/`.
- Confirm CI files and scripts agree on invocation syntax and environment variable names.
- Confirm UI strings are plain, intentional, and free of mojibake or placeholder artifacts.
- Confirm `.gitignore` ignores local junk without hiding required tracked source files.
- Confirm no unrelated user changes were reverted.

## Current round log

- Fixed Jenkins deploy invocation to pass `project_dir` and `env_path` in the order required by `deployment/scripts/deploy_backend.sh`.
- Fixed a visible separator encoding issue in the Flutter front page subtitle.
- Made the selected course stateful across course, learner, and activity views.
- Expanded Flutter widget coverage for course selection flow.
- Added `CODEX.md` and updated repo links.
- Backend verification was blocked because the available `python.exe` resolves to the Windows Store shim rather than a runnable interpreter.
- Flutter verification was attempted through the installed `flutter.bat`, but the command did not complete within the allotted timeout in this environment.
- Switched Jenkins backup and test execution to Docker-native scripts so the host no longer needs `pg_dump` or `python`.
- Fixed Docker deployment mismatches: compose stack naming, separate `db` service usage, database name wiring, and app env injection.
- Re-truncated the sample deployment secret to `dwMlZWVt...jpZOJG2z` after it had previously been written too broadly.
- Updated the backup step to skip cleanly on first deployment when the database role/database does not exist yet, instead of failing the whole pipeline.
- Added a reminder that any tool referenced by container scripts, such as `nc` in `entrypoint.sh`, must be installed in the image build.
- Added a reminder that container wait logic must have an explicit timeout, and internal Compose service connections should use service names like `db` rather than host-local addresses.
- Switched Jenkins env loading to Environment Injector style variables rendered by `prepare_env.sh`, so the pipeline no longer depends on a secret-file credential being wired correctly.
- Removed shell `source` parsing from the backup script because Environment Injector values can contain spaces, which breaks naive `.env` sourcing.
- Documented that public-repo Pipeline SCM jobs should not keep unnecessary Git credentials attached in Jenkins job configuration.
