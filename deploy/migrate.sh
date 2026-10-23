#!/bin/sh
# Apply database/migrations/*.sql not yet recorded in schema_migrations, in filename order.
# Usage: deploy/migrate.sh <db-container>   (migrations mounted at /migrations)
set -e
DB="$1"
PSQL="docker exec -i $DB psql -v ON_ERROR_STOP=1 -U medixa -d hms -qAt"
$PSQL -c "SET client_min_messages=warning; CREATE TABLE IF NOT EXISTS schema_migrations (filename text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())"
for f in $(docker exec "$DB" sh -c 'ls /migrations/*.sql' | grep -v '\.down\.sql$' | sort); do
  name=$(basename "$f")
  [ -n "$($PSQL -c "SELECT 1 FROM schema_migrations WHERE filename='$name'")" ] && continue
  echo "Applying $name"
  $PSQL -1 -f "$f"
  $PSQL -c "INSERT INTO schema_migrations(filename) VALUES ('$name')"
done
