#!/bin/sh
# First boot only (after 10-dump.sql): set every demo login's password and mark all
# migrations shipped with this dump as already applied (the dump includes them).
set -e
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v pw="$DEMO_PASSWORD" <<'SQL'
UPDATE doctor SET password = :'pw', failed_login_attempts = 0, account_locked_until = NULL;
UPDATE staff  SET password = :'pw', failed_login_attempts = 0, account_locked_until = NULL;
CREATE TABLE IF NOT EXISTS schema_migrations (filename text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now());
SQL
for f in /migrations/*.sql; do
  case "$f" in *.down.sql) continue ;; esac
  psql -q -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "INSERT INTO schema_migrations(filename) VALUES ('$(basename "$f")') ON CONFLICT DO NOTHING"
done
