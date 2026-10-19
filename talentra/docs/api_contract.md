# Talentra — API Contract
> For the UI / frontend developer. Every view, materialised view, and stored function exposed by the database.
> The database is the API. There is no REST layer — the frontend calls these directly via its backend/ORM.

---

## Quick Start

Every connection from your backend must do three things before querying:

```sql
-- 1. Set the authenticated user's ID (from your JWT / session)
SET app.user_id = '12345';          -- app_user.id of the logged-in user

-- 2. Set the role matching the user's type
SET ROLE app_candidate;             -- for candidates
-- or SET ROLE app_recruiter;       -- for recruiters / employers
-- or SET ROLE app_admin;           -- for admins

-- 3. Now query normally
SELECT * FROM v_job_search LIMIT 20 OFFSET 0;
```

**Important:** If you forget to set `app.user_id`, RLS policies that depend on the current user will return 0 rows or raise an error. Always set both `app.user_id` and `ROLE` at connection start.

**Pagination:** All views support standard `LIMIT` / `OFFSET`. There is no built-in cursor. Recommended page size: 20–50 rows.

**Soft deletes:** All views automatically exclude deleted rows (`WHERE deleted_at IS NULL`). You never need to add that filter yourself.

---

## Views

---

### `v_candidate_search`

**Type:** View  
**Purpose:** Flat search card for the candidate directory — one row per candidate, suitable for list/grid views.

**Returns:**

| Column | Type | Description |
|---|---|---|
| `id` | bigint | `candidate_profile.id` |
| `full_name` | varchar(150) | Candidate's full name |
| `headline` | varchar(300) | Professional headline |
| `city_name` | varchar(150) | City name (nullable if no city set) |
| `experience_band` | varchar(20) | `'0-1'`, `'1-3'`, `'3-6'`, or `'6+'` (years) |
| `skill_names` | text[] | Array of skill names, alphabetically sorted. NULL if no skills. |
| `expected_salary` | numeric(14,2) | Expected annual salary (nullable) |
| `is_open_to_work` | boolean | Whether the candidate is actively looking |

**Example calls:**

```sql
-- All open-to-work candidates in a city
SELECT * FROM v_candidate_search
WHERE is_open_to_work = true
  AND city_name = 'Mumbai'
LIMIT 20;

-- Filter by skill (skill must be in the skills array)
SELECT * FROM v_candidate_search
WHERE 'Python' = ANY(skill_names)
  AND experience_band IN ('3-6', '6+')
LIMIT 20;

-- Combined skill + city search (preferred — matches Q01 benchmark query)
SELECT v.*
FROM v_candidate_search v
JOIN candidate_skill cs ON cs.candidate_profile_id = v.id
JOIN skill s ON s.id = cs.skill_id
WHERE s.id = 3          -- use skill.id for indexed lookup
  AND v.city_name = 'Bengaluru'
  AND v.is_open_to_work = true
LIMIT 50;
```

**RLS behaviour:** As `app_recruiter`, blocked candidates are invisible. As `app_candidate`, only your own row is returned (use `v_candidate_profile_full` for your own profile page instead).

---

### `v_job_search`

**Type:** View  
**Purpose:** Published job listings for the job board. Only returns jobs with `job_status = 'published'`.

**Returns:**

| Column | Type | Description |
|---|---|---|
| `id` | bigint | `job.id` |
| `title` | varchar(300) | Job title |
| `org_name` | varchar(300) | Posting organisation's name |
| `city_name` | varchar(150) | Location (nullable for remote) |
| `role_name` | varchar(200) | Job role / category name |
| `salary_min` | numeric(14,2) | Minimum salary |
| `salary_max` | numeric(14,2) | Maximum salary |
| `work_type_name` | varchar(100) | `'Remote'`, `'On-site'`, `'Hybrid'` |
| `emp_type_name` | varchar(100) | `'Full-time'`, `'Contract'`, `'Part-time'`, etc. |
| `published_at` | timestamptz | When the job was published |
| `is_open_to_consultants` | boolean | Whether freelance recruiters can source for this job |

**Example calls:**

```sql
-- Job board: latest published jobs
SELECT * FROM v_job_search
ORDER BY published_at DESC
LIMIT 20;

-- Filter by role and city
SELECT * FROM v_job_search
WHERE role_name ILIKE '%data scientist%'
  AND city_name = 'Hyderabad'
ORDER BY published_at DESC;

-- Salary filter
SELECT * FROM v_job_search
WHERE salary_min >= 1000000  -- 10 LPA
  AND work_type_name = 'Remote'
ORDER BY published_at DESC;

-- Fuzzy title search (needs pg_trgm extension — fast)
SELECT * FROM v_job_search
WHERE title % 'backend engineer'
ORDER BY similarity(title, 'backend engineer') DESC
LIMIT 20;
```

**RLS behaviour:** Candidates see only published jobs. Recruiters see all their own organisation's jobs (any status) plus published jobs from others.

---

### `v_application_pipeline`

**Type:** View  
**Purpose:** Aggregate count of applications per job per pipeline stage. Used for the recruiter kanban board or pipeline funnel chart.

**Returns:**

| Column | Type | Description |
|---|---|---|
| `job_id` | bigint | `job.id` |
| `job_title` | varchar(300) | Job title |
| `org_name` | varchar(300) | Organisation name |
| `stage_code` | varchar(60) | Stage identifier: `'applied'`, `'shortlisted'`, `'interviewed'`, `'offered'`, `'joined'`, `'rejected'` |
| `stage_order` | integer | Sort order for display (0 = earliest) |
| `application_count` | bigint | Number of applications in this stage for this job |

**Example calls:**

```sql
-- Full pipeline for one job
SELECT stage_code, stage_order, application_count
FROM v_application_pipeline
WHERE job_id = 42
ORDER BY stage_order;

-- All active jobs and their pipeline counts for one org
SELECT job_id, job_title, stage_code, application_count
FROM v_application_pipeline
WHERE org_name = 'Acme Corp'
ORDER BY job_id, stage_order;
```

**RLS behaviour:** Recruiters only see their organisation's jobs.

---

### `v_recruiter_inbox`

**Type:** View  
**Purpose:** Inbound applications for a recruiter's organisation, one row per application. Use this for the "applications" list page.

**Returns:**

| Column | Type | Description |
|---|---|---|
| `application_id` | bigint | `application.id` |
| `job_title` | varchar(300) | Job the candidate applied to |
| `candidate_name` | varchar(150) | Candidate's full name |
| `candidate_city` | varchar(150) | Candidate's city |
| `applied_at` | timestamptz | When the application was submitted |
| `stage_code` | varchar(60) | Current pipeline stage |
| `job_organisation_id` | bigint | Organisation that owns the job (for additional RLS checks if needed) |

**Example calls:**

```sql
-- All applications for my org, newest first
SELECT * FROM v_recruiter_inbox
ORDER BY applied_at DESC
LIMIT 50;

-- Only shortlisted
SELECT * FROM v_recruiter_inbox
WHERE stage_code = 'shortlisted'
ORDER BY applied_at DESC;

-- Applications for a specific job
SELECT * FROM v_recruiter_inbox
WHERE job_title = 'Senior Data Scientist – Bengaluru'
ORDER BY applied_at DESC;
```

**RLS behaviour:** Returns only applications for the recruiter's own organisation's jobs.

---

### `v_gig_requests_open`

**Type:** View  
**Purpose:** Open gig requests available for gig workers to browse. Only shows `gig_status = 'open'`.

**Returns:**

| Column | Type | Description |
|---|---|---|
| `id` | bigint | `gig_request.id` |
| `title` | varchar(300) | Gig title |
| `org_name` | varchar(300) | Requester organisation |
| `city_name` | varchar(150) | Location (nullable for remote gigs) |
| `starts_at` | timestamptz | Gig window start |
| `ends_at` | timestamptz | Gig window end |
| `pay_amount` | numeric(14,2) | Pay for the gig |
| `pay_currency_code` | char(3) | ISO 4217 currency code (e.g. `'INR'`) |
| `openings` | integer | Number of workers needed |

**Example calls:**

```sql
-- Browse open gigs
SELECT * FROM v_gig_requests_open
ORDER BY starts_at ASC
LIMIT 20;

-- Gigs in a specific city starting soon
SELECT * FROM v_gig_requests_open
WHERE city_name = 'Delhi'
  AND starts_at BETWEEN NOW() AND NOW() + INTERVAL '30 days'
ORDER BY starts_at;
```

---

### `v_candidate_profile_full`

**Type:** View  
**Purpose:** Full candidate profile card for the profile detail page. Includes aggregated skills, latest education summary, and links.

**Returns:**

| Column | Type | Description |
|---|---|---|
| `id` | bigint | `candidate_profile.id` |
| `full_name` | varchar(150) | Full name |
| `headline` | varchar(300) | Professional headline |
| `contact_email` | varchar(254) | Contact email (**masked for non-downloading recruiters — apply masking in your backend layer**) |
| `phone_e164` | varchar(20) | Phone in E.164 format (**mask last 6 digits for non-downloaders**) |
| `city_name` | varchar(150) | City name |
| `total_experience_months` | integer | Total experience in months |
| `expected_salary` | numeric(14,2) | Expected salary |
| `expected_salary_currency_code` | char(3) | Currency code |
| `notice_period_days` | integer | Notice period in days |
| `is_open_to_work` | boolean | Actively looking? |
| `profile_completeness` | numeric(5,2) | Profile completion percentage (0–100) |
| `skill_names` | text[] | All skills, alphabetically sorted |
| `education_summary` | text | Latest qualification — institution string (e.g. `'B.Tech — IIT Bombay'`) |
| `linkedin_url` | varchar(300) | LinkedIn profile URL (nullable) |
| `github_url` | varchar(300) | GitHub URL (nullable) |
| `portfolio_url` | varchar(300) | Portfolio URL (nullable) |

**Example calls:**

```sql
-- Load a candidate's profile page
SELECT * FROM v_candidate_profile_full WHERE id = 12345;

-- Candidates a recruiter has already downloaded (no extra cost)
SELECT vf.*
FROM v_candidate_profile_full vf
JOIN profile_download pd ON pd.candidate_profile_id = vf.id
WHERE pd.organisation_id = <my_org_id>
ORDER BY pd.downloaded_at DESC;
```

**Note on masking:** `contact_email` and `phone_e164` are returned in full from the view. Your backend layer must apply masking for recruiters who have NOT downloaded the profile. Only show full contact details after `sp_download_profile()` has been called.

---

### `v_org_hiring_kpi`

**Type:** View (wraps `dw.mv_organisation_hiring_kpi`)  
**Purpose:** Organisation-level hiring KPIs for the employer dashboard. Data is from the DW materialised view — refreshed nightly via `dw.sp_refresh_dw()`. Not real-time.

**Returns:**

| Column | Type | Description |
|---|---|---|
| `organisation_id` | bigint | Organisation ID |
| `org_name` | varchar(300) | Organisation name |
| `jobs_with_applications` | bigint | Count of distinct jobs that received at least one application |
| `total_applications` | bigint | Total applications received |
| `total_joined` | bigint | Applications that reached the `'joined'` stage |
| `join_rate_pct` | numeric(5,2) | `(total_joined / total_applications) × 100` |

**Example call:**

```sql
-- My org's hiring KPIs
SELECT * FROM v_org_hiring_kpi WHERE organisation_id = <my_org_id>;

-- Top 10 orgs by join rate
SELECT * FROM v_org_hiring_kpi ORDER BY join_rate_pct DESC LIMIT 10;
```

---

## Materialised Views (Analytics)

These are pre-computed and refreshed by `dw.sp_refresh_dw()`. They are **not real-time** — call the refresh procedure from a nightly cron job or before rendering a dashboard.

---

### `dw.mv_daily_application_funnel`

**Type:** Materialised View  
**Purpose:** Daily application volume broken down by pipeline stage. Use this for the funnel/trend chart.

| Column | Type | Description |
|---|---|---|
| `full_date` | date | Calendar date |
| `stage_code` | varchar(60) | Pipeline stage |
| `application_count` | bigint | Applications in that stage on that date |

```sql
SELECT full_date, stage_code, application_count
FROM dw.mv_daily_application_funnel
WHERE full_date >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY full_date, stage_code;
```

---

### `dw.mv_organisation_hiring_kpi`

**Type:** Materialised View  
**Purpose:** Same data as `v_org_hiring_kpi` (the view wraps this). See above.

---

## Stored Functions and Procedures

---

### `sp_download_profile(recruiter_id, candidate_profile_id, cost := 1)`

**Type:** Stored function (`SECURITY DEFINER`)  
**Purpose:** Deducts 1 credit from the recruiter's organisation wallet and records a profile download. Fully idempotent — calling it twice with the same recruiter + candidate returns the same `profile_download.id` without charging again.

**Parameters:**

| Parameter | Type | Description |
|---|---|---|
| `p_recruiter_id` | bigint | `recruiter.id` of the downloading recruiter |
| `p_candidate_profile_id` | bigint | `candidate_profile.id` being downloaded |
| `p_cost` | integer | Credits to deduct (default: 1) |

**Returns:** `bigint` — the `profile_download.id`

**Example call:**

```sql
-- Download a candidate profile (deducts 1 credit, idempotent)
SELECT sp_download_profile(
  p_recruiter_id          := 55,
  p_candidate_profile_id  := 12345
);
```

**Errors:**
- `unknown recruiter <id>` — recruiter_id doesn't exist or is deleted
- `insufficient_privilege` — the recruiter doesn't belong to the current `app.user_id`
- `check_violation` — wallet balance would go below 0 (insufficient credits)

**After calling this:** show the full `v_candidate_profile_full` row including unmasked email and phone.

---

### `dw.sp_refresh_dw()`

**Type:** Stored procedure  
**Purpose:** Refreshes all DW dimensions (SCD2), facts, and materialised views in one call. Run this from a nightly cron job.

**Parameters:** None

**Example call:**

```sql
CALL dw.sp_refresh_dw();
```

**What it refreshes (in order):**
1. `dw.dim_organisation` — SCD2 update for changed org names/industries
2. `dw.dim_job` — SCD2 update for changed job titles/statuses
3. `dw.dim_candidate` — upsert for changed city/experience band
4. `dw.fact_application` — upsert for new/updated applications
5. `dw.fact_payment` — upsert for new/updated payments
6. `dw.mv_daily_application_funnel` — full refresh
7. `dw.mv_organisation_hiring_kpi` — full refresh

**Recommended schedule:** Once per night at off-peak hours (e.g., 02:00 IST). The refresh is not instant at 1M+ scale — budget 2–10 minutes.

---

## Reference: Lookup Table Codes

Use these codes when filtering views by status or type:

### Job status (`job_status.code`)
| Code | Meaning |
|---|---|
| `published` | Visible on job board |
| `draft` | Not yet published |
| `closed` | No longer accepting applications |

### Application stage (`application_stage.code`)
| Code | Stage order | Terminal? |
|---|---|---|
| `applied` | 1 | No |
| `shortlisted` | 2 | No |
| `interviewed` | 3 | No |
| `offered` | 4 | No |
| `joined` | 5 | Yes |
| `rejected` | 6 | Yes |
| `withdrawn` | 7 | Yes |

### Gig status (`gig_status.code`)
| Code | Meaning |
|---|---|
| `open` | Accepting applications |
| `assigned` | Worker accepted |
| `completed` | Gig done |
| `cancelled` | Cancelled |

---

## Connection Setup Example (Node.js / pg)

```javascript
const { Pool } = require('pg');

const pool = new Pool({
  host: 'localhost',
  port: 5433,           // docker-compose maps 5433 → 5432
  database: 'talentra',
  user: 'talentra',
  password: 'talentra',
});

async function queryAsRecruiter(userId, sql, params) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(`SET LOCAL app.user_id = $1`, [userId]);
    await client.query(`SET LOCAL ROLE app_recruiter`);
    const result = await client.query(sql, params);
    await client.query('COMMIT');
    return result.rows;
  } finally {
    client.release();
  }
}

// Usage
const jobs = await queryAsRecruiter(
  authenticatedUserId,
  `SELECT * FROM v_job_search ORDER BY published_at DESC LIMIT 20`
);
```

---

*Last updated: October 2026*
