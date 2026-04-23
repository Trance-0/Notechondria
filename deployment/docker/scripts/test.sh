#!/usr/bin/env bash
set -Eeuo pipefail
export PATH=${PATH}
for app in frontend/editor_app frontend/planner_app frontend/portal_app; do
  (cd "$app" && flutter test test/smoke_test.dart -r compact)
done
cd backend && python manage.py test
