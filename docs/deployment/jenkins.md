# Local Jenkins full stack

The maintained [Jenkins runbook](../../deployment/jenkins/README.md) covers
installation, the two controllers on this host, private `local.env`, resource
limits, PostgreSQL backups, feature parity, credentials, and troubleshooting.

Use `http://localhost:9060/portal/`, `/editor/`, and `/planner/` for the local
apps. Their backend is the local `/api/v1/`; production remains GitHub Pages
and Northflank. Local media stays in Docker volumes instead of production R2.
