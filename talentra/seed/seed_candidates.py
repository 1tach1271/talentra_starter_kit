"""
seed/seed_candidates.py
Seeds:
  app_user (candidates), candidate_profile,
  candidate_education, candidate_experience,
  candidate_skill, candidate_language,
  resume_version
"""

import random
from datetime import date, timedelta

import psycopg
from faker import Faker

from config import DSN, N_CANDIDATES, BATCH_SIZE

fake = Faker(["en_IN", "hi_IN"])
random.seed(42)
Faker.seed(42)

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


def run(conn):
    with conn.cursor() as cur:

        # --- reference maps ---
        skill_ids   = list(_id_map(cur, "skill").values())
        qual_ids    = list(_id_map(cur, "qualification").values())
        lang_ids    = list(_id_map(cur, "language").values())
        job_role_ids= list(_id_map(cur, "job_role").values())
        emp_type_ids= list(_id_map(cur, "employment_type").values())
        city_ids    = list({r[0] for r in cur.execute("SELECT id FROM city").fetchall()})
        currency_ids= list(_id_map(cur, "currency").values())
        proficiency_ids = list(_id_map(cur, "skill_proficiency").values())

        inr_id = cur.execute(
            "SELECT id FROM currency WHERE code='INR'"
        ).fetchone()[0]

        # --- 1. app_users for candidates ---
        user_rows = []
        for i in range(1, N_CANDIDATES + 1):
            fname = random.choice(FIRST_NAMES)
            lname = random.choice(LAST_NAMES)
            name  = f"{fname} {lname}"
            email = f"candidate{i}@talentra-seed.com"
            user_rows.append((email, name))

        # batch insert
        inserted_ids = []
        for batch_start in range(0, len(user_rows), BATCH_SIZE):
            batch = user_rows[batch_start: batch_start + BATCH_SIZE]
            cur.executemany(
                "INSERT INTO app_user (email, display_name) VALUES (%s, %s) ON CONFLICT DO NOTHING",
                batch,
            )

        emails = [r[0] for r in user_rows]
        cur.execute(
            "SELECT id, email FROM app_user WHERE email = ANY(%s) ORDER BY id",
            (emails,),
        )
        user_map = {email: uid for uid, email in cur.fetchall()}
        user_ids = [user_map[e] for e in emails if e in user_map]
        print(f"  candidate app_users: {len(user_ids)} ready")

        # --- 2. candidate_profiles ---
        profile_rows = []
        for i, uid in enumerate(user_ids):
            fname = random.choice(FIRST_NAMES)
            lname = random.choice(LAST_NAMES)
            exp_months = random.randint(0, 180)
            exp_years  = exp_months // 12
            headline   = random.choice(HEADLINES).format(exp_years or "< 1")
            salary     = random.randint(3, 50) * 100_000  # 3L – 50L
            dob        = _rand_date(1985, 2000)
            profile_rows.append((
                uid,
                f"{fname} {lname}",
                headline,
                f"+91{random.randint(7000000000, 9999999999)}",
                random.choice(city_ids),
                exp_months,
                f"p{i + 1}@talentra-seed.com",
                dob,
                random.choice(lang_ids),       # preferred_language_id
                salary,
                inr_id,
                random.randint(0, 90),          # notice_period_days
                random.random() > 0.3,          # is_open_to_work
            ))

        for batch_start in range(0, len(profile_rows), BATCH_SIZE):
            batch = profile_rows[batch_start: batch_start + BATCH_SIZE]
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
                batch,
            )
        print(f"  candidate_profiles: {len(profile_rows)} inserted")

        # fetch profile ids
        cur.execute(
            "SELECT id FROM candidate_profile WHERE app_user_id = ANY(%s) ORDER BY id",
            (user_ids,),
        )
        profile_ids = [r[0] for r in cur.fetchall()]

        # --- 3. education ---
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

        for batch_start in range(0, len(edu_rows), BATCH_SIZE):
            batch = edu_rows[batch_start: batch_start + BATCH_SIZE]
            cur.executemany(
                """
                INSERT INTO candidate_education
                  (candidate_profile_id, qualification_id, institution,
                   field_of_study, start_date, end_date, grade)
                VALUES (%s,%s,%s,%s,%s,%s,%s)
                """,
                batch,
            )
        print(f"  candidate_education:{len(edu_rows)} rows")

        # --- 4. experience ---
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

        for batch_start in range(0, len(exp_rows), BATCH_SIZE):
            batch = exp_rows[batch_start: batch_start + BATCH_SIZE]
            cur.executemany(
                """
                INSERT INTO candidate_experience
                  (candidate_profile_id, job_role_id, employment_type_id,
                   employer_name, job_title, start_date, end_date,
                   is_current, description)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
                """,
                batch,
            )
        print(f"  candidate_experience:{len(exp_rows)} rows")

        # --- 5. skills ---
        skill_rows = []
        seen = set()
        for pid in profile_ids:
            n_skills = random.randint(3, 8)
            chosen   = random.sample(skill_ids, min(n_skills, len(skill_ids)))
            for sid in chosen:
                key = (pid, sid)
                if key not in seen:
                    seen.add(key)
                    skill_rows.append((
                        pid, sid,
                        random.choice(proficiency_ids) if proficiency_ids else None,
                        round(random.uniform(0.5, 8.0), 1),
                    ))

        for batch_start in range(0, len(skill_rows), BATCH_SIZE):
            batch = skill_rows[batch_start: batch_start + BATCH_SIZE]
            cur.executemany(
                """
                INSERT INTO candidate_skill
                  (candidate_profile_id, skill_id, skill_proficiency_id, years_experience)
                VALUES (%s,%s,%s,%s)
                ON CONFLICT (candidate_profile_id, skill_id) DO NOTHING
                """,
                batch,
            )
        print(f"  candidate_skills:   {len(skill_rows)} rows")

        # --- 6. languages ---
        lang_rows = []
        seen = set()
        for pid in profile_ids:
            chosen = random.sample(lang_ids, min(random.randint(1, 3), len(lang_ids)))
            for lid in chosen:
                key = (pid, lid)
                if key not in seen:
                    seen.add(key)
                    lang_rows.append((
                        pid, lid,
                        random.choice(proficiency_ids) if proficiency_ids else None,
                    ))

        for batch_start in range(0, len(lang_rows), BATCH_SIZE):
            batch = lang_rows[batch_start: batch_start + BATCH_SIZE]
            cur.executemany(
                """
                INSERT INTO candidate_language
                  (candidate_profile_id, language_id, skill_proficiency_id)
                VALUES (%s,%s,%s)
                ON CONFLICT (candidate_profile_id, language_id) DO NOTHING
                """,
                batch,
            )
        print(f"  candidate_languages:{len(lang_rows)} rows")

        # --- 7. resume_versions (one per candidate) ---
        resume_rows = [
            (pid, 1, f"resumes/candidate_{pid}_v1.pdf", True)
            for pid in profile_ids
        ]
        for batch_start in range(0, len(resume_rows), BATCH_SIZE):
            batch = resume_rows[batch_start: batch_start + BATCH_SIZE]
            cur.executemany(
                """
                INSERT INTO resume_version
                  (candidate_profile_id, version_no, file_reference, is_primary)
                VALUES (%s,%s,%s,%s)
                ON CONFLICT (candidate_profile_id, version_no) DO NOTHING
                """,
                batch,
            )
        print(f"  resume_versions:    {len(resume_rows)} rows")

    conn.commit()
    print("✓ seed_candidates done")


if __name__ == "__main__":
    with psycopg.connect(DSN) as conn:
        run(conn)
