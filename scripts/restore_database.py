"""Restore the project PostgreSQL database from a tar dump.

Click-run defaults:
- reads target credentials from the repo-root `.env`
- restores the newest `scripts/db_backup/*.tar`

Optional operator edits:
- set USER_SELECTED_BACKUP_DIR to another directory
- set RESTORE_FILE to an exact tar path
- set REQUIRE_CONFIRMATION to False only for trusted automation

Requires the PostgreSQL `pg_restore` executable on PATH.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from urllib.parse import quote


ENV_FILE = Path(__file__).resolve().parents[1] / ".env"
USER_SELECTED_BACKUP_DIR: Optional[str] = None
RESTORE_FILE: Optional[str] = None
REQUIRE_CONFIRMATION = True
PG_RESTORE_EXE = "pg_restore"


def _fail(process: str, cause: str) -> None:
    raise SystemExit(
        f"Database restore not completed: Ops.Restore.Database/{process} - {cause}."
    )


def _load_env(path: Path) -> Dict[str, str]:
    if not path.exists():
        _fail("env_load", f"root .env file not found at {path}")
    values: Dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export ") :].strip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
            value = value[1:-1]
        values[key] = value
    return values


def _database_url(env: Dict[str, str]) -> Tuple[str, Optional[str]]:
    url = env.get("DATABASE_URL", "").strip()
    if url:
        return url, None

    required = [
        "POSTGRE_HOST",
        "POSTGRE_PORT",
        "POSTGRE_DB",
        "POSTGRE_USERNAME",
        "POSTGRE_PASSWORD",
    ]
    missing = [name for name in required if not env.get(name, "").strip()]
    if missing:
        _fail("env_parse", f"missing required database variable(s): {', '.join(missing)}")

    user = quote(env["POSTGRE_USERNAME"], safe="")
    password = quote(env["POSTGRE_PASSWORD"], safe="")
    host = env["POSTGRE_HOST"]
    port = env["POSTGRE_PORT"]
    db = quote(env["POSTGRE_DB"], safe="")
    return f"postgresql://{user}:{password}@{host}:{port}/{db}", env["POSTGRE_PASSWORD"]


def _restore_path() -> Path:
    if RESTORE_FILE:
        path = Path(RESTORE_FILE)
        if not path.exists():
            _fail("select_backup", f"restore file not found at {path}")
        return path

    backup_dir = (
        Path(USER_SELECTED_BACKUP_DIR)
        if USER_SELECTED_BACKUP_DIR
        else Path(__file__).resolve().parent / "db_backup"
    )
    if not backup_dir.exists():
        _fail("select_backup", f"backup directory not found at {backup_dir}")
    candidates = sorted(
        backup_dir.glob("*.tar"),
        key=lambda item: item.stat().st_mtime,
        reverse=True,
    )
    if not candidates:
        _fail("select_backup", f"no .tar backup files found in {backup_dir}")
    return candidates[0]


def _confirm(path: Path) -> None:
    if not REQUIRE_CONFIRMATION:
        return
    print(
        "Database restore confirmation required: Ops.Restore.Database/confirm - "
        f"target database objects may be replaced from {path}."
    )
    typed = input("Type RESTORE_DATABASE to continue: ").strip()
    if typed != "RESTORE_DATABASE":
        _fail("confirm", "confirmation phrase did not match")


def main() -> int:
    pg_restore = shutil.which(PG_RESTORE_EXE)
    if pg_restore is None:
        _fail("tool_check", f"{PG_RESTORE_EXE} executable not found on PATH")

    env_values = _load_env(ENV_FILE)
    db_url, password = _database_url(env_values)
    source = _restore_path()
    _confirm(source)

    command: List[str] = [
        pg_restore,
        "--clean",
        "--if-exists",
        "--no-owner",
        "--no-privileges",
        "--dbname",
        db_url,
        str(source),
    ]
    run_env = os.environ.copy()
    if password:
        run_env["PGPASSWORD"] = password

    print(
        "Database restore started: Ops.Restore.Database/pg_restore - "
        f"reading {source}."
    )
    result = subprocess.run(
        command,
        env=run_env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        cause = result.stderr.strip() or f"pg_restore exited with {result.returncode}"
        _fail("pg_restore", cause)

    print(
        "Database restore completed: Ops.Restore.Database/pg_restore - "
        f"{source} applied to target database."
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("Database restore aborted: Ops.Restore.Database/keyboard_interrupt - user interrupted the run.")
        raise SystemExit(130)
