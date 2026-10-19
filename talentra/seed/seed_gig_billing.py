"""
seed/seed_gig_billing.py
Seeds:
  gig_worker_profile, gig_availability, gig_request, gig_application,
  plan, subscription, payment_order, invoice, wallet, wallet_ledger,
  profile_download (a few sample downloads)
"""

import random
import uuid
from datetime import datetime, timedelta, timezone

import psycopg
from faker import Faker

from config import DSN, N_GIG_WORKERS, N_GIG_REQUESTS, N_ORGS, BATCH_SIZE

fake = Faker("en_IN")
random.seed(42)
Faker.seed(42)

NOW = datetime.now(timezone.utc)

PLANS = [
    # (code, name, price, billing_period_months, download_credits, max_seats)
    ("basic",      "Basic",      4_999.00,  12, 100,   2),
    ("pro",        "Pro",       14_999.00,  12, 500,  10),
    ("enterprise", "Enterprise",49_999.00,  12, 2500, 50),
]

GIG_TITLES = [
    "Event Staff for Tech Summit",
    "Warehouse Workers for Festive Season",
    "Delivery Executives – Weekend",
    "Hospitality Staff for Wedding",
    "Security Personnel – Night Shift",
    "Promoters for Product Launch",
    "Data Entry Operators",
    "Call Centre Agents – Short Term",
    "Logistics Support – Diwali Rush",
    "Field Survey Team Members",
]


def _id_map(cur, table, key_col="code"):
    cur.execute(f"SELECT {key_col}, id FROM {table}")
    return {r[0]: r[1] for r in cur.fetchall()}


def run(conn):
    with conn.cursor() as cur:

        inr_id       = cur.execute("SELECT id FROM currency WHERE code='INR'").fetchone()[0]
        city_ids     = [r[0] for r in cur.execute("SELECT id FROM city").fetchall()]
        org_ids      = [r[0] for r in cur.execute("SELECT id FROM organisation ORDER BY id").fetchall()]
        profile_ids  = [r[0] for r in cur.execute("SELECT id FROM candidate_profile ORDER BY id").fetchall()]
        recruiter_rows = cur.execute("SELECT id, organisation_id FROM recruiter").fetchall()

        # candidate app_user ids for gig workers (last N_GIG_WORKERS candidates)
        user_ids = [r[0] for r in cur.execute(
            "SELECT app_user_id FROM candidate_profile ORDER BY id LIMIT %s", (N_GIG_WORKERS,)
        ).fetchall()]

        gig_status_ids     = _id_map(cur, "gig_status")
        gig_app_status_ids = _id_map(cur, "gig_application_status")
        sub_status_ids     = _id_map(cur, "subscription_status")
        pay_status_ids     = _id_map(cur, "payment_status")
        inv_status_ids     = _id_map(cur, "invoice_status")
        ledger_type_ids    = _id_map(cur, "ledger_entry_type")

        open_gig_id     = gig_status_ids.get("open")
        applied_gig_id  = gig_app_status_ids.get("applied")
        active_sub_id   = sub_status_ids.get("active")
        paid_pay_id     = pay_status_ids.get("paid")
        issued_inv_id   = inv_status_ids.get("issued")
        purchase_type_id= ledger_type_ids.get("purchase")
        download_type_id= ledger_type_ids.get("download")

        # ── 1. gig_worker_profiles ─────────────────────────────────────────
        # Guard: skip if already seeded (rerun safety)
        existing_workers = cur.execute("SELECT count(*) FROM gig_worker_profile").fetchone()[0]
        if existing_workers >= N_GIG_WORKERS:
            print(f"  gig_worker_profiles: {existing_workers} already exist, skipping")
        else:
            gig_worker_rows = [
                (uid, f"Available for gig work | {fake.job()}", round(random.uniform(200, 2000), 2), inr_id)
                for uid in user_ids
            ]
            cur.executemany(
                """
                INSERT INTO gig_worker_profile (app_user_id, headline, hourly_rate, rate_currency_id)
                VALUES (%s,%s,%s,%s)
                ON CONFLICT DO NOTHING
                """,
                gig_worker_rows,
            )
            print(f"  gig_worker_profiles: {cur.rowcount} inserted")

        # Always fetch from DB (works for first run and rerun)
        gig_worker_ids = [r[0] for r in cur.execute(
            "SELECT id FROM gig_worker_profile WHERE app_user_id = ANY(%s)", (user_ids,)
        ).fetchall()]

        # ── 2. gig_availability (non-overlapping windows per worker) ───────
        # Guard: skip if already seeded (rerun safety — avoids EXCLUDE violation)
        existing_avail = cur.execute("SELECT count(*) FROM gig_availability").fetchone()[0]
        if existing_avail > 0:
            print(f"  gig_availabilities:  {existing_avail} already exist, skipping")
        else:
            avail_rows = []
            for gwid in gig_worker_ids:
                # give each worker 1-2 future availability windows
                base = NOW + timedelta(days=random.randint(1, 5))
                for _ in range(random.randint(1, 2)):
                    start = base
                    end   = start + timedelta(hours=random.randint(4, 48))
                    # tstzrange literal for psycopg
                    avail_rows.append((gwid, f"[{start.isoformat()},{end.isoformat()})"))
                    base  = end + timedelta(days=random.randint(1, 3))

            cur.executemany(
                """
                INSERT INTO gig_availability (gig_worker_profile_id, available_window)
                VALUES (%s, %s::tstzrange)
                ON CONFLICT DO NOTHING
                """,
                avail_rows,
            )
            print(f"  gig_availabilities:  {len(avail_rows)} rows")

        # ── 3. gig_requests ────────────────────────────────────────────────
        # Guard: skip if already seeded (rerun safety)
        existing_gigs = cur.execute("SELECT count(*) FROM gig_request").fetchone()[0]
        if existing_gigs >= N_GIG_REQUESTS:
            print(f"  gig_requests:      {existing_gigs} already exist, skipping")
        else:
            gig_req_rows = []
            for i in range(N_GIG_REQUESTS):
                org_id    = random.choice(org_ids)
                city_id   = random.choice(city_ids)
                starts_at = NOW + timedelta(days=random.randint(2, 30))
                ends_at   = starts_at + timedelta(hours=random.randint(4, 72))
                pay       = round(random.randint(500, 10000) / 100) * 100
                title     = random.choice(GIG_TITLES)
                gig_req_rows.append((
                    org_id, city_id, open_gig_id,
                    f"{title} #{i + 1}",
                    f"Short-term requirement: {title.lower()}. "
                    f"Duration {int((ends_at - starts_at).total_seconds() / 3600)}h.",
                    starts_at, ends_at,
                    pay, inr_id,
                    random.randint(1, 10),   # openings
                ))

            cur.executemany(
                """
                INSERT INTO gig_request (
                    organisation_id, city_id, gig_status_id, title, description,
                    starts_at, ends_at, pay_amount, pay_currency_id, openings
                ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                """,
                gig_req_rows,
            )
            print(f"  gig_requests:        {N_GIG_REQUESTS} inserted")

        # Always fetch gig_req_ids from DB (works for both first run and rerun)
        gig_req_ids = [r[0] for r in cur.execute(
            "SELECT id FROM gig_request ORDER BY id LIMIT %s", (N_GIG_REQUESTS,)
        ).fetchall()]

        # ── 4. gig_applications (2-3 workers per request) ──────────────────
        gig_app_rows = []
        seen = set()
        for gid in gig_req_ids:
            for wid in random.sample(gig_worker_ids, min(3, len(gig_worker_ids))):
                key = (gid, wid)
                if key not in seen:
                    seen.add(key)
                    gig_app_rows.append((gid, wid, applied_gig_id))

        cur.executemany(
            """
            INSERT INTO gig_application (gig_request_id, gig_worker_profile_id, gig_application_status_id)
            VALUES (%s,%s,%s)
            ON CONFLICT (gig_request_id, gig_worker_profile_id) DO NOTHING
            """,
            gig_app_rows,
        )
        print(f"  gig_applications:    {len(gig_app_rows)} rows")

        # Cap to N_ORGS — on a re-run the DB may have more orgs from previous
        # partial runs; we only want to process the originally intended set.
        org_ids = org_ids[:N_ORGS]

        # ── 5. plans ───────────────────────────────────────────────────────
        cur.executemany(
            """
            INSERT INTO plan (code, name, price, currency_id, billing_period_months,
                              download_credits, max_seats)
            VALUES (%s,%s,%s,%s,%s,%s,%s)
            ON CONFLICT (code) DO NOTHING
            """,
            [(c, n, p, inr_id, bm, dc, ms) for c, n, p, bm, dc, ms in PLANS],
        )
        print(f"  plans:               {cur.rowcount} inserted")

        plan_rows = cur.execute("SELECT id, code, price, download_credits FROM plan").fetchall()
        plan_list = [(pid, code, price, credits) for pid, code, price, credits in plan_rows]

        # ── 6. subscriptions + payment_orders + invoices + wallets + ledger
        # Each org gets one subscription. On rerun, the EXCLUDE constraint on
        # subscription (no overlapping periods per org) will fire — we use a
        # SAVEPOINT so only the current org's attempt rolls back; all other
        # work in the transaction is preserved.
        # Commit gig/plan data first so it is durable before we start
        # the per-org loop that may partially rollback via savepoints.
        conn.commit()

        wallet_ids = {}   # org_id → wallet_id
        subs_created = 0

        for i, org_id in enumerate(org_ids):
            plan_id, plan_code, plan_price, dl_credits = random.choice(plan_list)
            period_start = NOW - timedelta(days=30)
            period_end   = NOW + timedelta(days=335)

            # ── wallet (idempotent — ON CONFLICT DO NOTHING) ──────────────
            cur.execute(
                """
                INSERT INTO wallet (organisation_id)
                VALUES (%s)
                ON CONFLICT (organisation_id) DO NOTHING
                RETURNING id
                """,
                (org_id,),
            )
            row = cur.fetchone()
            if row:
                wallet_id = row[0]
            else:
                wallet_id = cur.execute(
                    "SELECT id FROM wallet WHERE organisation_id=%s", (org_id,)
                ).fetchone()[0]
            wallet_ids[org_id] = wallet_id

            # ── subscription (may fail on rerun due to EXCLUDE constraint) ─
            # Use a SAVEPOINT so a violation only rolls back THIS org's
            # subscription attempt — not the entire transaction.
            idempotency = f"seed-pay-org-{org_id}-{uuid.uuid4().hex[:8]}"
            sub_id = None
            try:
                cur.execute("SAVEPOINT sp_sub")
                cur.execute(
                    """
                    INSERT INTO subscription
                      (organisation_id, plan_id, subscription_status_id, period_start, period_end)
                    VALUES (%s,%s,%s,%s,%s)
                    RETURNING id
                    """,
                    (org_id, plan_id, active_sub_id, period_start, period_end),
                )
                sub_id = cur.fetchone()[0]
                cur.execute("RELEASE SAVEPOINT sp_sub")
                subs_created += 1
            except psycopg.errors.ExclusionViolation:
                # Org already has an overlapping subscription — rollback only
                # this savepoint and skip to the next org.
                cur.execute("ROLLBACK TO SAVEPOINT sp_sub")
                continue

            # ── payment_order (only if we created a subscription) ─────────
            cur.execute(
                """
                INSERT INTO payment_order
                  (organisation_id, subscription_id, payment_status_id,
                   amount, currency_id, gateway_reference, idempotency_key, paid_at)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
                RETURNING id
                """,
                (org_id, sub_id, paid_pay_id, plan_price, inr_id,
                 f"gw-{uuid.uuid4().hex[:12]}", idempotency, period_start),
            )
            po_id = cur.fetchone()[0]

            # ── invoice ───────────────────────────────────────────────────
            tax    = round(float(plan_price) * 0.18, 2)
            total  = float(plan_price) + tax
            inv_no = f"INV-{org_id:08d}"
            cur.execute(
                """
                INSERT INTO invoice
                  (organisation_id, payment_order_id, invoice_status_id,
                   invoice_number, subtotal, tax_amount, total_amount, currency_id)
                  VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
                  ON CONFLICT (invoice_number) DO NOTHING
                  """,
                (org_id, po_id, issued_inv_id, inv_no, plan_price, tax, total, inr_id),
            )

            # ── wallet_ledger: credit purchase (idempotent) ──────────────
            ledger_key = f"seed-credit-{org_id}-{po_id}"
            cur.execute(
                """
                INSERT INTO wallet_ledger
                  (wallet_id, ledger_entry_type_id, credits,
                   payment_order_id, idempotency_key)
                  VALUES (%s,%s,%s,%s,%s)
                  ON CONFLICT (idempotency_key) DO NOTHING
                  """,
                (wallet_id, purchase_type_id, dl_credits, po_id, ledger_key),
            )

        print(f"  subscriptions/payments/wallets: {subs_created} new subs, {len(wallet_ids)} wallets")

        # ── 7. profile_downloads (a few sample downloads) ─────────────────
        if recruiter_rows and profile_ids and download_type_id:
            download_rows = []
            for _ in range(min(20, len(recruiter_rows))):
                rec_id, org_id = random.choice(recruiter_rows)
                cand_id = random.choice(profile_ids)
                w_id    = wallet_ids.get(org_id)
                if not w_id:
                    continue
                dl_key = f"dl:{org_id}:{cand_id}"
                # check not already downloaded
                exists = cur.execute(
                    "SELECT 1 FROM wallet_ledger WHERE idempotency_key=%s", (dl_key,)
                ).fetchone()
                if exists:
                    continue
                cur.execute(
                    """
                    INSERT INTO wallet_ledger
                      (wallet_id, ledger_entry_type_id, credits,
                       reference_table, reference_id, idempotency_key)
                    VALUES (%s,%s,%s,%s,%s,%s)
                    ON CONFLICT (idempotency_key) DO NOTHING
                    RETURNING id
                    """,
                    (w_id, download_type_id, -1,
                     "candidate_profile", cand_id, dl_key),
                )
                ledger_row = cur.fetchone()
                if ledger_row:
                    cur.execute(
                        """
                        INSERT INTO profile_download
                          (organisation_id, recruiter_id, candidate_profile_id,
                           wallet_ledger_id)
                        VALUES (%s,%s,%s,%s)
                        """,
                        (org_id, rec_id, cand_id, ledger_row[0]),
                    )
                    download_rows.append(1)
            print(f"  profile_downloads:   {len(download_rows)} rows")

    conn.commit()
    print("✓ seed_gig_billing done")


if __name__ == "__main__":
    with psycopg.connect(DSN) as conn:
        run(conn)
