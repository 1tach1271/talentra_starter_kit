#!/usr/bin/env bash
set -e
DB=${1:-talentra}
export PGUSER=${PGUSER:-postgres}
psql -v ON_ERROR_STOP=1 -q -d "$DB" -f 01_core.sql
for f in 01b_helpers 02_admin_licence 03_org_sourcing 04_candidate 04b_candidate_missing 05_jobs_applications 05b_jobs_applications_missing 06_gig_finance 07_notifications_community 08_analytics 09_security_rls; do
  echo ">> $f"; psql -v ON_ERROR_STOP=1 -q -d "$DB" -f $f.sql
done
psql -v ON_ERROR_STOP=1 -q -d "$DB" -c "call sp_index_fks()"
echo ">> seed"; psql -v ON_ERROR_STOP=1 -q -d "$DB" ${SEED_ARGS} -f 10_seed.sql
