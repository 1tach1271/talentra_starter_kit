#!/usr/bin/env bash
# docker-entrypoint-initdb.d wrapper
# Runs talentra_db SQL files in the correct dependency order.
# Docker's initdb would run them alphabetically, which breaks FK dependencies.

set -e

DIR="/talentra_db"

run_sql() {
    echo ">> $1"
    psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$DIR/$1"
}

run_sql 01_core.sql
run_sql 01b_helpers.sql
run_sql 02_admin_licence.sql
run_sql 03_org_sourcing.sql
run_sql 04_candidate.sql
run_sql 04b_candidate_missing.sql
run_sql 05_jobs_applications.sql
run_sql 05b_jobs_applications_missing.sql
run_sql 06_gig_finance.sql
run_sql 06b_schema_fixes.sql
run_sql 07_notifications_community.sql
run_sql 08_analytics.sql
run_sql 09_security_rls.sql
run_sql 15_api_views.sql

echo ">> indexing foreign keys"
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "call sp_index_fks()"

echo ">> schema initialisation complete"
