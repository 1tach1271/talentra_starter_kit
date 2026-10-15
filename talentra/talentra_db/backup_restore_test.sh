#!/usr/bin/env bash
set -e
DB=${1:-talentra}; RESTORE_DB=${DB}_restore
s=$(date +%s.%N); pg_dump -Fc -d "$DB" -f /tmp/${DB}.dump; b=$(date +%s.%N)
psql -q -d postgres -c "drop database if exists ${RESTORE_DB}" -c "create database ${RESTORE_DB}"
pg_restore -d "$RESTORE_DB" -j 4 /tmp/${DB}.dump; e=$(date +%s.%N)
echo "backup_seconds=$(echo "$b - $s" | bc) restore_seconds=$(echo "$e - $b" | bc) dump_size=$(du -h /tmp/${DB}.dump | cut -f1)"
for t in candidate_profile job application; do
  echo "$t: source=$(psql -d $DB -Atc "select count(*) from $t") restored=$(psql -d $RESTORE_DB -Atc "select count(*) from $t")"
done
