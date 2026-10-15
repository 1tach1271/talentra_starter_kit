#!/usr/bin/env bash
set -e

HOST="${DB_HOST:-db}"
PORT="${DB_PORT:-5432}"

echo "Waiting for PostgreSQL at $HOST:$PORT (max 5 min) ..."

# Poll until postgres accepts connections — 150 attempts × 2s = 300s max.
# The DB container runs all initdb SQL files before accepting connections,
# which can take 2-3 minutes for the full seed dataset.
READY=0
for i in $(seq 1 150); do
    if python - <<'EOF'
import psycopg, os, sys
try:
    psycopg.connect(
        host=os.getenv("DB_HOST","db"),
        port=int(os.getenv("DB_PORT","5432")),
        dbname=os.getenv("DB_NAME","talentra"),
        user=os.getenv("DB_USER","talentra"),
        password=os.getenv("DB_PASSWORD","talentra"),
        connect_timeout=2,
    ).close()
    sys.exit(0)
except Exception:
    sys.exit(1)
EOF
    then
        echo "PostgreSQL is ready (attempt $i)."
        READY=1
        break
    fi
    echo "  attempt $i/150 — not ready yet, waiting 2s..."
    sleep 2
done

if [ "$READY" -eq 0 ]; then
    echo "ERROR: PostgreSQL did not become ready after 300 seconds. Aborting." >&2
    exit 1
fi

echo "Running Talentra seed scripts..."
python run_all.py

echo "Seeding complete. Container will now exit."
