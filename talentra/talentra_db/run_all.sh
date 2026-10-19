#!/usr/bin/env bash
# run_all.sh — manual schema + seed runner (alternative to Docker initdb)
# Usage: ./run_all.sh talentra
# With seed scale: SEED_ARGS="-v n_profiles=1000000" ./run_all.sh talentra
set -e
DB=${1:-talentra}
export PGUSER=${PGUSER:-talentra}

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

SQL_FILES=(
  01_core
  01b_helpers
  02_admin_licence
  03_org_sourcing
  04_candidate
  04b_candidate_missing
  05_jobs_applications
  05b_jobs_applications_missing
  06_gig_finance
  06b_schema_fixes
  07_notifications_community
  08_analytics
  09_security_rls
  15_api_views
)

for f in "${SQL_FILES[@]}"; do
  echo ">> $f.sql"
  psql -v ON_ERROR_STOP=1 -q -d "$DB" -f "$f.sql"
done

echo ">> indexing foreign keys"
psql -v ON_ERROR_STOP=1 -q -d "$DB" -c "call sp_index_fks()"

echo ">> seed (SQL-based)"
psql -v ON_ERROR_STOP=1 -q -d "$DB" ${SEED_ARGS:-} -f 10_seed.sql

echo ">> schema + seed complete"
