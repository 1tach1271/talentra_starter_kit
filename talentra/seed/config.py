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

# ── Scale constants (small — increase later for full laptop-scale run) ───────
# Phase 5 laptop-scale targets:
#   N_CANDIDATES = 1_000_000
#   N_ORGS       = 10_000
#   N_JOBS       = 100_000
#   APPS_PER_JOB = 50
#   N_NOTIFICATIONS = 2_000_000

N_CANDIDATES    = 500       # candidate profiles
N_ORGS          = 20        # organisations (+ one recruiter per org)
N_JOBS          = 100       # job postings
APPS_PER_JOB    = 10        # applications per job (random subset of candidates)
N_GIG_WORKERS   = 20        # gig worker profiles
N_GIG_REQUESTS  = 30        # gig requests
N_NOTIFICATIONS = 200       # notification rows

# ── Batch size for executemany inserts ───────────────────────────────────────
BATCH_SIZE = 500
