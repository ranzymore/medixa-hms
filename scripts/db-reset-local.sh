#!/usr/bin/env bash
# Rebuild the LOCAL hms database from the committed Supabase dump (schema + demo data),
# then set every doctor/staff password to `password123` so all demo roles can log in.
# Plaintext is intentional: /api/login upgrades it to scrypt on first successful login.
#
# Usage: scripts/db-reset-local.sh [dump.sql]   (defaults to newest db/dump/*.sql)
set -euo pipefail
cd "$(dirname "$0")/.."

set -a; source .env.local; set +a
case "$DATABASE_URL" in
  *@localhost:*|*@127.0.0.1:*) ;;
  *) echo "Refusing: DATABASE_URL is not local ($DATABASE_URL)" >&2; exit 1 ;;
esac

DUMP="${1:-$(ls -t db/dump/*.sql | head -1)}"
# Dump uses \restrict (psql >= 17.6); run the client inside the server container when available.
CONTAINER="${PG_CONTAINER:-hms-pg}"
if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER"; then
  PSQL=(docker exec -i "$CONTAINER" psql -U postgres -d hms)
else
  PSQL=(psql "$DATABASE_URL")
fi

echo "Restoring $DUMP ..."
"${PSQL[@]}" -qc "SET client_min_messages=warning; DROP SCHEMA IF EXISTS public CASCADE;"
"${PSQL[@]}" -q -v ON_ERROR_STOP=1 < "$DUMP" > /dev/null

"${PSQL[@]}" -v ON_ERROR_STOP=1 <<'SQL'
UPDATE doctor SET password = 'password123', failed_login_attempts = 0, account_locked_until = NULL;
UPDATE staff  SET password = 'password123', failed_login_attempts = 0, account_locked_until = NULL;
ANALYZE;
SELECT 'doctor' AS kind, user_code, doctor_name AS name FROM doctor
UNION ALL SELECT role, user_code, name FROM staff ORDER BY 1, 2;
SQL
echo "Done. All accounts above: password123"
