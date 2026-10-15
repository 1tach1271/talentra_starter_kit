"""
seed/seed_jobs_applications.py
Seeds:
  job, job_skill, job_question,
  application, application_answer, application_history
  saved_job
"""

import random
from datetime import datetime, timedelta, timezone

import psycopg
from faker import Faker

from config import DSN, N_JOBS, APPS_PER_JOB, BATCH_SIZE

fake = Faker("en_IN")
random.seed(42)
Faker.seed(42)

NOW = datetime.now(timezone.utc)

JOB_TITLE_TEMPLATES = [
    "{role} – {city}",
    "Senior {role}",
    "Junior {role} (Fresher OK)",
    "{role} | {exp}+ Years",
    "Urgent: {role} for {industry}",
    "{role} – Remote",
    "Contract {role} – 6 Months",
]

QUESTION_TEMPLATES = [
    "How many years of {skill} experience do you have?",
    "Are you comfortable working {work_type}?",
    "What is your current notice period?",
    "Can you join within 30 days?",
    "Describe your most challenging project.",
    "What is your expected CTC in LPA?",
    "Do you have experience with {skill}?",
    "Are you open to relocation?",
]


def _id_map(cur, table, key_col="code"):
    cur.execute(f"SELECT {key_col}, id FROM {table}")
    return {r[0]: r[1] for r in cur.fetchall()}


def run(conn):
    with conn.cursor() as cur:

        # --- reference data ---
        org_ids      = [r[0] for r in cur.execute("SELECT id FROM organisation ORDER BY id").fetchall()]
        job_role_map = _id_map(cur, "job_role")
        job_role_ids = list(job_role_map.values())
        job_role_names = {v: k for k, v in job_role_map.items()}

        emp_type_ids = list(_id_map(cur, "employment_type").values())
        work_type_ids= list(_id_map(cur, "work_type").values())
        city_ids     = [r[0] for r in cur.execute("SELECT id FROM city").fetchall()]
        skill_ids    = [r[0] for r in cur.execute("SELECT id FROM skill").fetchall()]
        skill_names  = {v: k for k, v in _id_map(cur, "skill").items()}

        inr_id       = cur.execute("SELECT id FROM currency WHERE code='INR'").fetchone()[0]

        status_map   = _id_map(cur, "job_status")
        published_id = status_map.get("published")
        draft_id     = status_map.get("draft")
        closed_id    = status_map.get("closed")

        stage_rows   = cur.execute(
            "SELECT id, code, stage_order, is_terminal FROM application_stage ORDER BY stage_order"
        ).fetchall()
        stage_ids    = [r[0] for r in stage_rows]
        stage_map    = {r[0]: r for r in stage_rows}   # id → (id, code, order, is_terminal)

        profile_ids  = [r[0] for r in cur.execute("SELECT id FROM candidate_profile ORDER BY id").fetchall()]

        # job_category lookup (from 05b file)
        try:
            job_cat_ids = list(_id_map(cur, "job_category").values())
        except Exception:
            job_cat_ids = []

        industry_map  = _id_map(cur, "industry")
        ind_name_map  = {v: k for k, v in industry_map.items()}

        # --- 1. jobs ---
        job_rows = []
        for i in range(1, N_JOBS + 1):
            role_id  = random.choice(job_role_ids)
            role_name= job_role_names.get(role_id, "Engineer")
            city_id  = random.choice(city_ids)
            exp_min  = random.choice([0, 1, 2, 3, 5])
            exp_max  = exp_min + random.choice([2, 3, 5])
            sal_min  = random.randint(4, 20) * 100_000
            sal_max  = sal_min + random.randint(1, 10) * 100_000

            # 80% published, 10% draft, 10% closed
            rng = random.random()
            if rng < 0.80:
                status_id  = published_id
                pub_offset = random.randint(1, 60)
                published_at = NOW - timedelta(days=pub_offset)
                expires_at   = published_at + timedelta(days=30)
            elif rng < 0.90:
                status_id    = draft_id
                published_at = None
                expires_at   = None
            else:
                status_id    = closed_id
                published_at = NOW - timedelta(days=random.randint(30, 90))
                expires_at   = published_at + timedelta(days=30)

            template = random.choice(JOB_TITLE_TEMPLATES)
            title = (template
                     .replace("{role}", role_name.replace("_", " ").title())
                     .replace("{city}", "Bengaluru")
                     .replace("{exp}", str(exp_min))
                     .replace("{industry}", "IT"))

            row = [
                random.choice(org_ids),
                role_id,
                random.choice(emp_type_ids),
                random.choice(work_type_ids),
                status_id,
                city_id,
                title,
                sal_min,
                sal_max,
                inr_id,
                published_at,
                expires_at,
                f"We are looking for a {title}. You will work on exciting projects. "
                f"Strong communication and teamwork required.",
                exp_min,
                exp_max,
                random.randint(1, 5),       # openings
            ]

            if job_cat_ids:
                row.append(random.choice(job_cat_ids))
                row.append(random.random() > 0.7)   # is_open_to_consultants

            job_rows.append(tuple(row))

        if job_cat_ids:
            sql = """
                INSERT INTO job (
                    organisation_id, job_role_id, employment_type_id, work_type_id,
                    job_status_id, city_id, title, salary_min, salary_max,
                    salary_currency_id, published_at, expires_at, description,
                    experience_min_years, experience_max_years, openings,
                    job_category_id, is_open_to_consultants
                ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """
        else:
            sql = """
                INSERT INTO job (
                    organisation_id, job_role_id, employment_type_id, work_type_id,
                    job_status_id, city_id, title, salary_min, salary_max,
                    salary_currency_id, published_at, expires_at, description,
                    experience_min_years, experience_max_years, openings
                ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """

        for batch_start in range(0, len(job_rows), BATCH_SIZE):
            cur.executemany(sql, job_rows[batch_start: batch_start + BATCH_SIZE])

        print(f"  jobs:             {N_JOBS} inserted")

        # fetch job ids
        job_ids = [r[0] for r in cur.execute(
            "SELECT id FROM job ORDER BY id DESC LIMIT %s", (N_JOBS,)
        ).fetchall()][::-1]

        # --- 2. job_skills (3–5 skills per job) ---
        job_skill_rows = []
        seen = set()
        for jid in job_ids:
            chosen = random.sample(skill_ids, random.randint(3, 5))
            for idx, sid in enumerate(chosen):
                key = (jid, sid)
                if key not in seen:
                    seen.add(key)
                    job_skill_rows.append((jid, sid, idx < 2))   # first 2 are mandatory

        for batch_start in range(0, len(job_skill_rows), BATCH_SIZE):
            cur.executemany(
                """
                INSERT INTO job_skill (job_id, skill_id, is_mandatory)
                VALUES (%s,%s,%s)
                ON CONFLICT (job_id, skill_id) DO NOTHING
                """,
                job_skill_rows[batch_start: batch_start + BATCH_SIZE],
            )
        print(f"  job_skills:       {len(job_skill_rows)} rows")

        # --- 3. job_questions (1–2 per job) ---
        question_rows = []
        for jid in job_ids:
            n_q = random.randint(1, 2)
            for order, tmpl in enumerate(random.sample(QUESTION_TEMPLATES, n_q)):
                q = (tmpl
                     .replace("{skill}", random.choice(list(skill_names.values())))
                     .replace("{work_type}", "remote"))
                question_rows.append((jid, q, order == 0, order))

        for batch_start in range(0, len(question_rows), BATCH_SIZE):
            cur.executemany(
                """
                INSERT INTO job_question (job_id, question_text, is_required, display_order)
                VALUES (%s,%s,%s,%s)
                """,
                question_rows[batch_start: batch_start + BATCH_SIZE],
            )
        print(f"  job_questions:    {len(question_rows)} rows")

        # --- 4. applications ---
        # fetch question ids per job
        cur.execute("SELECT job_id, id FROM job_question")
        q_by_job = {}
        for jid, qid in cur.fetchall():
            q_by_job.setdefault(jid, []).append(qid)

        # weighted stage distribution
        stage_weights = [40, 20, 15, 10, 8, 5, 2][:len(stage_ids)]
        application_rows = []
        seen_pairs       = set()

        for jid in job_ids:
            pool = random.sample(profile_ids, min(APPS_PER_JOB, len(profile_ids)))
            for pid in pool:
                key = (jid, pid)
                if key in seen_pairs:
                    continue
                seen_pairs.add(key)
                stage_id   = random.choices(stage_ids, weights=stage_weights[:len(stage_ids)])[0]
                applied_at = NOW - timedelta(days=random.randint(1, 60),
                                             hours=random.randint(0, 23))
                application_rows.append((jid, pid, stage_id, applied_at))

        # disable the history trigger during bulk insert (same pattern as 10_seed.sql)
        cur.execute("ALTER TABLE application DISABLE TRIGGER trg_application_history")

        for batch_start in range(0, len(application_rows), BATCH_SIZE):
            cur.executemany(
                """
                INSERT INTO application (job_id, candidate_profile_id, application_stage_id, applied_at)
                VALUES (%s,%s,%s,%s)
                """,
                application_rows[batch_start: batch_start + BATCH_SIZE],
            )

        cur.execute("ALTER TABLE application ENABLE TRIGGER trg_application_history")
        print(f"  applications:     {len(application_rows)} rows")

        # fetch app ids
        cur.execute("SELECT id, job_id, candidate_profile_id, application_stage_id, applied_at FROM application")
        app_rows_db = cur.fetchall()

        # --- 5. application_history (one initial row per application) ---
        hist_rows = [
            (app_id, None, stage_id, applied_at)
            for app_id, _jid, _pid, stage_id, applied_at in app_rows_db
        ]
        for batch_start in range(0, len(hist_rows), BATCH_SIZE):
            cur.executemany(
                """
                INSERT INTO application_history
                  (application_id, from_stage_id, to_stage_id, changed_at)
                VALUES (%s,%s,%s,%s)
                """,
                hist_rows[batch_start: batch_start + BATCH_SIZE],
            )
        print(f"  application_history:{len(hist_rows)} rows")

        # --- 6. application_answers ---
        answer_rows = []
        for app_id, jid, pid, stage_id, applied_at in app_rows_db:
            for qid in q_by_job.get(jid, []):
                answer_rows.append((
                    app_id, qid,
                    random.choice([
                        "Yes, I have the required experience.",
                        "I can join within 2 weeks.",
                        "3 years of relevant experience.",
                        "I am open to relocation.",
                        "My expected CTC is 12 LPA.",
                        "I work well in a team environment.",
                    ])
                ))

        for batch_start in range(0, len(answer_rows), BATCH_SIZE):
            cur.executemany(
                """
                INSERT INTO application_answer (application_id, job_question_id, answer_text)
                VALUES (%s,%s,%s)
                ON CONFLICT (application_id, job_question_id) DO NOTHING
                """,
                answer_rows[batch_start: batch_start + BATCH_SIZE],
            )
        print(f"  application_answers:{len(answer_rows)} rows")

        # --- 7. saved_jobs (10% of candidates save a random job) ---
        saved_rows = []
        seen = set()
        sample_profiles = random.sample(profile_ids, max(1, len(profile_ids) // 10))
        for pid in sample_profiles:
            for jid in random.sample(job_ids, min(3, len(job_ids))):
                key = (pid, jid)
                if key not in seen:
                    seen.add(key)
                    saved_rows.append((pid, jid))

        cur.executemany(
            """
            INSERT INTO saved_job (candidate_profile_id, job_id)
            VALUES (%s,%s)
            ON CONFLICT (candidate_profile_id, job_id) DO NOTHING
            """,
            saved_rows,
        )
        print(f"  saved_jobs:       {len(saved_rows)} rows")

    conn.commit()
    print("✓ seed_jobs_applications done")


if __name__ == "__main__":
    with psycopg.connect(DSN) as conn:
        run(conn)
