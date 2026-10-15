#!/usr/bin/env bash
# Talentra: one-shot create + load for PostgreSQL 16.
#
# Docker (friend's container):   ./setup_talentra.sh -c <container_name>
# Plain psql (local/remote):     PGHOST=... PGPORT=... PGUSER=... PGPASSWORD=... ./setup_talentra.sh
#
# Options
#   -c NAME    run inside this docker container (files are copied in with docker cp)
#   -d DB      database name (default: talentra)
#   -U USER    superuser (default: postgres)
#   -s SCALE   seed size: small (default) | laptop (1M profiles, 100K jobs, 5M apps) | none
#   -r         RESET: drop and recreate the database first (DESTROYS existing data)
#   -t         also run compliance checks + test suite at the end
set -euo pipefail

CONTAINER=""; DB="talentra"; PGUSER_="${PGUSER:-postgres}"; SCALE="small"; RESET=0; RUN_TESTS=0
while getopts "c:d:U:s:rth" o; do
  case $o in
    c) CONTAINER=$OPTARG ;; d) DB=$OPTARG ;; U) PGUSER_=$OPTARG ;; s) SCALE=$OPTARG ;;
    r) RESET=1 ;; t) RUN_TESTS=1 ;; *) sed -n '2,15p' "$0"; exit 1 ;;
  esac
done

SRC="$(cd "$(dirname "$0")" && pwd)"
FILES=(01_core 01b_helpers 02_admin_licence 03_org_sourcing 04_candidate 05_jobs_applications \
       06_gig_finance 07_notifications_community 08_analytics 09_security_rls)

case $SCALE in
  small)  SEED_ARGS=() ;;
  laptop) SEED_ARGS=(-v n_orgs=10000 -v n_profiles=1000000 -v n_jobs=100000 -v apps_per_job=50 -v n_notif=2000000) ;;
  none)   SEED_ARGS=() ;;
  *) echo "scale must be small|laptop|none"; exit 1 ;;
esac

# ---- how to run psql: inside the container, or directly ----
if [[ -n $CONTAINER ]]; then
  docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q true \
    || { echo "Container '$CONTAINER' is not running (docker ps)."; exit 1; }
  WORK=/tmp/talentra_sql
  docker exec "$CONTAINER" rm -rf $WORK
  docker exec "$CONTAINER" mkdir -p $WORK
  docker cp "$SRC/." "$CONTAINER:$WORK/"
  PSQL=(docker exec -i -w $WORK "$CONTAINER" psql -U "$PGUSER_" -v ON_ERROR_STOP=1 -q)
else
  command -v psql >/dev/null || { echo "psql not found; install postgresql-client or use -c <container>"; exit 1; }
  PSQL=(psql -U "$PGUSER_" -v ON_ERROR_STOP=1 -q)
  cd "$SRC"
fi

run()  { "${PSQL[@]}" -d "$1" "${@:2}"; }

echo "== Checking server"
VER=$(run postgres -Atc "show server_version_num")
(( VER >= 140000 )) || { echo "PostgreSQL 14+ required (16 recommended), found $VER"; exit 1; }
run postgres -Atc "select name from pg_available_extensions where name in ('pg_trgm','btree_gist')" | sort | tr '\n' ' ' | grep -q "btree_gist pg_trgm" \
  || { echo "Missing contrib extensions pg_trgm / btree_gist (the official postgres image has them)."; exit 1; }

EXISTS=$(run postgres -Atc "select 1 from pg_database where datname='$DB'")
if [[ -n $EXISTS ]]; then
  if (( RESET )); then
    echo "== RESET: dropping database $DB"
    run postgres -c "drop database \"$DB\" with (force)"
    EXISTS=""
  else
    N=$(run "$DB" -Atc "select count(*) from information_schema.tables where table_schema in ('public','dw')")
    if (( N > 0 )); then
      echo "Database '$DB' already has $N tables. Re-run with -r to drop and rebuild, or pick another -d name."; exit 1
    fi
  fi
fi
[[ -n $EXISTS ]] || { echo "== Creating database $DB"; run postgres -c "create database \"$DB\" encoding 'UTF8'"; }

echo "== Building schema"
for f in "${FILES[@]}"; do echo "   $f.sql"; run "$DB" -f "$f.sql"; done
echo "   indexing all foreign keys"; run "$DB" -c "call sp_index_fks()"

if [[ $SCALE != none ]]; then
  echo "== Seeding ($SCALE)"
  run "$DB" ${SEED_ARGS[@]+"${SEED_ARGS[@]}"} -f 10_seed.sql
fi

if (( RUN_TESTS )); then
  echo "== Compliance checks (expect 0 rows)"; run "$DB" -f 11_compliance_checks.sql
  echo "== Test suite"; run "$DB" -f 12_tests.sql
fi

echo "== Summary"
run "$DB" -Atc "select 'tables: '||count(*) from information_schema.tables where table_schema='public' and table_type='BASE TABLE'
                union all select 'foreign keys: '||count(*) from pg_constraint where contype='f'
                union all select 'dw tables: '||count(*) from information_schema.tables where table_schema='dw'"
echo "Done. Connect: psql -U $PGUSER_ -d $DB"
