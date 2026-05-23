# Local Backup and Restore Scripts

The repo root `scripts/` directory includes four click-run Python
scripts for operator backups. Each script reads credentials directly
from the repo-root `.env` file and does not require command-line
arguments.

## Database

- `scripts/backup_database.py`
- `scripts/restore_database.py`

The database backup script writes a PostgreSQL tar-format dump to:

```text
scripts/db_backup/<YYYYmmdd-HHMMSS>.tar
```

The restore script uses the newest `.tar` in `scripts/db_backup/`
unless `RESTORE_FILE` is set inside the script.

Both scripts read `DATABASE_URL` first. If that is absent, they build a
connection string from:

- `POSTGRE_HOST`
- `POSTGRE_PORT`
- `POSTGRE_DB`
- `POSTGRE_USERNAME`
- `POSTGRE_PASSWORD`

The database scripts require PostgreSQL client tools on the local
machine:

- `pg_dump`
- `pg_restore`

## Cloudflare R2

- `scripts/backup_cloudflare_r2.py`
- `scripts/restore_cloudflare_r2.py`

The R2 backup script writes an app-version-independent tar archive to:

```text
scripts/r2_backup/<YYYYmmdd-HHMMSS>.tar
```

The archive contains `manifest.json` plus opaque object payloads under
`objects/`. The manifest maps each object key to its payload path and
records content type, size, ETag, and last-modified values where R2
returns them.

The R2 scripts read:

- `CLOUDFLARE_R2_BUCKET_NAME`
- `CLOUDFLARE_R2_ACCOUNT_ID`
- `CLOUDFLARE_R2_ACCESS_KEY_ID`
- `CLOUDFLARE_R2_SECRET_ACCESS_KEY`

They use Python stdlib AWS SigV4 signing against Cloudflare's S3 API,
so `boto3` and AWS CLI are not required.

## Operator Variables

Each script has editable constants near the top:

- `USER_SELECTED_BACKUP_DIR`: use a custom backup directory.
- `BACKUP_FILENAME`: force a backup filename.
- `RESTORE_FILE`: restore an exact archive instead of the newest one.
- `REQUIRE_CONFIRMATION`: restore safety prompt.

The R2 restore script also has:

- `DELETE_REMOTE_OBJECTS_NOT_IN_BACKUP`: when `False`, restore
  overwrites matching keys and leaves extra remote objects alone. Set
  to `True` only when intentionally replacing the bucket contents with
  the archive state.

Do not commit generated backup archives. They contain production data
and may include user media.
