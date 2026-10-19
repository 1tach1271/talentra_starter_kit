"""
seed/config.py
DB connection settings and scale constants.
To scale up, just change the SCALE values below.
"""

import os

# ── Database connection ──────────────────────────────────────────────────────
DB_HOST     = os.getenv("DB_HOST",     "localhost")
DB_PORT     = int(os.getenv("DB_PORT", "5432"))
DB_NAME     = os.getenv("DB_NAME",     "talentra")
DB_USER     = os.getenv("DB_USER",     "talentra")
DB_PASSWORD = os.getenv("DB_PASSWORD", "talentra")

DSN = (
    f"host={DB_HOST} port={DB_PORT} dbname={DB_NAME} "
    f"user={DB_USER} password={DB_PASSWORD}"
)

# ── Scale constants ──────────────────────────────────────────────────────────
# Docket-required laptop-scale values for the Talentra PostgreSQL hackathon.
# These figures produce a realistic 1 M-profile dataset that fits on a
# developer laptop (16 GB RAM recommended) when the seeders use the chunked
# insertion strategy defined in seed_candidates.py and
# seed_jobs_applications.py.  Do NOT build the full lists in memory at these
# sizes — always generate → insert → commit in chunks.
#
# Quick reference:
#   ~1 M candidate_profile rows
#   ~10 K organisations + recruiter users
#   ~100 K job postings  (→ ~5 M applications at APPS_PER_JOB = 50)
#   ~2 M notification rows
# ─────────────────────────────────────────────────────────────────────────────
N_CANDIDATES    = 1_000_000   # candidate profiles
N_ORGS          = 10_000      # organisations (+ one recruiter per org)
N_JOBS          = 100_000     # job postings
APPS_PER_JOB    = 50          # applications per job (random subset of candidates)
N_GIG_WORKERS   = 2_000       # gig worker profiles
N_GIG_REQUESTS  = 5_000       # gig requests
N_NOTIFICATIONS = 2_000_000   # notification rows

# ── Batch size for executemany inserts ───────────────────────────────────────
# Increased from 500 → 2 000 for efficiency at scale.  Each executemany call
# sends one round-trip to Postgres; larger batches mean fewer round-trips and
# better throughput without ballooning per-batch memory.
BATCH_SIZE = 2_000
