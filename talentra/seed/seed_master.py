"""
seed/seed_master.py
Seeds all master / reference data:
  currency, language, country, state, city,
  skill, qualification, industry, job_role,
  employment_type, work_type, job_status, application_stage,
  lookup_translation (sample Hindi / Tamil translations)

Safe to re-run: uses INSERT ... ON CONFLICT DO NOTHING throughout,
so it won't create duplicates if some rows already exist.
"""

import psycopg
from config import DSN


# ── Raw data ─────────────────────────────────────────────────────────────────

CURRENCIES = [
    ("INR", "Indian Rupee",  2),
    ("USD", "US Dollar",     2),
    ("EUR", "Euro",          2),
    ("GBP", "British Pound", 2),
    ("SGD", "Singapore Dollar", 2),
]

LANGUAGES = [
    ("en", "English", "English",    True),
    ("hi", "Hindi",   "हिन्दी",    False),
    ("ta", "Tamil",   "தமிழ்",     False),
    ("te", "Telugu",  "తెలుగు",    False),
]

# (iso2, iso3, name, phone_code, currency_code)
COUNTRIES = [
    ("IN", "IND", "India",          "+91", "INR"),
    ("US", "USA", "United States",  "+1",  "USD"),
    ("GB", "GBR", "United Kingdom", "+44", "GBP"),
    ("SG", "SGP", "Singapore",      "+65", "SGD"),
    ("DE", "DEU", "Germany",        "+49", "EUR"),
]

# (country_iso2, state_code, state_name)
STATES = [
    ("IN", "TN", "Tamil Nadu"),
    ("IN", "KA", "Karnataka"),
    ("IN", "MH", "Maharashtra"),
    ("IN", "DL", "Delhi"),
    ("IN", "TG", "Telangana"),
    ("IN", "WB", "West Bengal"),
    ("IN", "GJ", "Gujarat"),
    ("IN", "RJ", "Rajasthan"),
    ("US", "CA", "California"),
    ("US", "NY", "New York"),
    ("US", "TX", "Texas"),
    ("GB", "ENG", "England"),
    ("SG", "SG",  "Singapore"),   # city-state
    ("DE", "BY",  "Bavaria"),
]

# (state_code, city_name, latitude, longitude)
CITIES = [
    ("TN",  "Chennai",         13.0827,  80.2707),
    ("TN",  "Coimbatore",      11.0168,  76.9558),
    ("TN",  "Madurai",         9.9252,   78.1198),
    ("KA",  "Bengaluru",       12.9716,  77.5946),
    ("KA",  "Mysuru",          12.2958,  76.6394),
    ("MH",  "Mumbai",          19.0760,  72.8777),
    ("MH",  "Pune",            18.5204,  73.8567),
    ("MH",  "Nagpur",          21.1458,  79.0882),
    ("DL",  "New Delhi",       28.6139,  77.2090),
    ("TG",  "Hyderabad",       17.3850,  78.4867),
    ("WB",  "Kolkata",         22.5726,  88.3639),
    ("GJ",  "Ahmedabad",       23.0225,  72.5714),
    ("RJ",  "Jaipur",          26.9124,  75.7873),
    ("CA",  "San Francisco",   37.7749, -122.4194),
    ("CA",  "Los Angeles",     34.0522, -118.2437),
    ("NY",  "New York City",   40.7128,  -74.0060),
    ("TX",  "Austin",          30.2672,  -97.7431),
    ("ENG", "London",          51.5074,  -0.1278),
    ("SG",  "Singapore City",  1.3521,   103.8198),
    ("BY",  "Munich",          48.1351,  11.5820),
]

SKILLS = [
    ("java",             "Java"),
    ("python",           "Python"),
    ("sql",              "SQL"),
    ("javascript",       "JavaScript"),
    ("typescript",       "TypeScript"),
    ("react",            "React"),
    ("nodejs",           "Node.js"),
    ("spring_boot",      "Spring Boot"),
    ("docker",           "Docker"),
    ("kubernetes",       "Kubernetes"),
    ("aws",              "AWS"),
    ("azure",            "Azure"),
    ("machine_learning", "Machine Learning"),
    ("deep_learning",    "Deep Learning"),
    ("data_analysis",    "Data Analysis"),
    ("power_bi",         "Power BI"),
    ("tableau",          "Tableau"),
    ("excel",            "Excel"),
    ("git",              "Git"),
    ("linux",            "Linux"),
    ("cpp",              "C++"),
    ("go",               "Go"),
    ("rust",             "Rust"),
    ("devops",           "DevOps"),
    ("testing",          "Testing"),
    ("figma",            "Figma"),
    ("sales",            "Sales"),
    ("accounting",       "Accounting"),
    ("communication",    "Communication"),
    ("project_mgmt",     "Project Management"),
]

# (code, name, level_rank)
QUALIFICATIONS = [
    ("school",     "School / Secondary",   1),
    ("diploma",    "Diploma",              2),
    ("bachelors",  "Bachelor's Degree",    3),
    ("masters",    "Master's Degree",      4),
    ("doctorate",  "Doctorate / PhD",      5),
    ("certificate","Certificate",          2),
    ("pgdiploma",  "Post-Graduate Diploma",3),
]

# (code, name, parent_code or None)
INDUSTRIES = [
    ("it",        "Information Technology", None),
    ("fin",       "Finance & Banking",      None),
    ("health",    "Healthcare",             None),
    ("edu",       "Education",              None),
    ("mfg",       "Manufacturing",          None),
    ("retail",    "Retail & E-Commerce",    None),
    ("media",     "Media & Entertainment",  None),
    ("logistics", "Logistics & Supply Chain",None),
    ("realestate","Real Estate",            None),
    ("auto",      "Automotive",             "mfg"),   # child of manufacturing
    ("fintech",   "FinTech",                "fin"),   # child of finance
    ("edtech",    "EdTech",                 "edu"),   # child of education
]

# (code, name, industry_code)
JOB_ROLES = [
    ("software_engineer",    "Software Engineer",     "it"),
    ("data_scientist",       "Data Scientist",        "it"),
    ("data_analyst",         "Data Analyst",          "it"),
    ("ml_engineer",          "ML Engineer",           "it"),
    ("devops_engineer",      "DevOps Engineer",       "it"),
    ("product_manager",      "Product Manager",       "it"),
    ("qa_engineer",          "QA Engineer",           "it"),
    ("frontend_developer",   "Frontend Developer",    "it"),
    ("backend_developer",    "Backend Developer",     "it"),
    ("fullstack_developer",  "Full Stack Developer",  "it"),
    ("business_analyst",     "Business Analyst",      "fin"),
    ("accountant",           "Accountant",            "fin"),
    ("financial_analyst",    "Financial Analyst",     "fin"),
    ("sales_executive",      "Sales Executive",       "retail"),
    ("hr_executive",         "HR Executive",          "it"),
    ("ux_designer",          "UX Designer",           "media"),
    ("content_writer",       "Content Writer",        "media"),
    ("operations_manager",   "Operations Manager",    "logistics"),
    ("mechanical_engineer",  "Mechanical Engineer",   "mfg"),
    ("support_engineer",     "Support Engineer",      "it"),
]

EMPLOYMENT_TYPES = [
    ("full_time",   "Full Time"),
    ("part_time",   "Part Time"),
    ("contract",    "Contract"),
    ("internship",  "Internship"),
    ("gig",         "Gig / Project-based"),
    ("apprentice",  "Apprentice"),
    ("freelance",   "Freelance"),
]

WORK_TYPES = [
    ("onsite", "On-site"),
    ("remote", "Remote"),
    ("hybrid", "Hybrid"),
]

JOB_STATUSES = [
    ("draft",     "Draft"),
    ("published", "Published"),
    ("paused",    "Paused"),
    ("closed",    "Closed"),
]

APPLICATION_STAGES = [
    ("applied",      "Applied",      1, False),
    ("shortlisted",  "Shortlisted",  2, False),
    ("interviewed",  "Interviewed",  3, False),
    ("offered",      "Offered",      4, False),
    ("joined",       "Joined",       5, True),
    ("rejected",     "Rejected",     6, True),
    ("withdrawn",    "Withdrawn",    7, True),
]

# Sample translations: (entity_table, entity_code, language_code, translated_name)
# Keyed by (table, code) → looked up to get entity_id at runtime
TRANSLATIONS = [
    ("employment_type", "full_time",  "hi", "पूर्णकालिक"),
    ("employment_type", "full_time",  "ta", "முழு நேரம்"),
    ("employment_type", "part_time",  "hi", "अंशकालिक"),
    ("employment_type", "part_time",  "ta", "பகுதி நேரம்"),
    ("employment_type", "contract",   "hi", "अनुबंध"),
    ("employment_type", "contract",   "ta", "ஒப்பந்தம்"),
    ("work_type",       "onsite",     "hi", "कार्यालय में"),
    ("work_type",       "remote",     "hi", "दूरस्थ"),
    ("work_type",       "hybrid",     "hi", "हाइब्रिड"),
    ("job_status",      "published",  "hi", "प्रकाशित"),
    ("job_status",      "closed",     "hi", "बंद"),
]


# ── Helpers ──────────────────────────────────────────────────────────────────

def _id_map(cur, table: str, key_col: str = "code") -> dict:
    """Return {code: id} for any lookup table."""
    cur.execute(f"SELECT {key_col}, id FROM {table}")
    return {row[0]: row[1] for row in cur.fetchall()}


# ── Seeder ───────────────────────────────────────────────────────────────────

def run(conn):
    with conn.cursor() as cur:

        # 1. currencies
        cur.executemany(
            """
            INSERT INTO currency (code, name, minor_unit)
            VALUES (%s, %s, %s)
            ON CONFLICT (code) DO NOTHING
            """,
            CURRENCIES,
        )
        print(f"  currencies:    {cur.rowcount} inserted")

        # 2. languages
        cur.executemany(
            """
            INSERT INTO language (code, name, native_name, is_active)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (code) DO NOTHING
            """,
            LANGUAGES,
        )
        print(f"  languages:     {cur.rowcount} inserted")

        # 3. countries  (need currency_id)
        currency_ids = _id_map(cur, "currency")
        cur.executemany(
            """
            INSERT INTO country (iso2, iso3, name, phone_code, currency_id)
            VALUES (%s, %s, %s, %s, %s)
            ON CONFLICT (iso2) DO NOTHING
            """,
            [
                (iso2, iso3, name, phone, currency_ids.get(cur_code))
                for iso2, iso3, name, phone, cur_code in COUNTRIES
            ],
        )
        print(f"  countries:     {cur.rowcount} inserted")

        # 4. states
        country_ids = _id_map(cur, "country", "iso2")
        cur.executemany(
            """
            INSERT INTO state (country_id, code, name)
            VALUES (%s, %s, %s)
            ON CONFLICT (country_id, code) DO NOTHING
            """,
            [
                (country_ids[iso2], code, name)
                for iso2, code, name in STATES
                if iso2 in country_ids
            ],
        )
        print(f"  states:        {cur.rowcount} inserted")

        # 5. cities
        state_ids = _id_map(cur, "state", "code")
        cur.executemany(
            """
            INSERT INTO city (state_id, name, latitude, longitude)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (state_id, name) DO NOTHING
            """,
            [
                (state_ids[sc], name, lat, lon)
                for sc, name, lat, lon in CITIES
                if sc in state_ids
            ],
        )
        print(f"  cities:        {cur.rowcount} inserted")

        # 6. skills
        cur.executemany(
            """
            INSERT INTO skill (code, name)
            VALUES (%s, %s)
            ON CONFLICT (code) DO NOTHING
            """,
            SKILLS,
        )
        print(f"  skills:        {cur.rowcount} inserted")

        # 7. qualifications
        cur.executemany(
            """
            INSERT INTO qualification (code, name, level_rank)
            VALUES (%s, %s, %s)
            ON CONFLICT (code) DO NOTHING
            """,
            QUALIFICATIONS,
        )
        print(f"  qualifications:{cur.rowcount} inserted")

        # 8. industries (two-pass: parents first, then children)
        parents_first = [r for r in INDUSTRIES if r[2] is None]
        children      = [r for r in INDUSTRIES if r[2] is not None]
        cur.executemany(
            """
            INSERT INTO industry (code, name, parent_industry_id)
            VALUES (%s, %s, NULL)
            ON CONFLICT (code) DO NOTHING
            """,
            [(c, n) for c, n, _ in parents_first],
        )
        industry_ids = _id_map(cur, "industry")
        cur.executemany(
            """
            INSERT INTO industry (code, name, parent_industry_id)
            VALUES (%s, %s, %s)
            ON CONFLICT (code) DO NOTHING
            """,
            [
                (code, name, industry_ids.get(parent))
                for code, name, parent in children
            ],
        )
        industry_ids = _id_map(cur, "industry")   # refresh after children
        print(f"  industries:    {len(industry_ids)} total")

        # 9. job_roles
        cur.executemany(
            """
            INSERT INTO job_role (code, name, industry_id)
            VALUES (%s, %s, %s)
            ON CONFLICT (code) DO NOTHING
            """,
            [
                (code, name, industry_ids.get(ind_code))
                for code, name, ind_code in JOB_ROLES
            ],
        )
        print(f"  job_roles:     {cur.rowcount} inserted")

        # 10. employment_types
        cur.executemany(
            """
            INSERT INTO employment_type (code, name)
            VALUES (%s, %s)
            ON CONFLICT (code) DO NOTHING
            """,
            EMPLOYMENT_TYPES,
        )
        print(f"  employment_types: {cur.rowcount} inserted")

        # 11. work_types
        cur.executemany(
            """
            INSERT INTO work_type (code, name)
            VALUES (%s, %s)
            ON CONFLICT (code) DO NOTHING
            """,
            WORK_TYPES,
        )
        print(f"  work_types:    {cur.rowcount} inserted")

        # 12. job_statuses
        cur.executemany(
            """
            INSERT INTO job_status (code, name)
            VALUES (%s, %s)
            ON CONFLICT (code) DO NOTHING
            """,
            JOB_STATUSES,
        )
        print(f"  job_statuses:  {cur.rowcount} inserted")

        # 13. application_stages
        cur.executemany(
            """
            INSERT INTO application_stage (code, name, stage_order, is_terminal)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (code) DO NOTHING
            """,
            APPLICATION_STAGES,
        )
        print(f"  application_stages: {cur.rowcount} inserted")

        # 14. lookup_translations (employment_type, work_type, job_status)
        lang_ids = _id_map(cur, "language")
        et_ids   = _id_map(cur, "employment_type")
        wt_ids   = _id_map(cur, "work_type")
        js_ids   = _id_map(cur, "job_status")

        table_map = {
            "employment_type": et_ids,
            "work_type":       wt_ids,
            "job_status":      js_ids,
        }

        translation_rows = []
        for tbl, entity_code, lang_code, translated in TRANSLATIONS:
            entity_id   = table_map.get(tbl, {}).get(entity_code)
            language_id = lang_ids.get(lang_code)
            if entity_id and language_id:
                translation_rows.append((tbl, entity_id, language_id, translated))

        cur.executemany(
            """
            INSERT INTO lookup_translation
              (entity_table, entity_id, language_id, translated_name)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (entity_table, entity_id, language_id) DO NOTHING
            """,
            translation_rows,
        )
        print(f"  translations:  {cur.rowcount} inserted")

    conn.commit()
    print("✓ seed_master done")


if __name__ == "__main__":
    with psycopg.connect(DSN) as conn:
        run(conn)
