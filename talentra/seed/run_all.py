"""
seed/run_all.py
Orchestrator — runs all seeders in the correct dependency order.

Usage:
    python run_all.py            # use config.py defaults
    python run_all.py --dry-run  # just test the DB connection

The script is idempotent: each seeder uses ON CONFLICT DO NOTHING
or guards on existing row counts, so re-running it is safe.

Each seeder gets its own connection so that a rollback inside one
seeder (e.g. seed_gig_billing catching an EXCLUDE constraint violation)
does not affect the others.
"""

import argparse
import sys
import time

import psycopg

from config import DSN


def banner(msg: str):
    print(f"\n{'─' * 55}")
    print(f"  {msg}")
    print(f"{'─' * 55}")


def run_step(name: str, fn, conn):
    banner(f"[{name}]")
    t0 = time.perf_counter()
    fn(conn)
    elapsed = time.perf_counter() - t0
    print(f"  ✓ {name} completed in {elapsed:.1f}s")


def main():
    parser = argparse.ArgumentParser(description="Talentra seed runner")
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Only test the DB connection, do not seed",
    )
    args = parser.parse_args()

    print("Connecting to database …")
    try:
        conn = psycopg.connect(DSN, autocommit=False)
        print("  ✓ connected")
    except Exception as e:
        print(f"  ✗ connection failed: {e}")
        sys.exit(1)

    if args.dry_run:
        print("Dry run — connection OK, exiting.")
        conn.close()
        return

    # Late imports so config is loaded first
    import seed_master
    import seed_users_orgs
    import seed_candidates
    import seed_jobs_applications
    import seed_gig_billing
    import seed_notifications

    total_start = time.perf_counter()

    def refresh_analytics(step_conn):
        print("  → Populating DW dimensions, facts, and refreshing materialized views...")
        with step_conn.cursor() as cur:
            cur.execute("CALL dw.sp_refresh_dw()")
        step_conn.commit()

    steps = [
        ("Master data",           seed_master.run),
        ("Users & Organisations", seed_users_orgs.run),
        ("Candidates",            seed_candidates.run),
        ("Jobs & Applications",   seed_jobs_applications.run),
        ("Gig & Billing",         seed_gig_billing.run),
        ("Notifications",         seed_notifications.run),
        ("DW Analytics Refresh",  refresh_analytics),
    ]

    for name, fn in steps:
        try:
            # Open a fresh connection for each seeder
            step_conn = psycopg.connect(DSN, autocommit=False)
            run_step(name, fn, step_conn)
            step_conn.close()
        except Exception as e:
            print(f"\n✗ Error in [{name}]: {e}")
            try:
                step_conn.rollback()
                step_conn.close()
            except Exception:
                pass
            sys.exit(1)

    conn.close()

    total = time.perf_counter() - total_start
    banner(f"All steps complete in {total:.1f}s 🎉")

    # Print a quick row-count summary
    print("\nRow counts (spot-check):")
    try:
        with psycopg.connect(DSN) as check_conn:
            with check_conn.cursor() as cur:
                tables = [
                    "country", "skill", "industry", "job_role",
                    "organisation", "app_user", "candidate_profile",
                    "job", "application", "gig_request",
                    "gig_worker_profile", "wallet",
                    "subscription", "notification",
                    "community_post", "support_ticket",
                ]
                for tbl in tables:
                    try:
                        n = cur.execute(f"SELECT count(*) FROM {tbl}").fetchone()[0]
                        print(f"  {tbl:<25} {n:>8} rows")
                    except Exception:
                        pass
    except Exception:
        pass


if __name__ == "__main__":
    main()
