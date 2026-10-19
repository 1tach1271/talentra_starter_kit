# Talentra — Quick Start Guide
> For your friend building the UI. Follow these steps in order.

---

## Step 0: Prerequisites

You need:
- Docker Desktop (or Docker Engine + docker-compose)
- Python 3.10+ (for the targeted seed script, optional)
- A PostgreSQL client (DBeaver, TablePlus, or just `psql`)

---

## Step 1: Start the Database (one command)

```bash
cd talentra_starter_kit/talentra
docker compose up
```

What happens:
1. PostgreSQL 16 starts on port **5433** (mapped to 5432 inside the container)
2. On first run: all SQL files run automatically (schema + indexes + views) — takes ~2 minutes
3. The Python seed container starts and seeds 1M candidates + 100K jobs + 5M applications — takes **45–90 minutes**
4. The seed container exits when done. The DB keeps running.

**To check progress** (in a separate terminal):
```bash
docker logs -f talentra_seed
```

**To reset everything and start fresh:**
```bash
docker compose down -v    # -v wipes the data volume
docker compose up          # starts fresh, re-seeds from scratch
```

**Connection details:**
```
Host: localhost  Port: 5433  Database: talentra  User: talentra  Password: talentra
```

---

## Step 2: Run the Targeted Seed for Missing Data

The main seed (candidates + jobs + applications) runs automatically in Docker.
But gig/billing/notifications data may not have been seeded. Run this to fill those gaps:

```bash
# From the talentra/ directory:
cd seed
DB_HOST=localhost DB_PORT=5433 python3 -c "
import psycopg, seed_gig_billing, seed_notifications
from config import DSN
conn = psycopg.connect(DSN)
print('Seeding gig & billing...')
seed_gig_billing.run(conn)
print('Seeding notifications...')
seed_notifications.run(conn)
conn.close()
print('Done!')
"
```

This takes ~5–10 minutes and is safe to re-run (all scripts are idempotent).

---

## Step 3: Run Performance Benchmarks

```bash
cd talentra_db

# Run all 12 benchmark queries (10 runs each, ~2 minutes)
PGHOST=localhost PGPORT=5433 PGUSER=talentra PGPASSWORD=talentra \
  python3 bench.py talentra 10 ../perf/benchmark_results.csv

# Results are saved to:
#   perf/benchmark_results.csv  (summary p50/p95/p99)
#   plan_Q01.txt ... plan_Q12.txt  (full EXPLAIN ANALYZE output)
```

Copy the numbers from `benchmark_results.csv` into `perf/performance_baseline.md` section 4.

---

## Step 4: Run Backup/Restore Test

This must run INSIDE the Docker container (to avoid pg_dump version mismatch):

```bash
docker exec -e PGPASSWORD=talentra talentra_db bash /talentra_db/backup_restore_test.sh
```

Copy the timing output into `perf/performance_baseline.md` section 7.

---

## Step 5: Run Compliance Checks

```bash
PGPASSWORD=talentra psql -h localhost -p 5433 -U talentra -d talentra \
  -f talentra_db/11_compliance_checks.sql
```

This should return **0 rows** (meaning 0 rule violations). Screenshot it and add to `docs/rule_compliance_table.md`.

---

## Step 6: Run Test Suite

```bash
PGPASSWORD=talentra psql -h localhost -p 5433 -U talentra -d talentra \
  -f talentra_db/12_tests.sql
```

All tests should show `PASS`. Screenshot it and add to `security/security_design_note.md`.

---

## Step 7: Generate ERD Diagram (optional but recommended)

Using DBeaver:
1. Connect to `localhost:5433`, database `talentra`, user `talentra`, password `talentra`
2. Right-click the `public` schema → "Generate ER Diagram"
3. Export as PNG to `docs/erd_diagram.png`

---

## Step 8: Build the UI

Read `docs/ui_requirements.md` — it has 10 screens with exact SQL for each.
Read `docs/api_contract.md` — it has every view and stored function documented.

The database IS your API. There is no REST backend to build (unless you want to).
You can either:
- Build a thin backend (Node.js/Express or Python/FastAPI) that sets the DB role and queries views
- Use PostgREST to auto-generate REST endpoints from the views (see `docs/ui_requirements.md` section "Tech Stack")

---

## File Reference

| What | Where |
|---|---|
| Full UI requirements (10 screens) | `docs/ui_requirements.md` |
| API contract (every view + function) | `docs/api_contract.md` |
| Data dictionary (every column) | `docs/data_dictionary.md` |
| All views SQL | `talentra_db/15_api_views.sql` |
| RLS policies | `talentra_db/09_security_rls.sql` |
| Performance baseline | `perf/performance_baseline.md` |
| Extrapolation to 10M | `perf/full_scale_extrapolation.md` |
| Rule compliance table | `docs/rule_compliance_table.md` |
| Integration boundary table | `docs/integration_boundary_table.md` |
| Competitive coverage matrix | `docs/competitive_coverage_matrix.md` |
| Gig model decision | `docs/gig_model_decision.md` |
| Security: PII handling | `security/pii_handling_notes.md` |
| Security: threat model | `security/threat_model.md` |
| Security: design note | `security/security_design_note.md` |
| Current situation overview | `current_situation.md` |
