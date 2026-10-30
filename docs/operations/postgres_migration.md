# PostgreSQL Backup and Restore for Service Migration

This guide replaces the old root-level `code_snippets/database-backup.sh` and `database-restore.sh` one-liners with portable scripts that work against arbitrary PostgreSQL hosts.

## Canonical scripts

- `docs/operations/scripts/postgres_backup.sh`
- `docs/operations/scripts/postgres_restore.sh`

Both scripts use the standard PostgreSQL client environment variables:

- `PGHOST`
- `PGPORT`
- `PGUSER`
- `PGPASSWORD`
- `PGDATABASE`

## 1) Back up a source database

Example:

```bash
export PGHOST=source-db.example.com
export PGPORT=5432
export PGUSER=postgres
export PGPASSWORD='replace-me'
export PGDATABASE=notechondria

bash docs/operations/scripts/postgres_backup.sh ./backups/notechondria-$(date +%Y%m%d-%H%M%S).dump
```

The script creates a **custom-format** dump suitable for `pg_restore`.

## 2) Restore into a target database

Example:

```bash
export PGHOST=target-db.example.com
export PGPORT=5432
export PGUSER=postgres
export PGPASSWORD='replace-me'
export PGDATABASE=notechondria

bash docs/operations/scripts/postgres_restore.sh ./backups/notechondria-20260404-060000.dump
```

By default the restore script runs with:
- `--clean`
- `--if-exists`
- `--no-owner`
- `--no-privileges`

That makes it safer for cross-host migration where roles and ownership differ.

## 3) Create the target database first when needed

If the target database does not already exist, create it first:

```bash
createdb -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" "$PGDATABASE"
```

If your managed host does not allow `createdb`, create the empty database from the provider dashboard first, then run the restore.

## 4) Common migration pattern

### Source host

```bash
export PGHOST=old-db.example.com
export PGPORT=5432
export PGUSER=postgres
export PGPASSWORD='old-password'
export PGDATABASE=notechondria
bash docs/operations/scripts/postgres_backup.sh ./backups/notechondria.dump
```

### Target host

```bash
export PGHOST=new-db.example.com
export PGPORT=5432
export PGUSER=postgres
export PGPASSWORD='new-password'
export PGDATABASE=notechondria
createdb -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" "$PGDATABASE" || true
bash docs/operations/scripts/postgres_restore.sh ./backups/notechondria.dump
```

## 5) Verification after restore

```bash
psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -c '\dt'
psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -c 'select count(*) from django_migrations;'
```

For app-level verification after restore:

```bash
cd backend
python manage.py migrate --noinput
python manage.py check
```

## Why the old snippets were replaced

The old snippets were too thin to be safe or reusable:
- hard-coded assumptions like `postgres`
- no guardrails
- no docs around credentials or target database prep
- not clearly tied to migration workflows

These replacement scripts are still simple, but they are at least portable, parameterized, and documented.

## Northflank to local Jenkins preparation (2026-10-30)

The local runtime remains a GitHub-main/webhook Jenkins deployment. Migration
changes data volumes and the private local env; it does not replace SCM with
local source and does not connect the local app to the production database.

Cloudflare preparation is complete: 1,014 R2 objects (624 media, 390 static;
56,379,831 bytes) were downloaded using `prod.env`, verified for size and
checksum, and imported into the existing local Docker volumes. The `media/`
and `static/` key prefixes map to `/home/mediafiles/` and `/home/staticfiles/`.
All 624 media files were verified again through the local HTTP gateway.
Original local data was backed up before import. Cloudflare objects were not
changed or deleted; the local app keeps its local filesystem storage config.

Private evidence lives under ignored `logs/migration/`. `latest-run` points to
the timestamped download, SHA-256 manifest, operation scripts, logs and status.
`local-before/` contains the original local custom-format PostgreSQL dump and
both original volume tar archives, with backup checksums. These contain private
data and must not be committed or shared as public artifacts.

**Production database import is pending.** The hostname in prod.env resolves,
but its PostgreSQL port 5432 times out from this host. The local database has
not been replaced. Obtain a publicly reachable Northflank database endpoint
and port (with TLS), a tunnel from an authorized Northflank environment, or a
custom-format production dump. A dashboard/API credential may be needed to
obtain that connection. Database credentials alone do not enable network access.

Once connected:

1. Preserve another local backup if any local data changed. Quiesce local
   writes and avoid concurrent Jenkins deployment during restore.
2. Take a consistent remote pg_dump snapshot using a client compatible with
   the remote PostgreSQL version, then restore into a new local staging
   database with no ownership/ACL transfer. Keep the current local database
   available for rollback.
3. Compare table/row counts, user IDs, note IDs, foreign keys, migrations,
   sequences, and referenced media keys. Audit embedded production media URLs;
   downloaded files alone do not rewrite URLs stored in Markdown.
4. Switch the local app only after staging verification. Account for
   bootstrap_platform resetting the env-named admin password and startup
   clearing application sessions; preserve the intended production account
   identity and credentials.
5. Before the actual cutover, pause production writes and capture a final
   database snapshot plus an R2 delta. Reconcile and verify again. The earlier
   asset download is a preparation snapshot, not a live replication stream.
6. Verify the local app, auth callbacks, uploads, and public routing before
   retiring Northflank. Do not delete the source database or bucket until the
   owner confirms the cutover and rollback retention.
