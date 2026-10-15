-- 04b_candidate_missing.sql
-- Phase 1 · Profile module — missing tables and columns
-- Depends on: 01_core.sql, 01b_helpers.sql, 03_org_sourcing.sql, 04_candidate.sql
-- Owner: Team (common Phase 1)

-- ─────────────────────────────────────────────────────────────────────────────
-- Lookup tables needed by this file
-- ─────────────────────────────────────────────────────────────────────────────
call sp_create_lookup('course_status');
call sp_create_lookup('referral_status');
call sp_create_lookup('bookmark_entity_type');

insert into course_status (code, name) values
  ('enrolled','Enrolled'),
  ('in_progress','In progress'),
  ('completed','Completed'),
  ('dropped','Dropped');

insert into referral_status (code, name) values
  ('pending','Pending'),
  ('registered','Registered'),
  ('hired','Hired'),
  ('expired','Expired');

-- bookmark_entity_type: what kind of entity was bookmarked / shortlisted
insert into bookmark_entity_type (code, name) values
  ('candidate','Candidate profile'),
  ('job','Job requirement');

-- ─────────────────────────────────────────────────────────────────────────────
-- Extended columns on candidate_profile
-- (gender, nationality — needed for competitor coverage parity with
--  Naukri / Monster / LinkedIn and for analytics segmentation)
-- gender_code and nationality_country_id are nullable: candidate may choose
-- not to disclose. Storing NULL is distinct from "not applicable" (Rule 5).
-- ─────────────────────────────────────────────────────────────────────────────
alter table candidate_profile
  add column gender_code        varchar(20),          -- 'male','female','non_binary','prefer_not_to_say'
  add column nationality_country_id bigint references country(id),
  add column linkedin_url       varchar(500),          -- nullable: not all candidates supply it
  add column github_url         varchar(500),          -- nullable
  add column portfolio_url      varchar(500);          -- nullable

-- ─────────────────────────────────────────────────────────────────────────────
-- resume_template
-- Stores named layout templates that candidates can apply when generating
-- a formatted resume from their profile data.
-- ─────────────────────────────────────────────────────────────────────────────
create table resume_template (
  id               bigint generated always as identity primary key,
  code             varchar(60)  not null,
  name             varchar(200) not null,
  thumbnail_url    varchar(500),              -- nullable: template preview image
  is_active        boolean      not null default true,
  is_default       boolean      not null default false,
  constraint uq_resume_template_code unique (code)
);
call sp_add_audit('resume_template');
-- only one template may be the system default at a time
create unique index uq_resume_template_default on resume_template (is_default) where is_default;

-- Link a resume_version to the template it was rendered with (nullable:
-- versions uploaded as raw files have no template).
alter table resume_version
  add column resume_template_id bigint references resume_template(id),
  add column label              varchar(200);  -- nullable: e.g. "Software Engineer variant"

insert into resume_template (code, name, is_default) values
  ('classic',  'Classic',   true),
  ('modern',   'Modern',    false),
  ('minimal',  'Minimal',   false),
  ('executive','Executive', false);

-- ─────────────────────────────────────────────────────────────────────────────
-- course_enrolment
-- Tier 1 mandatory (docket Section 4 — Profile module scope).
-- Tracks online / offline courses a candidate has enrolled in or completed.
-- course_provider and course_url are nullable: not every course has them.
-- ─────────────────────────────────────────────────────────────────────────────
create table course_enrolment (
  id                   bigint generated always as identity primary key,
  candidate_profile_id bigint      not null references candidate_profile(id),
  course_status_id     bigint      not null references course_status(id),
  course_name          varchar(300) not null,
  course_provider      varchar(300),           -- nullable: self-study / unknown provider
  course_url           varchar(500),           -- nullable
  certificate_url      varchar(500),           -- nullable: issued only on completion
  started_on           date,                   -- nullable: some courses lack a fixed start
  completed_on         date,                   -- nullable: not yet completed
  credential_id        varchar(200),           -- nullable: certificate / badge ID from provider
  constraint ck_course_enrolment_dates
    check (completed_on is null or started_on is null or completed_on >= started_on)
);
call sp_add_audit('course_enrolment');
create index idx_course_enrolment_candidate on course_enrolment (candidate_profile_id);
create index idx_course_enrolment_status    on course_enrolment (course_status_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- profile_view_history
-- Tier 2 "should be modelled" (docket Section 4).
-- Records every distinct view of a candidate profile by a recruiter or
-- employer user.  Append-only (Rule 10: view history is immutable).
-- viewer_app_user_id + viewer_organisation_id together identify the actor;
-- viewer_organisation_id is nullable because a standalone consultant has no
-- owning organisation in all cases.
-- ─────────────────────────────────────────────────────────────────────────────
create table profile_view_history (
  id                      bigint generated always as identity primary key,
  candidate_profile_id    bigint      not null references candidate_profile(id),
  viewer_app_user_id      bigint      not null references app_user(id),
  viewer_organisation_id  bigint      references organisation(id),  -- nullable: see above
  viewed_at               timestamptz not null default now()
);
call sp_add_audit('profile_view_history', false);
call sp_make_append_only('profile_view_history');
create index idx_profile_view_history_candidate_time
  on profile_view_history (candidate_profile_id, viewed_at desc);
create index idx_profile_view_history_viewer_time
  on profile_view_history (viewer_app_user_id, viewed_at desc);

-- ─────────────────────────────────────────────────────────────────────────────
-- shortlist_bookmark_history
-- Tier 2 "should be modelled" (docket Section 4).
-- Immutable audit trail of every bookmark/shortlist action taken by recruiters
-- or employers on a candidate or job.
-- is_added = true  → bookmarked / added to shortlist
-- is_added = false → removed from bookmark / shortlist
-- entity_type_id distinguishes whether a candidate or a job was bookmarked.
-- ─────────────────────────────────────────────────────────────────────────────
create table shortlist_bookmark_history (
  id                     bigint      generated always as identity primary key,
  actor_app_user_id      bigint      not null references app_user(id),
  actor_organisation_id  bigint      references organisation(id),  -- nullable: see profile_view_history
  bookmark_entity_type_id bigint     not null references bookmark_entity_type(id),
  entity_id              bigint      not null,   -- PK of the bookmarked row
  shortlist_id           bigint      references shortlist(id),  -- nullable: ad-hoc bookmark has no shortlist
  is_added               boolean     not null,
  occurred_at            timestamptz not null default now()
);
call sp_add_audit('shortlist_bookmark_history', false);
call sp_make_append_only('shortlist_bookmark_history');
create index idx_shortlist_bookmark_history_actor_time
  on shortlist_bookmark_history (actor_app_user_id, occurred_at desc);
create index idx_shortlist_bookmark_history_entity
  on shortlist_bookmark_history (bookmark_entity_type_id, entity_id, occurred_at desc);

-- ─────────────────────────────────────────────────────────────────────────────
-- referral_tracking
-- Tier 2 "should be modelled" (docket Section 4).
-- A candidate can refer another person using a unique referral code.
-- referred_candidate_profile_id is nullable until the referred person
-- completes registration.
-- ─────────────────────────────────────────────────────────────────────────────
create table referral_tracking (
  id                              bigint      generated always as identity primary key,
  referrer_candidate_profile_id   bigint      not null references candidate_profile(id),
  referral_code                   varchar(60) not null,
  referred_email                  varchar(320) not null,   -- email the invitation was sent to
  referred_candidate_profile_id   bigint      references candidate_profile(id),  -- nullable until registered
  referral_status_id              bigint      not null references referral_status(id),
  referred_at                     timestamptz not null default now(),
  registered_at                   timestamptz,             -- nullable until event fires
  hired_at                        timestamptz,             -- nullable until hired
  reward_credited                 boolean     not null default false,
  constraint uq_referral_code unique (referral_code),
  -- a referrer cannot refer the same email twice
  constraint uq_referral_referrer_email unique (referrer_candidate_profile_id, referred_email),
  constraint ck_referral_dates
    check (registered_at is null or registered_at >= referred_at)
);
call sp_add_audit('referral_tracking');
create index idx_referral_tracking_referrer
  on referral_tracking (referrer_candidate_profile_id);
create index idx_referral_tracking_referred_profile
  on referral_tracking (referred_candidate_profile_id)
  where referred_candidate_profile_id is not null;
