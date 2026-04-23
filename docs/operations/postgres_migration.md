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
