"""Back up the project PostgreSQL database to a timestamped tar dump.

Click-run defaults:
- reads credentials from the repo-root `.env`
- writes to `scripts/db_backup/<YYYYmmdd-HHMMSS>.tar`

Optional operator edits:
- set USER_SELECTED_BACKUP_DIR to another directory
- set BACKUP_FILENAME to a fixed filename

Requires the PostgreSQL `pg_dump` executable on PATH.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from urllib.parse import quote


ENV_FILE = Path(__file__).resolve().parents[1] / ".env"
USER_SELECTED_BACKUP_DIR: Optional[str] = None
BACKUP_FILENAME: Optional[str] = None
PG_DUMP_EXE = "pg_dump"


def _fail(process: str, cause: str) -> None:
    raise SystemExit(
        f"Database backup not created: Ops.Backup.Database/{process} - {cause}."
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


def _backup_path() -> Path:
    backup_dir = (
        Path(USER_SELECTED_BACKUP_DIR)
        if USER_SELECTED_BACKUP_DIR
        else Path(__file__).resolve().parent / "db_backup"
    )
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    filename = BACKUP_FILENAME or f"{stamp}.tar"
    if not filename.endswith(".tar"):
        filename = f"{filename}.tar"
    backup_dir.mkdir(parents=True, exist_ok=True)
    return backup_dir / filename


def main() -> int:
    pg_dump = shutil.which(PG_DUMP_EXE)
    if pg_dump is None:
        _fail("tool_check", f"{PG_DUMP_EXE} executable not found on PATH")

    env_values = _load_env(ENV_FILE)
    db_url, password = _database_url(env_values)
    output = _backup_path()

    command: List[str] = [
        pg_dump,
        "--format=tar",
        "--no-owner",
        "--no-privileges",
        "--file",
        str(output),
        "--dbname",
        db_url,
    ]
    run_env = os.environ.copy()
    if password:
        run_env["PGPASSWORD"] = password

    print(
        "Database backup started: Ops.Backup.Database/pg_dump - "
        f"writing {output}."
    )
    result = subprocess.run(
        command,
        env=run_env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        if output.exists():
            output.unlink()
        cause = result.stderr.strip() or f"pg_dump exited with {result.returncode}"
        _fail("pg_dump", cause)

    size = output.stat().st_size
    print(
        "Database backup created: Ops.Backup.Database/pg_dump - "
        f"{output} ({size} bytes)."
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("Database backup aborted: Ops.Backup.Database/keyboard_interrupt - user interrupted the run.")
        raise SystemExit(130)
