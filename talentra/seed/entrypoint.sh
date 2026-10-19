#!/usr/bin/env bash
set -e

HOST="${DB_HOST:-db}"
PORT="${DB_PORT:-5432}"
USER="${DB_USER:-talentra}"

echo "Waiting for PostgreSQL at $HOST:$PORT ..."

# Poll until postgres accepts connections (max 60s)
for i in $(seq 1 30); do
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
        echo "PostgreSQL is ready."
        break
    fi
    echo "  attempt $i/30 — not ready yet, waiting 2s..."
    sleep 2
done

echo "Running Talentra seed scripts..."
python run_all.py

echo "Seeding complete. Container will now exit."
