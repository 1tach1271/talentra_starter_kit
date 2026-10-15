#!/usr/bin/env bash
# backup_restore_test.sh
# Run manually to test backup + restore and print RTO timings.
#
# Usage:
#   ./backup_restore_test.sh [db_name]
#
# Defaults to db=talentra, user=talentra, host=localhost, port=5432.
# Set PGPASSWORD, PGHOST, PGPORT, PGUSER env vars to override.
#
# Example (run from the host while docker-compose is up):
#   PGPASSWORD=talentra ./backup_restore_test.sh talentra

set -e

DB="${1:-talentra}"
RESTORE_DB="${DB}_restore"
DUMP_FILE="/tmp/${DB}.dump"

export PGUSER="${PGUSER:-talentra}"
export PGHOST="${PGHOST:-localhost}"
export PGPORT="${PGPORT:-5432}"
export PGPASSWORD="${PGPASSWORD:-talentra}"

echo "=== Talentra Backup & Restore Test ==="
echo "  source DB : $DB"
echo "  restore DB: $RESTORE_DB"
echo "  dump file : $DUMP_FILE"
echo "  user      : $PGUSER @ $PGHOST:$PGPORT"
echo ""

# ── 1. Backup ────────────────────────────────────────────────────────────────
echo "[1/4] Running pg_dump ..."
s=$(date +%s%N)
pg_dump -Fc -d "$DB" -f "$DUMP_FILE"
b=$(date +%s%N)
backup_ms=$(( (b - s) / 1000000 ))
dump_size=$(du -h "$DUMP_FILE" | cut -f1)
echo "      done — ${backup_ms}ms, size=${dump_size}"

# ── 2. Create restore target ─────────────────────────────────────────────────
# Use the source DB as the maintenance database for the DROP/CREATE commands
# (avoids needing the postgres maintenance DB to exist under this user).
echo "[2/4] Creating restore database '$RESTORE_DB' ..."
psql -q -d "$DB" -c "DROP DATABASE IF EXISTS ${RESTORE_DB};"
psql -q -d "$DB" -c "CREATE DATABASE ${RESTORE_DB};"

# ── 3. Restore ───────────────────────────────────────────────────────────────
echo "[3/4] Running pg_restore (4 jobs) ..."
r=$(date +%s%N)
pg_restore -d "$RESTORE_DB" -j 4 "$DUMP_FILE"
e=$(date +%s%N)
restore_ms=$(( (e - r) / 1000000 ))
echo "      done — ${restore_ms}ms"

# ── 4. Row-count verification ────────────────────────────────────────────────
echo "[4/4] Verifying row counts ..."
all_ok=true
for t in candidate_profile job application notification wallet_ledger; do
    src=$(psql -d "$DB"         -Atc "SELECT count(*) FROM ${t}" 2>/dev/null || echo "N/A")
    rst=$(psql -d "$RESTORE_DB" -Atc "SELECT count(*) FROM ${t}" 2>/dev/null || echo "N/A")
    if [ "$src" = "$rst" ]; then
        status="✓"
    else
        status="✗ MISMATCH"
        all_ok=false
    fi
    echo "      ${status}  ${t}: source=${src}  restored=${rst}"
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=== Results ==="
echo "  backup_ms=${backup_ms}  restore_ms=${restore_ms}  dump_size=${dump_size}"
if $all_ok; then
    echo "  row counts: ALL MATCH ✓"
else
    echo "  row counts: MISMATCH DETECTED ✗" >&2
    exit 1
fi
