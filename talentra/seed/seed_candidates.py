"""
seed/seed_candidates.py
Seeds:
  app_user (candidates), candidate_profile,
  candidate_education, candidate_experience,
  candidate_skill, candidate_language,
  resume_version

Memory strategy for 1 M rows
─────────────────────────────
At 1 M candidates the old approach of building user_rows / profile_rows /
edu_rows etc. entirely in memory before inserting caused OOM.

Instead we now process CHUNK_SIZE candidates at a time:
  1. Generate a chunk of user rows  → INSERT → commit
  2. Fetch back the profile_ids for exactly that chunk (by email range)
  3. Generate and insert derived rows (edu / exp / skill / lang / resume)
     for that same chunk immediately, then free the memory before the next
     chunk starts.

This keeps peak RSS to roughly:
  CHUNK_SIZE × avg_bytes_per_candidate  ≈  10 000 × ~2 KB  ≈  ~20 MB
instead of  1 000 000 × ~2 KB ≈ 2 GB.
"""

import random
from datetime import date, timedelta

import psycopg
from faker import Faker

from config import DSN, N_CANDIDATES, BATCH_SIZE

fake = Faker(["en_IN", "hi_IN"])
random.seed(42)
Faker.seed(42)

# Process this many candidates per outer loop iteration to bound RAM usage.
CHUNK_SIZE = 10_000

FIRST_NAMES = [
    "Aarav", "Priya", "Ravi", "Meera", "Arjun", "Divya", "Kiran", "Sneha",
    "Vikram", "Ananya", "Rohan", "Pooja", "Siddharth", "Kavya", "Amit",
    "Neha", "Rahul", "Shruti", "Aditya", "Swati", "Mohammed", "Fatima",
    "Suresh", "Lakshmi", "Ganesh", "Parvathi", "Deepak", "Rekha", "Nikhil",
    "Anita", "Rajesh", "Sunita", "Manoj", "Geeta", "Vinod", "Seema",
]

LAST_NAMES = [
    "Sharma", "Iyer", "Reddy", "Nair", "Singh", "Patel", "Khan", "Das",
    "Gupta", "Verma", "Mehta", "Joshi", "Kumar", "Rao", "Pillai", "Naidu",
    "Mukherjee", "Chatterjee", "Bose", "Sen", "Mishra", "Tiwari", "Pandey",
    "Dubey", "Srivastava", "Agarwal", "Bansal", "Goel", "Saxena", "Kapoor",
]

HEADLINES = [
    "Software Engineer with {} years of experience",
    "Full Stack Developer | {} years exp",
    "Data Scientist passionate about ML | {} yrs",
    "DevOps Engineer | {} years in cloud infra",
    "Product Manager | {} years driving growth",
    "Backend Developer specialising in Python | {} yrs",
    "Frontend Developer | React & Vue | {} years",
    "QA Engineer | {} years ensuring quality",
    "Business Analyst | {} years in FinTech",
    "ML Engineer | {} yrs | NLP & CV",
]


def _id_map(cur, table, key_col="code"):
    cur.execute(f"SELECT {key_col}, id FROM {table}")
    return {r[0]: r[1] for r in cur.fetchall()}


def _rand_date(start_year=2000, end_year=2022):
    start = date(start_year, 1, 1)
    end   = date(end_year,   12, 31)
    return start + timedelta(days=random.randint(0, (end - start).days))


def _insert_education(cur, profile_ids, qual_ids):
    """Generate and insert candidate_education for the given profile_ids chunk."""
    edu_rows = []
    for pid in profile_ids:
        n_edu = random.randint(1, 2)
        start = _rand_date(2005, 2015)
        for _ in range(n_edu):
            end = start + timedelta(days=random.randint(365 * 2, 365 * 4))
            edu_rows.append((
                pid,
                random.choice(qual_ids),
                f"{fake.last_name()} University",
                random.choice(["Computer Science", "Engineering", "Business",
                               "Mathematics", "Physics", "Commerce", "Arts"]),
                start,
                end if end <= date.today() else None,
                f"{random.randint(55, 95)}%",
            ))
            start = end + timedelta(days=30)
            if len(edu_rows) >= BATCH_SIZE:
                cur.executemany(
                    """
                    INSERT INTO candidate_education
                      (candidate_profile_id, qualification_id, institution,
                       field_of_study, start_date, end_date, grade)
                    VALUES (%s,%s,%s,%s,%s,%s,%s)
                    """,
                    edu_rows,
                )
                edu_rows = []
    if edu_rows:
        cur.executemany(
            """
            INSERT INTO candidate_education
              (candidate_profile_id, qualification_id, institution,
               field_of_study, start_date, end_date, grade)
            VALUES (%s,%s,%s,%s,%s,%s,%s)
            """,
            edu_rows,
        )


def _insert_experience(cur, profile_ids, job_role_ids, emp_type_ids):
    """Generate and insert candidate_experience for the given profile_ids chunk."""
    exp_rows = []
    for pid in profile_ids:
        n_exp = random.randint(0, 3)
        start = _rand_date(2015, 2021)
        for j in range(n_exp):
            is_current = (j == n_exp - 1) and random.random() > 0.3
            end = None if is_current else start + timedelta(
                days=random.randint(180, 365 * 3)
            )
            exp_rows.append((
                pid,
                random.choice(job_role_ids),
                random.choice(emp_type_ids),
                fake.company(),
                fake.job(),
                start,
                end,
                is_current,
                f"Worked on {fake.bs()}.",
            ))
            if end:
                start = end + timedelta(days=random.randint(7, 60))
            if len(exp_rows) >= BATCH_SIZE:
                cur.executemany(
                    """
                    INSERT INTO candidate_experience
                      (candidate_profile_id, job_role_id, employment_type_id,
                       employer_name, job_title, start_date, end_date,
                       is_current, description)
                    VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
                    """,
                    exp_rows,
                )
                exp_rows = []
    if exp_rows:
        cur.executemany(
            """
            INSERT INTO candidate_experience
              (candidate_profile_id, job_role_id, employment_type_id,
               employer_name, job_title, start_date, end_date,
               is_current, description)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """,
            exp_rows,
        )


def _insert_skills(cur, profile_ids, skill_ids, proficiency_ids):
    """Generate and insert candidate_skill for the given profile_ids chunk."""
    skill_rows = []
    for pid in profile_ids:
        n_skills = random.randint(3, 8)
        chosen   = random.sample(skill_ids, min(n_skills, len(skill_ids)))
        for sid in chosen:
            skill_rows.append((
                pid, sid,
                random.choice(proficiency_ids) if proficiency_ids else None,
                round(random.uniform(0.5, 8.0), 1),
            ))
        if len(skill_rows) >= BATCH_SIZE:
            cur.executemany(
                """
                INSERT INTO candidate_skill
                  (candidate_profile_id, skill_id, skill_proficiency_id, years_experience)
                VALUES (%s,%s,%s,%s)
                ON CONFLICT (candidate_profile_id, skill_id) DO NOTHING
                """,
                skill_rows,
            )
            skill_rows = []
    if skill_rows:
        cur.executemany(
            """
            INSERT INTO candidate_skill
              (candidate_profile_id, skill_id, skill_proficiency_id, years_experience)
            VALUES (%s,%s,%s,%s)
            ON CONFLICT (candidate_profile_id, skill_id) DO NOTHING
            """,
            skill_rows,
        )


def _insert_languages(cur, profile_ids, lang_ids, proficiency_ids):
    """Generate and insert candidate_language for the given profile_ids chunk."""
    lang_rows = []
    for pid in profile_ids:
        chosen = random.sample(lang_ids, min(random.randint(1, 3), len(lang_ids)))
        for lid in chosen:
            lang_rows.append((
                pid, lid,
                random.choice(proficiency_ids) if proficiency_ids else None,
            ))
        if len(lang_rows) >= BATCH_SIZE:
            cur.executemany(
                """
                INSERT INTO candidate_language
                  (candidate_profile_id, language_id, skill_proficiency_id)
                VALUES (%s,%s,%s)
                ON CONFLICT (candidate_profile_id, language_id) DO NOTHING
                """,
                lang_rows,
            )
            lang_rows = []
    if lang_rows:
        cur.executemany(
            """
            INSERT INTO candidate_language
              (candidate_profile_id, language_id, skill_proficiency_id)
            VALUES (%s,%s,%s)
            ON CONFLICT (candidate_profile_id, language_id) DO NOTHING
            """,
            lang_rows,
        )


def _insert_resumes(cur, profile_ids):
    """Insert one resume_version per candidate in the given profile_ids chunk."""
    resume_rows = [
        (pid, 1, f"resumes/candidate_{pid}_v1.pdf", True)
        for pid in profile_ids
    ]
    for batch_start in range(0, len(resume_rows), BATCH_SIZE):
        cur.executemany(
            """
            INSERT INTO resume_version
              (candidate_profile_id, version_no, file_reference, is_primary)
            VALUES (%s,%s,%s,%s)
            ON CONFLICT (candidate_profile_id, version_no) DO NOTHING
            """,
            resume_rows[batch_start: batch_start + BATCH_SIZE],
        )


def run(conn):
    with conn.cursor() as cur:

        # --- reference maps (tiny — safe to load once) ---
        skill_ids       = list(_id_map(cur, "skill").values())
        qual_ids        = list(_id_map(cur, "qualification").values())
        lang_ids        = list(_id_map(cur, "language").values())
        job_role_ids    = list(_id_map(cur, "job_role").values())
        emp_type_ids    = list(_id_map(cur, "employment_type").values())
        city_ids        = list({r[0] for r in cur.execute("SELECT id FROM city").fetchall()})
        proficiency_ids = list(_id_map(cur, "skill_proficiency").values())

        inr_id = cur.execute(
            "SELECT id FROM currency WHERE code='INR'"
        ).fetchone()[0]

        # ─────────────────────────────────────────────────────────────────────
        # Process N_CANDIDATES in chunks of CHUNK_SIZE to keep RAM bounded.
        # For each chunk we:
        #   (a) insert app_user rows
        #   (b) fetch back the new user ids by email
        #   (c) insert candidate_profile rows
        #   (d) fetch back the new profile ids
        #   (e) insert all derived rows (edu / exp / skill / lang / resume)
        #   (f) commit — memory for this chunk is now released
        # ─────────────────────────────────────────────────────────────────────

        total_profiles = 0

        for chunk_start in range(0, N_CANDIDATES, CHUNK_SIZE):
            chunk_end = min(chunk_start + CHUNK_SIZE, N_CANDIDATES)
            # i is 1-based candidate index
            chunk_indices = range(chunk_start + 1, chunk_end + 1)

            # progress every 100 000 candidates
            if chunk_start % 100_000 == 0:
                print(f"  ... {chunk_start}/{N_CANDIDATES}")

            # ── (a) app_user rows ──────────────────────────────────────────
            user_rows = []
            for i in chunk_indices:
                fname = random.choice(FIRST_NAMES)
                lname = random.choice(LAST_NAMES)
                name  = f"{fname} {lname}"
                email = f"candidate{i}@talentra-seed.com"
                user_rows.append((email, name))

            for batch_start in range(0, len(user_rows), BATCH_SIZE):
                cur.executemany(
                    "INSERT INTO app_user (email, display_name) VALUES (%s, %s) ON CONFLICT DO NOTHING",
                    user_rows[batch_start: batch_start + BATCH_SIZE],
                )

            # ── (b) fetch new user ids ─────────────────────────────────────
            emails = [r[0] for r in user_rows]
            cur.execute(
                "SELECT id, email FROM app_user WHERE email = ANY(%s) ORDER BY id",
                (emails,),
            )
            user_map  = {email: uid for uid, email in cur.fetchall()}
            user_ids  = [user_map[e] for e in emails if e in user_map]

            # ── (c) candidate_profile rows ─────────────────────────────────
            profile_rows = []
            for seq, (i, uid) in enumerate(zip(chunk_indices, user_ids)):
                fname      = random.choice(FIRST_NAMES)
                lname      = random.choice(LAST_NAMES)
                exp_months = random.randint(0, 180)
                exp_years  = exp_months // 12
                headline   = random.choice(HEADLINES).format(exp_years or "< 1")
                salary     = random.randint(3, 50) * 100_000
                dob        = _rand_date(1985, 2000)
                profile_rows.append((
                    uid,
                    f"{fname} {lname}",
                    headline,
                    f"+91{random.randint(7000000000, 9999999999)}",
                    random.choice(city_ids),
                    exp_months,
                    f"p{i}@talentra-seed.com",
                    dob,
                    random.choice(lang_ids),
                    salary,
                    inr_id,
                    random.randint(0, 90),
                    random.random() > 0.3,
                ))

            for batch_start in range(0, len(profile_rows), BATCH_SIZE):
                cur.executemany(
                    """
                    INSERT INTO candidate_profile (
                        app_user_id, full_name, headline, phone_e164, city_id,
                        total_experience_months, contact_email, date_of_birth,
                        preferred_language_id, expected_salary,
                        expected_salary_currency_id, notice_period_days,
                        is_open_to_work
                    ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                    ON CONFLICT DO NOTHING
                    """,
                    profile_rows[batch_start: batch_start + BATCH_SIZE],
                )

            # ── (d) fetch back profile ids for THIS chunk only ─────────────
            cur.execute(
                "SELECT id FROM candidate_profile WHERE app_user_id = ANY(%s) ORDER BY id",
                (user_ids,),
            )
            profile_ids_chunk = [r[0] for r in cur.fetchall()]

            # ── (e) derived rows — all scoped to this chunk ────────────────
            _insert_education(cur, profile_ids_chunk, qual_ids)
            _insert_experience(cur, profile_ids_chunk, job_role_ids, emp_type_ids)
            _insert_skills(cur, profile_ids_chunk, skill_ids, proficiency_ids)
            _insert_languages(cur, profile_ids_chunk, lang_ids, proficiency_ids)
            _insert_resumes(cur, profile_ids_chunk)

            # ── (f) commit and release this chunk's memory ─────────────────
            conn.commit()
            total_profiles += len(profile_ids_chunk)

    print(f"  ... {N_CANDIDATES}/{N_CANDIDATES}")
    print(f"✓ seed_candidates done  ({total_profiles} profiles inserted)")


if __name__ == "__main__":
    with psycopg.connect(DSN) as conn:
        run(conn)
