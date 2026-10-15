#!/usr/bin/env bash
set -e
DB=${1:-talentra}
export PGUSER=${PGUSER:-talentra}
export PGPASSWORD=${PGPASSWORD:-talentra}
for f in 010_helpers 011_core 020_admin_licence 030_org_sourcing 040_candidate 041_candidate_missing 050_jobs_applications 051_jobs_applications_missing 060_gig_finance 070_notifications_community 080_analytics 090_security_rls 095_index_fks; do
  echo ">> $f"; psql -v ON_ERROR_STOP=1 -q -d "$DB" -f $f.sql
done
echo ">> seed"; psql -v ON_ERROR_STOP=1 -q -d "$DB" ${SEED_ARGS} -f 100_seed.sql
