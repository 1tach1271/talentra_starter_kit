"""
seed/seed_users_orgs.py
Seeds:
  app_role, permission, role_permission,
  app_user (system + recruiters + an admin),
  organisation, recruiter, app_user_role
"""

import random
import psycopg
from faker import Faker

from config import DSN, N_ORGS, BATCH_SIZE

fake = Faker("en_IN")
random.seed(42)
Faker.seed(42)

# ── Static lookup data ────────────────────────────────────────────────────────

ROLES = [
    ("admin",      "Administrator"),
    ("recruiter",  "Recruiter"),
    ("candidate",  "Candidate"),
    ("gig_worker", "Gig Worker"),
    ("support",    "Support Agent"),
    ("tpo",        "Placement Officer"),
    ("consultant", "Consultant"),
]

PERMISSIONS = [
    ("profile.read",         "Read candidate profiles"),
    ("profile.download",     "Download candidate profiles"),
    ("job.write",            "Create and edit jobs"),
    ("application.manage",   "Manage applications"),
    ("billing.manage",       "Manage billing"),
    ("user.manage",          "Manage users"),
    ("sourcing.manage",      "Manage sourcing requests"),
    ("gig.manage",           "Manage gig requests"),
    ("report.read",          "View analytics reports"),
]

# role_code → list of permission_codes it gets
ROLE_PERMISSIONS = {
    "admin":      [p[0] for p in PERMISSIONS],   # all
    "recruiter":  ["profile.read", "profile.download", "job.write",
                   "application.manage", "sourcing.manage"],
    "tpo":        ["profile.read", "job.write", "application.manage"],
    "consultant": ["profile.read", "sourcing.manage"],
    "support":    ["profile.read"],
    "candidate":  [],
    "gig_worker": [],
}

ORG_TYPES     = ["employer", "consultancy", "agency"]      # codes must exist in org_type table
VERIFY_STATUS = ["pending", "verified", "rejected"]        # codes in verification_status table

COMPANY_SUFFIXES = [
    "Technologies", "Solutions", "Systems", "Consulting", "Ventures",
    "Innovations", "Enterprises", "Group", "Labs", "Services",
]


# ── Helpers ──────────────────────────────────────────────────────────────────

def _id_map(cur, table: str, key_col: str = "code") -> dict:
    cur.execute(f"SELECT {key_col}, id FROM {table}")
    return {row[0]: row[1] for row in cur.fetchall()}


# ── Seeder ───────────────────────────────────────────────────────────────────

def run(conn):
    with conn.cursor() as cur:

        # 1. roles
        cur.executemany(
            """
            INSERT INTO app_role (code, name)
            VALUES (%s, %s)
            ON CONFLICT (code) DO NOTHING
            """,
            ROLES,
        )
        print(f"  app_roles:      {cur.rowcount} inserted")

        # 2. permissions
        cur.executemany(
            """
            INSERT INTO permission (code, name)
            VALUES (%s, %s)
            ON CONFLICT (code) DO NOTHING
            """,
            PERMISSIONS,
        )
        print(f"  permissions:    {cur.rowcount} inserted")

        # 3. role_permissions
        role_ids = _id_map(cur, "app_role")
        perm_ids = _id_map(cur, "permission")

        rp_rows = [
            (role_ids[rc], perm_ids[pc])
            for rc, pcs in ROLE_PERMISSIONS.items()
            for pc in pcs
            if rc in role_ids and pc in perm_ids
        ]
        cur.executemany(
            """
            INSERT INTO role_permission (app_role_id, permission_id)
            VALUES (%s, %s)
            ON CONFLICT (app_role_id, permission_id) DO NOTHING
            """,
            rp_rows,
        )
        print(f"  role_permissions:{cur.rowcount} inserted")

        # 4. fetch reference id maps needed later
        country_ids    = _id_map(cur, "country", "iso2")
        industry_ids   = _id_map(cur, "industry")
        city_ids_rows  = cur.execute("SELECT name, id FROM city").fetchall()
        city_name_ids  = {r[0]: r[1] for r in city_ids_rows}

        # org_type and verification_status come from sp_create_lookup tables
        org_type_ids    = _id_map(cur, "org_type")
        verify_stat_ids = _id_map(cur, "verification_status")

        industry_list  = list(industry_ids.values())
        city_list      = list(city_name_ids.values())
        india_id       = country_ids.get("IN")

        # 5. organisations + one recruiter app_user per org
        # Guard: if we already have >= N_ORGS organisations (from a previous
        # partial run), skip insertion entirely and reuse the existing rows.
        existing_org_count = cur.execute("SELECT count(*) FROM organisation").fetchone()[0]
        if existing_org_count >= N_ORGS:
            print(f"  organisations:  {existing_org_count} already exist, skipping insert")
            cur.execute("SELECT id FROM organisation ORDER BY id LIMIT %s", (N_ORGS,))
            org_ids = [r[0] for r in cur.fetchall()]
        else:
            org_rows = []
            for i in range(1, N_ORGS + 1):
                company = f"{fake.last_name()} {random.choice(COMPANY_SUFFIXES)}"
                org_type = random.choice(ORG_TYPES)
                verify   = random.choice(VERIFY_STATUS)
                org_rows.append((
                    company,
                    f"{company} Pvt Ltd",
                    india_id,
                    random.choice(industry_list),
                    org_type_ids.get(org_type),
                    verify_stat_ids.get(verify),
                    f"https://www.{company.lower().replace(' ', '')}.com",
                ))

            cur.executemany(
                """
                INSERT INTO organisation
                  (name, legal_name, country_id, industry_id,
                   org_type_id, verification_status_id, website)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                """,
                org_rows,
            )
            print(f"  organisations:  {N_ORGS} inserted")

            # fetch the org ids we just inserted (in insertion order)
            cur.execute(
                "SELECT id FROM organisation ORDER BY id DESC LIMIT %s",
                (N_ORGS,),
            )
            org_ids = [r[0] for r in cur.fetchall()][::-1]   # oldest first

        # 6. admin app_user
        cur.execute(
            """
            INSERT INTO app_user (email, display_name)
            VALUES ('admin@talentra.local', 'Admin User')
            ON CONFLICT DO NOTHING
            RETURNING id
            """
        )
        row = cur.fetchone()
        if row:
            admin_id = row[0]
            admin_role_id = role_ids.get("admin")
            if admin_role_id:
                cur.execute(
                    """
                    INSERT INTO app_user_role (app_user_id, app_role_id)
                    VALUES (%s, %s)
                    ON CONFLICT DO NOTHING
                    """,
                    (admin_id, admin_role_id),
                )

        # 7. recruiter app_users + recruiter rows + user_roles
        rec_user_rows = []
        for i, org_id in enumerate(org_ids):
            name  = fake.name()
            email = f"recruiter{i + 1}@talentra-seed.com"
            rec_user_rows.append((email, name))

        cur.executemany(
            """
            INSERT INTO app_user (email, display_name)
            VALUES (%s, %s)
            ON CONFLICT DO NOTHING
            """,
            rec_user_rows,
        )

        # fetch their ids
        emails = [r[0] for r in rec_user_rows]
        cur.execute(
            "SELECT id FROM app_user WHERE email = ANY(%s) ORDER BY id",
            (emails,),
        )
        rec_user_ids = [r[0] for r in cur.fetchall()]

        recruiter_rows = []
        user_role_rows = []
        rec_role_id    = role_ids.get("recruiter")

        for uid, org_id in zip(rec_user_ids, org_ids):
            recruiter_rows.append((uid, org_id, fake.job()))
            if rec_role_id:
                user_role_rows.append((uid, rec_role_id, org_id))

        cur.executemany(
            """
            INSERT INTO recruiter (app_user_id, organisation_id, job_title)
            VALUES (%s, %s, %s)
            ON CONFLICT DO NOTHING
            """,
            recruiter_rows,
        )
        print(f"  recruiters:     {cur.rowcount} inserted")

        cur.executemany(
            """
            INSERT INTO app_user_role (app_user_id, app_role_id, organisation_id)
            VALUES (%s, %s, %s)
            ON CONFLICT DO NOTHING
            """,
            user_role_rows,
        )
        print(f"  user_roles:     {cur.rowcount} inserted")

    conn.commit()
    print("✓ seed_users_orgs done")


if __name__ == "__main__":
    with psycopg.connect(DSN) as conn:
        run(conn)
