-- 05b_jobs_applications_missing.sql
-- Phase 1 · Jobs and Applications module — missing tables and columns
-- Depends on: 01_core.sql, 01b_helpers.sql, 02_admin_licence.sql,
--             03_org_sourcing.sql, 04_candidate.sql, 05_jobs_applications.sql
-- Owner: Team (common Phase 1)

-- ─────────────────────────────────────────────────────────────────────────────
-- Lookup tables needed by this file
-- ─────────────────────────────────────────────────────────────────────────────
call sp_create_lookup('job_category');
call sp_create_lookup('search_filter_type');
call sp_create_lookup('block_target_type');

-- Job categories (docket Section 2: 8 distinct job categories)
insert into job_category (code, name) values
  ('gig',                  'Gig / project-based'),
  ('general_staffing',     'General staffing'),
  ('professional_staffing','Professional staffing'),
  ('permanent',            'Permanent full-time'),
  ('apprentice',           'Apprentice hiring'),
  ('campus_fresher',       'Campus / fresher hiring'),
  ('consultant_marketplace','Consultant marketplace'),
  ('managed_remote',       'Managed remote workforce');

-- search_filter_type: classifies what the candidate searched / filtered on
insert into search_filter_type (code, name) values
  ('keyword',       'Keyword'),
  ('location',      'Location'),
  ('job_role',      'Job role'),
  ('skill',         'Skill'),
  ('salary_range',  'Salary range'),
  ('experience',    'Experience range'),
  ('work_type',     'Work type'),
  ('employment_type','Employment type'),
  ('job_category',  'Job category');

-- block_target_type: who/what can be blocked by a candidate (Rule 3.3 in docket)
insert into block_target_type (code, name) values
  ('organisation', 'Organisation / employer'),
  ('recruiter',    'Recruiter (individual)'),
  ('consultant',   'Consultant (individual)');

-- ─────────────────────────────────────────────────────────────────────────────
-- Add job_category_id and is_open_to_consultants to the job table
--
-- job_category_id: mandatory — every job belongs to exactly one of the 8
--   categories. Nullable on ALTER to allow existing rows; tightened below.
-- is_open_to_consultants: docket Rule — a consultant may only work on
--   requirements that are open to consultants. Enforced here at data level.
--   Default false: unless explicitly opened, consultants cannot source.
-- ─────────────────────────────────────────────────────────────────────────────
alter table job
  add column job_category_id        bigint  references job_category(id),
  add column is_open_to_consultants boolean not null default false;

-- Back-fill existing rows: assign the most generic permanent category so the
-- not-null constraint we apply next succeeds on a non-empty database.
update job set job_category_id = (select id from job_category where code = 'permanent')
where job_category_id is null;

-- Now enforce NOT NULL
alter table job alter column job_category_id set not null;

create index idx_job_job_category_id on job (job_category_id);
create index idx_job_open_to_consultants on job (is_open_to_consultants) where is_open_to_consultants;

-- ─────────────────────────────────────────────────────────────────────────────
-- job_search_history
-- Tier 2 "should be modelled" (docket Section 4: "Job search and application
-- history for candidates").
-- Records each search a candidate executes, including the raw query text and
-- the structured filters applied.  Append-only (history must not be altered).
-- result_count: how many jobs matched, captured at search time for analytics.
-- ─────────────────────────────────────────────────────────────────────────────
create table job_search_history (
  id                   bigint      generated always as identity primary key,
  candidate_profile_id bigint      not null references candidate_profile(id),
  query_text           varchar(500),           -- nullable: filter-only searches have no keyword
  city_id              bigint      references city(id),        -- nullable: not filtered by city
  job_category_id      bigint      references job_category(id),-- nullable: not filtered by category
  result_count         integer     not null default 0 check (result_count >= 0),
  searched_at          timestamptz not null default now()
);
call sp_add_audit('job_search_history', false);
call sp_make_append_only('job_search_history');
create index idx_job_search_history_candidate_time
  on job_search_history (candidate_profile_id, searched_at desc);

-- job_search_filter
-- Stores each individual filter applied during a search (one row per filter).
-- Normalised away from job_search_history to support analytics across filter
-- types without wide sparse columns.
create table job_search_filter (
  id                     bigint      generated always as identity primary key,
  job_search_history_id  bigint      not null references job_search_history(id),
  search_filter_type_id  bigint      not null references search_filter_type(id),
  filter_value           varchar(300) not null   -- stored as text; type gives context
);
call sp_add_audit('job_search_filter', false);
create index idx_job_search_filter_history
  on job_search_filter (job_search_history_id);
create index idx_job_search_filter_type_value
  on job_search_filter (search_filter_type_id, filter_value);

-- ─────────────────────────────────────────────────────────────────────────────
-- Extended block_list
--
-- The existing block_list (04_candidate.sql) only covers candidate → organisation.
-- The docket requires candidates to also block individual recruiters and
-- consultants (actors, not organisations).
--
-- Design decision: extend block_list with a nullable recruiter_app_user_id
-- column and a block_target_type_id so the same table handles all three cases
-- without duplicating audit machinery.  Exactly one of (organisation_id,
-- blocked_app_user_id) must be set — enforced by the check constraint below.
--
-- blocked_app_user_id: the app_user of the recruiter or consultant being blocked.
-- block_target_type_id: 'organisation', 'recruiter', or 'consultant'.
-- ─────────────────────────────────────────────────────────────────────────────
alter table block_list
  add column block_target_type_id bigint references block_target_type(id),
  add column blocked_app_user_id  bigint references app_user(id);

-- Back-fill existing rows: all existing rows are organisation-level blocks
update block_list
set block_target_type_id = (select id from block_target_type where code = 'organisation')
where block_target_type_id is null;

-- Enforce NOT NULL now that existing rows are back-filled
alter table block_list alter column block_target_type_id set not null;

-- Exactly one of organisation_id / blocked_app_user_id must be populated
alter table block_list
  add constraint ck_block_list_target_xor
    check (
      (organisation_id    is not null and blocked_app_user_id is null) or
      (organisation_id    is null     and blocked_app_user_id is not null)
    );

-- The original unique index covers candidate+organisation pairs.
-- Add a second partial unique index for candidate+user (recruiter/consultant) blocks.
create unique index uq_block_list_candidate_user
  on block_list (candidate_profile_id, blocked_app_user_id)
  where blocked_app_user_id is not null and deleted_at is null;

create index idx_block_list_blocked_app_user_id
  on block_list (blocked_app_user_id)
  where blocked_app_user_id is not null;
