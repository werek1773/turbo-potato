#!/usr/bin/env bash
# Runs the Supabase migrations and pgTAP tests against a throwaway local
# Postgres (no Docker needed). Usage: scripts/local-db/test.sh
# Requires: postgres + pgtap + pg_prove (e.g. apt install postgresql-16-pgtap
# libtap-parser-sourcehandler-pgtap-perl). With Docker available, prefer
# `supabase db start && supabase test db`.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PGBIN="${PGBIN:-$(pg_config --bindir 2>/dev/null || echo /usr/lib/postgresql/16/bin)}"
WORKDIR="$(mktemp -d)"
PORT="${PORT:-54399}"
RUN_AS=()
if [ "$(id -u)" = "0" ]; then
  chown postgres "$WORKDIR"
  RUN_AS=(su postgres -s /bin/bash -c)
fi

run() {
  if [ ${#RUN_AS[@]} -gt 0 ]; then "${RUN_AS[@]}" "$*"; else bash -c "$*"; fi
}

cleanup() {
  run "$PGBIN/pg_ctl -D $WORKDIR/data -m immediate stop" >/dev/null 2>&1 || true
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

run "$PGBIN/initdb -D $WORKDIR/data -A trust -U postgres" >/dev/null
run "$PGBIN/pg_ctl -D $WORKDIR/data -l $WORKDIR/log -o '-p $PORT -k $WORKDIR' -w start" >/dev/null

PSQL=(psql -h "$WORKDIR" -p "$PORT" -U postgres -d postgres -v ON_ERROR_STOP=1 -q)
"${PSQL[@]}" -c "alter database postgres set search_path = \"\$user\", public, extensions;"
"${PSQL[@]}" -f "$ROOT/scripts/local-db/supabase_shim.sql"

for migration in "$ROOT"/supabase/migrations/*.sql; do
  echo "migrate: $(basename "$migration")"
  "${PSQL[@]}" -f "$migration"
done

pg_prove -h "$WORKDIR" -p "$PORT" -U postgres -d postgres --ext .sql -r "$ROOT/supabase/tests"
