"""
seed/seed_jobs_applications.py
Seeds:
  job, job_skill, job_question,
  application, application_answer, application_history
  saved_job

Memory strategy for 100 K jobs × 50 apps = ~5 M applications
──────────────────────────────────────────────────────────────
The old approach built:
  • a single `seen_pairs` set  (~5 M entries ≈ 400 MB)
  • a single `application_rows` list (~5 M tuples)
  • fetched ALL 5 M app rows back from Postgres for history/answers

All three caused OOM at hackathon scale.

New approach — process jobs in chunks of JOB_CHUNK_SIZE:
  1. For each job chunk:  generate applications → INSERT … ON CONFLICT DO NOTHING
     (the DB unique constraint replaces the in-memory seen_pairs set)
  2. Fetch back only the app ids for the jobs in THIS chunk
  3. Write application_history and application_answers for this chunk
  4. Commit → free memory → next chunk

Peak RAM is now  JOB_CHUNK_SIZE × APPS_PER_JOB × row_size
                 ≈ 1 000 × 50 × ~200 B ≈ ~10 MB per chunk.
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

# Number of jobs to process per outer loop iteration.
JOB_CHUNK_SIZE = 1_000

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

        # --- reference data (small — safe to load once) ---
        org_ids       = [r[0] for r in cur.execute("SELECT id FROM organisation ORDER BY id").fetchall()]
        job_role_map  = _id_map(cur, "job_role")
        job_role_ids  = list(job_role_map.values())
        job_role_names= {v: k for k, v in job_role_map.items()}

        emp_type_ids  = list(_id_map(cur, "employment_type").values())
        work_type_ids = list(_id_map(cur, "work_type").values())
        city_ids      = [r[0] for r in cur.execute("SELECT id FROM city").fetchall()]
        skill_ids     = [r[0] for r in cur.execute("SELECT id FROM skill").fetchall()]
        skill_names   = {v: k for k, v in _id_map(cur, "skill").items()}

        inr_id        = cur.execute("SELECT id FROM currency WHERE code='INR'").fetchone()[0]

        status_map    = _id_map(cur, "job_status")
        published_id  = status_map.get("published")
        draft_id      = status_map.get("draft")
        closed_id     = status_map.get("closed")

        stage_rows    = cur.execute(
            "SELECT id, code, stage_order, is_terminal FROM application_stage ORDER BY stage_order"
        ).fetchall()
        stage_ids     = [r[0] for r in stage_rows]

        # Load profile_ids once — just IDs (integers), ~8 MB for 1 M rows.
        profile_ids   = [r[0] for r in cur.execute("SELECT id FROM candidate_profile ORDER BY id").fetchall()]

        try:
            job_cat_ids = list(_id_map(cur, "job_category").values())
        except Exception:
            job_cat_ids = []

        # Weighted stage distribution for applications.
        stage_weights = [40, 20, 15, 10, 8, 5, 2][: len(stage_ids)]

        # ─────────────────────────────────────────────────────────────────────
        # 1. jobs  — insert all job rows first (100 K rows is manageable as a
        #    single pass; each row is tiny).
        # ─────────────────────────────────────────────────────────────────────
        if job_cat_ids:
            job_sql = """
                INSERT INTO job (
                    organisation_id, job_role_id, employment_type_id, work_type_id,
                    job_status_id, city_id, title, salary_min, salary_max,
                    salary_currency_id, published_at, expires_at, description,
                    experience_min_years, experience_max_years, openings,
                    job_category_id, is_open_to_consultants
                ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """
        else:
            job_sql = """
                INSERT INTO job (
                    organisation_id, job_role_id, employment_type_id, work_type_id,
                    job_status_id, city_id, title, salary_min, salary_max,
                    salary_currency_id, published_at, expires_at, description,
                    experience_min_years, experience_max_years, openings
                ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """

        job_rows = []
        for i in range(1, N_JOBS + 1):
            role_id   = random.choice(job_role_ids)
            role_name = job_role_names.get(role_id, "Engineer")
            exp_min   = random.choice([0, 1, 2, 3, 5])
            exp_max   = exp_min + random.choice([2, 3, 5])
            sal_min   = random.randint(4, 20) * 100_000
            sal_max   = sal_min + random.randint(1, 10) * 100_000

            rng = random.random()
            if rng < 0.80:
                status_id    = published_id
                published_at = NOW - timedelta(days=random.randint(1, 60))
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
                random.choice(city_ids),
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
                random.randint(1, 5),
            ]
            if job_cat_ids:
                row.append(random.choice(job_cat_ids))
                row.append(random.random() > 0.7)

            job_rows.append(tuple(row))

        for batch_start in range(0, len(job_rows), BATCH_SIZE):
            cur.executemany(job_sql, job_rows[batch_start: batch_start + BATCH_SIZE])

        conn.commit()
        del job_rows  # free memory before the next phase
        print(f"  jobs:             {N_JOBS} inserted")

        # Fetch job ids in insertion order.
        job_ids = [r[0] for r in cur.execute(
            "SELECT id FROM job ORDER BY id DESC LIMIT %s", (N_JOBS,)
        ).fetchall()][::-1]

        # ─────────────────────────────────────────────────────────────────────
        # 2. job_skills (3–5 skills per job) — still a single pass (100 K × 5
        #    = 500 K rows, each tiny).
        # ─────────────────────────────────────────────────────────────────────
        job_skill_rows = []
        seen = set()
        for jid in job_ids:
            chosen = random.sample(skill_ids, random.randint(3, 5))
            for idx, sid in enumerate(chosen):
                key = (jid, sid)
                if key not in seen:
                    seen.add(key)
                    job_skill_rows.append((jid, sid, idx < 2))

        for batch_start in range(0, len(job_skill_rows), BATCH_SIZE):
            cur.executemany(
                """
                INSERT INTO job_skill (job_id, skill_id, is_mandatory)
                VALUES (%s,%s,%s)
                ON CONFLICT (job_id, skill_id) DO NOTHING
                """,
                job_skill_rows[batch_start: batch_start + BATCH_SIZE],
            )
        conn.commit()
        del job_skill_rows, seen
        print(f"  job_skills:       inserted")

        # ─────────────────────────────────────────────────────────────────────
        # 3. job_questions (1–2 per job) — 100–200 K rows, tiny.
        # ─────────────────────────────────────────────────────────────────────
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
        conn.commit()
        del question_rows
        print(f"  job_questions:    inserted")

        # Build a question-id lookup (job_id → [question_ids]).
        # This fits in RAM: max 2 qids × 100 K jobs = 200 K integers.
        cur.execute("SELECT job_id, id FROM job_question")
        q_by_job: dict[int, list[int]] = {}
        for jid, qid in cur.fetchall():
            q_by_job.setdefault(jid, []).append(qid)

        # ─────────────────────────────────────────────────────────────────────
        # 4–6. applications, application_history, application_answers
        #
        # Process JOB_CHUNK_SIZE jobs at a time:
        #   • Generate application rows for the chunk
        #   • INSERT with ON CONFLICT DO NOTHING (DB enforces uniqueness —
        #     no in-memory seen_pairs set needed)
        #   • Disable the history trigger during bulk insert, re-enable after
        #   • Fetch back app ids for this chunk only
        #   • Write history + answers for this chunk
        #   • Commit and move on
        # ─────────────────────────────────────────────────────────────────────
        total_apps = 0

        cur.execute("ALTER TABLE application DISABLE TRIGGER trg_application_history")

        for chunk_start in range(0, len(job_ids), JOB_CHUNK_SIZE):
            job_chunk = job_ids[chunk_start: chunk_start + JOB_CHUNK_SIZE]

            if chunk_start % 10_000 == 0:
                print(f"  ... applications chunk {chunk_start}/{N_JOBS}")

            # --- generate application rows for this job chunk ---
            # Use a per-chunk seen_pairs set to avoid duplicates within the chunk.
            # Memory cost: JOB_CHUNK_SIZE * APPS_PER_JOB = 1000 * 50 = 50K pairs max.
            chunk_seen: set[tuple[int, int]] = set()
            app_rows: list[tuple] = []
            for jid in job_chunk:
                pool = random.sample(profile_ids, min(APPS_PER_JOB, len(profile_ids)))
                for pid in pool:
                    key = (jid, pid)
                    if key in chunk_seen:
                        continue
                    chunk_seen.add(key)
                    stage_id   = random.choices(stage_ids, weights=stage_weights[: len(stage_ids)])[0]
                    applied_at = NOW - timedelta(days=random.randint(1, 60),
                                                 hours=random.randint(0, 23))
                    app_rows.append((jid, pid, stage_id, applied_at))

            for batch_start in range(0, len(app_rows), BATCH_SIZE):
                cur.executemany(
                    """
                    INSERT INTO application (job_id, candidate_profile_id, application_stage_id, applied_at)
                    VALUES (%s,%s,%s,%s)
                    ON CONFLICT (job_id, candidate_profile_id) WHERE deleted_at IS NULL DO NOTHING
                    """,
                    app_rows[batch_start: batch_start + BATCH_SIZE],
                )

            # --- fetch back the inserted app rows for THIS chunk ---
            cur.execute(
                """
                SELECT id, job_id, candidate_profile_id, application_stage_id, applied_at
                FROM application
                WHERE job_id = ANY(%s)
                """,
                (job_chunk,),
            )
            chunk_apps = cur.fetchall()
            total_apps += len(chunk_apps)

            # --- application_history (one initial row per application) ---
            hist_rows = [
                (app_id, None, stage_id, applied_at)
                for app_id, _jid, _pid, stage_id, applied_at in chunk_apps
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

            # --- application_answers ---
            answer_rows = []
            for app_id, jid, _pid, _stage_id, _applied_at in chunk_apps:
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

            conn.commit()

        cur.execute("ALTER TABLE application ENABLE TRIGGER trg_application_history")
        conn.commit()

        print(f"  applications:       {total_apps} rows")
        print(f"  application_history:{total_apps} rows")
        print(f"  application_answers: inserted")

        # ─────────────────────────────────────────────────────────────────────
        # 7. saved_jobs (10 % of candidates save up to 3 random jobs each)
        #    Candidate sample is small enough to handle in one pass.
        # ─────────────────────────────────────────────────────────────────────
        with conn.cursor() as cur2:
            profile_sample = [r[0] for r in cur2.execute(
                "SELECT id FROM candidate_profile ORDER BY random() LIMIT %s",
                (max(1, len(profile_ids) // 10),),
            ).fetchall()]

        saved_rows = []
        seen_saved: set[tuple[int, int]] = set()
        for pid in profile_sample:
            for jid in random.sample(job_ids, min(3, len(job_ids))):
                key = (pid, jid)
                if key not in seen_saved:
                    seen_saved.add(key)
                    saved_rows.append((pid, jid))
            if len(saved_rows) >= BATCH_SIZE:
                with conn.cursor() as cur3:
                    cur3.executemany(
                        """
                        INSERT INTO saved_job (candidate_profile_id, job_id)
                        VALUES (%s,%s)
                        ON CONFLICT (candidate_profile_id, job_id) DO NOTHING
                        """,
                        saved_rows,
                    )
                conn.commit()
                saved_rows = []

        if saved_rows:
            with conn.cursor() as cur3:
                cur3.executemany(
                    """
                    INSERT INTO saved_job (candidate_profile_id, job_id)
                    VALUES (%s,%s)
                    ON CONFLICT (candidate_profile_id, job_id) DO NOTHING
                    """,
                    saved_rows,
                )
            conn.commit()

        print(f"  saved_jobs:         inserted")

    print("✓ seed_jobs_applications done")


if __name__ == "__main__":
    with psycopg.connect(DSN) as conn:
        run(conn)
