#!/usr/bin/env bash
# backup_restore_test.sh
# Runs pg_dump → pg_restore and verifies row counts.
# Must be run INSIDE the talentra_db Docker container to avoid pg_dump version mismatch.
#
# Usage (from your terminal):
#   docker exec -e PGPASSWORD=talentra talentra_db bash /talentra_db/backup_restore_test.sh
#
# Or directly if pg_dump version matches the server (PostgreSQL 16):
#   PGPASSWORD=talentra bash backup_restore_test.sh talentra

set -e

DB=${1:-talentra}
RESTORE_DB="${DB}_restore"
DUMP_FILE="/tmp/${DB}.dump"

echo "=== Talentra Backup / Restore Test ==="
echo "Source DB:  $DB"
echo "Restore DB: $RESTORE_DB"
echo "Dump file:  $DUMP_FILE"
echo ""

# ── 1. Dump ──────────────────────────────────────────────────────────────────
echo "Step 1: pg_dump..."
t_dump_start=$(date +%s)
pg_dump -U talentra -Fc -d "$DB" -f "$DUMP_FILE"
t_dump_end=$(date +%s)
DUMP_SECS=$((t_dump_end - t_dump_start))
DUMP_SIZE=$(du -h "$DUMP_FILE" | cut -f1)
echo "  Done. Size: $DUMP_SIZE | Time: ${DUMP_SECS}s"
echo ""

# ── 2. Create restore target ─────────────────────────────────────────────────
echo "Step 2: creating restore database..."
psql -U talentra -d postgres -c "DROP DATABASE IF EXISTS ${RESTORE_DB};" > /dev/null
psql -U talentra -d postgres -c "CREATE DATABASE ${RESTORE_DB};" > /dev/null
echo "  Done."
echo ""

# ── 3. Restore ───────────────────────────────────────────────────────────────
echo "Step 3: pg_restore (-j 4 parallel jobs)..."
t_restore_start=$(date +%s)
pg_restore -U talentra -d "$RESTORE_DB" -j 4 "$DUMP_FILE"
t_restore_end=$(date +%s)
RESTORE_SECS=$((t_restore_end - t_restore_start))
echo "  Done. Time: ${RESTORE_SECS}s"
echo ""

# ── 4. Row count verification ────────────────────────────────────────────────
echo "Step 4: row count verification..."
ALL_PASS=true
for t in candidate_profile job application organisation app_user wallet_ledger; do
    SRC=$(psql -U talentra -d "$DB"         -Atc "SELECT count(*) FROM ${t}" 2>/dev/null || echo "N/A")
    DST=$(psql -U talentra -d "$RESTORE_DB" -Atc "SELECT count(*) FROM ${t}" 2>/dev/null || echo "N/A")
    if [ "$SRC" = "$DST" ]; then
        STATUS="PASS"
    else
        STATUS="FAIL"
        ALL_PASS=false
    fi
    printf "  %-25s source=%-10s restored=%-10s %s\n" "$t" "$SRC" "$DST" "$STATUS"
done
echo ""

# ── 5. Summary ───────────────────────────────────────────────────────────────
echo "=== Summary ==="
echo "  Dump size:      $DUMP_SIZE"
echo "  Dump time:      ${DUMP_SECS}s"
echo "  Restore time:   ${RESTORE_SECS}s"
echo "  Total RTO:      $((DUMP_SECS + RESTORE_SECS))s"
if [ "$ALL_PASS" = "true" ]; then
    echo "  Row counts:     ALL PASS ✅"
else
    echo "  Row counts:     SOME FAILED ❌ — check output above"
fi

# ── 6. Cleanup ───────────────────────────────────────────────────────────────
echo ""
echo "Cleaning up restore DB..."
psql -U talentra -d postgres -c "DROP DATABASE IF EXISTS ${RESTORE_DB};" > /dev/null
rm -f "$DUMP_FILE"
echo "Done. Add the Summary numbers to perf/performance_baseline.md section 7."
