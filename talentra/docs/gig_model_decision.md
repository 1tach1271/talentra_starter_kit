# Decision D4 — Gig Model: Separate Subsystem

**Decision ID:** D4  
**Date:** 2026-10-20  
**Status:** ACCEPTED  
**Owner:** Kshitij  
**Supersedes:** —  
**Related decisions:** D3 (lookup tables for enums), D5 (Tier 3 deferral)

---

## 1. The Question

> **Why not reuse the existing `job` and `application` tables to model gig work?**

When the gig domain was introduced, the most obvious path was to extend `job_requirement` with a "gig" flag and reuse `application` for gig bids. This would minimise the number of tables, keep reporting paths simple, and avoid duplicating concepts such as "a worker expresses interest in a work opportunity."

This decision record explains why that approach was rejected and why a **dedicated gig subsystem** was chosen instead.

---

## 2. Structural Differences That Make Reuse Untenable

The following differences were identified by comparing the two domains side-by-side. Each difference on its own might be handled with a nullable column or a conditional constraint; together they create a model that would be fundamentally ambiguous.

### 2.1 Time Window vs. Open-ended Tenure

Gig work has a hard time window:

```sql
-- gig_request
starts_at  timestamptz not null,
ends_at    timestamptz not null,
constraint ck_gig_request_window check (ends_at > starts_at)
```

A job posting is open-ended — it has a `posted_at` and possibly an `expires_at`, but there is no concept of "the job begins at 14:00 on Tuesday and ends at 22:00." Storing `starts_at` / `ends_at` on `job_requirement` would require `NULL` for every non-gig job, which violates Convention 13 (nullable columns need a justification comment) and, more importantly, makes the schema semantically incorrect — a `NULL` end time on a gig request is a data error, not an optional field.

### 2.2 Pay Structure

| Domain | Pay column | Type |
|---|---|---|
| Gig | `gig_request.pay_amount` (fixed fee for the window, or rate × hours) | `numeric(14,2) NOT NULL` |
| Job | `job_requirement.salary_min` / `salary_max` (annual range) | `numeric(14,2)` nullable range |

Merging these into a single table would require two separate pay columns (`pay_amount` for gig, `salary_min` / `salary_max` for jobs), each nullable when the other is active. The check constraints that enforce sign and range on each column would interact badly. The business meaning of "how much does this work pay?" would require application-layer branching to interpret.

### 2.3 Application Direction

The job model is **recruiter-initiated**: a recruiter posts a job; a candidate applies to it. The gig model is **worker-initiated (bid model)**: an organisation posts a `gig_request`; a gig worker submits a `gig_application` (a bid). There is no recruiter outreach step.

If the same `application` table were used:
- The `recruiter_id` FK would be `NULL` on all gig rows.
- The `candidate_profile_id` FK (used for job applications) would be conceptually wrong for a `gig_worker_profile`.
- The `gig_worker_profile_id` FK would be `NULL` on all job rows.

This produces a table that is half-empty in either direction, which is precisely the anti-pattern that Convention 13 exists to prevent.

### 2.4 External Fulfilment Handoff

When a gig is assigned, Talentra hands off to an external fulfilment system:

```sql
-- gig_assignment
fulfilment_reference varchar(100),   -- external system's reference
work_window          tstzrange not null,
-- EXCLUDE constraint prevents overlapping windows for same worker
constraint ex_gig_assignment_no_overlap
  exclude using gist (gig_worker_profile_id with =, work_window with &&)
  where (not is_cancelled)
```

And the financial reconciliation is tracked separately:

```sql
-- gig_earning_reference
external_reference varchar(100) not null,
reconciled_at      timestamptz,   -- set exactly once on reconciliation
constraint uq_gig_earning_reference_external unique (external_reference)
```

A job application has no equivalent. There is no `fulfilment_reference` on a hiring decision, no reconciliation event, and no `tstzrange` for the work performed. Adding these columns to a shared `assignment` table would require `NULL` for every job-related row with no path to making them `NOT NULL`.

### 2.5 Availability Windows with Overlap Prevention

The gig subsystem tracks worker availability at fine granularity:

```sql
-- gig_availability
available_window tstzrange not null,
constraint ck_gig_availability_not_empty check (not isempty(available_window)),
constraint ex_gig_availability_no_overlap
  exclude using gist (gig_worker_profile_id with =, available_window with &&)
```

The `EXCLUDE USING GIST` constraint is a PostgreSQL-specific range overlap prevention mechanism. It requires the `btree_gist` extension and a GiST index. The candidate domain has no equivalent — there is no concept of "a candidate cannot be in two job processes at the same time." Adding availability windows to `candidate_profile` or `application` would be semantically meaningless and would pollute the GiST index with unused rows.

### 2.6 Favouriting and Blacklisting per Requester Organisation

The gig subsystem includes per-organisation worker preference management:

```sql
-- gig_worker_favourite  (gig subsystem only)
organisation_id        bigint not null references organisation(id)
gig_worker_profile_id  bigint not null references gig_worker_profile(id)

-- gig_worker_blacklist  (gig subsystem only)
organisation_id        bigint not null references organisation(id)
gig_worker_profile_id  bigint not null references gig_worker_profile(id)
```

This relationship is directional and organisational — an employer can mark a specific gig worker as preferred or blocked across all future requests. The concept does not translate to the recruitment domain, where candidates are evaluated per-application rather than placed on organisation-wide lists.

### 2.7 Ratings on Assignments, Not Applications

```sql
-- gig_rating
gig_assignment_id      bigint not null references gig_assignment(id),
rated_by_app_user_id   bigint not null references app_user(id),
rating                 smallint not null check (rating between 1 and 5),
constraint uq_gig_rating_assignment_rater unique (gig_assignment_id, rated_by_app_user_id)
```

Ratings apply to **completed gig assignments** — a bilateral post-work evaluation. In the recruitment domain there is no analogous rating of a job application outcome. Sharing the `application` table would require a nullable `rating` and a nullable `rated_at` on every job application row — two more unjustified nullable columns.

---

## 3. Trade-offs Accepted

### 3.1 Cross-type Reporting

A combined pipeline view (jobs + gigs in a single query) cannot be achieved with a simple `SELECT`; it requires either:

- A `UNION` query in application code or a view (`v_combined_pipeline`), or
- The data warehouse layer: `dw.fact_application` is designed to absorb both job applications and gig applications into a single analytics fact table, normalised against `dw.dim_worker` and `dw.dim_requirement`.

**Mitigation:** The DW layer absorbs this complexity. Operational reporting that truly needs both domains can use a `UNION` view. This is an acceptable cost given the correctness guarantee of the separate schemas.

### 3.2 Separate Code Paths

Two subsystems mean two code paths in the application layer: one for job posting + application management, one for gig request + bid management. This increases initial development cost and ongoing maintenance surface.

**Mitigation:** Both subsystems share the `app_user` identity table and the `organisation` table. Authentication, authorisation (RLS roles `app_candidate`, `app_recruiter`, `app_admin`), wallet, subscription, and payment are shared infrastructure. The shared spine reduces the duplication to domain-specific business logic only.

### 3.3 Future Unification Path

If the two domains need to be unified in a future schema version, a **super-type table** approach is available:

```sql
-- Hypothetical future unification
create table job_requirement_base (
  id               bigint generated always as identity primary key,
  requirement_type varchar(20) not null check (requirement_type in ('job','gig')),
  organisation_id  bigint not null references organisation(id),
  title            varchar(300) not null,
  -- ... shared fields only
);
```

The current separate-subsystem design does not preclude this unification. Because each subsystem uses its own `id` sequence and `_id` FK conventions, a future migration can introduce the super-type table and back-fill it without altering the existing child tables.

---

## 4. The Decision

**DECISION: Gig is a separate subsystem.**

Sharing `job` and `application` tables with the gig domain would require adding nullable columns for every gig-specific attribute (`starts_at`, `ends_at`, `work_window`, `fulfilment_reference`, `hourly_rate`, `availability_window`, etc.) to the core job tables. Under Convention 13, each of these nullable columns requires a `COMMENT ON COLUMN` justifying why it is nullable.

The honest justification for each comment would be: *"nullable because this column only applies when this row represents a gig, not a job."* That justification is a direct admission that the table is modelling two distinct entities — which is precisely what the separate-subsystem design makes explicit at the schema level.

A shared table with conditional semantics is harder to validate (check constraints must be conditional), harder to query (every join needs a type discriminator), harder to index (GiST indexes on `work_window` would cover NULL-valued job rows), and harder to extend (adding a gig-only constraint risks breaking the job path).

The separate subsystem design is correct, maintainable, and consistent with the project's own conventions. The cost (cross-type UNION for reporting) is fully mitigated by the DW analytics layer (`dw.fact_application`).

---

## 5. Consequences

| Area | Impact |
|---|---|
| Schema correctness | `gig_request` and `gig_assignment` columns are all `NOT NULL` where appropriate; no ambiguous NULLs |
| Rule Group 5 (nullability) | Gig subsystem does not add unjustified NULLs to the job domain |
| Reporting | Cross-type views require `UNION`; absorbed by `dw.fact_application` |
| RLS | Gig tables need their own RLS policies (to be added in `09_security_rls.sql` v2) |
| Application code | Two separate service modules; shared auth + wallet infrastructure |
| Migration | No impact on existing job/application data |
| Future unification | Possible via super-type table without breaking existing FKs |
