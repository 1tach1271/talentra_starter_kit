-- 15_api_views.sql
-- API views for the UI / application layer
-- Depends on: all preceding schema files (01_core through 14_data_dictionary)
-- Owner: Team (common Phase 1)
--
-- Naming convention: v_<name> (project convention §15)
-- All views use CREATE OR REPLACE so re-running this file is safe.
-- Soft-deleted rows are always excluded via WHERE deleted_at IS NULL.
-- ─────────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────────
-- v_candidate_search
-- Flat search card for the candidate directory shown to recruiters.
-- skill_names is NULL when the candidate has no skills recorded.
-- experience_band comes from the DW dimension which is refreshed by sp_refresh_dw.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace view v_candidate_search as
select
    cp.id,
    cp.full_name,
    cp.headline,
    ci.name                                              as city_name,
    dc.experience_band,
    (
        select array_agg(s.name order by s.name)
        from candidate_skill cs
        join skill s on s.id = cs.skill_id
        where cs.candidate_profile_id = cp.id
          and cs.deleted_at is null
    )                                                    as skill_names,
    cp.expected_salary,
    cp.is_open_to_work
from candidate_profile cp
left join city ci on ci.id = cp.city_id
left join dw.dim_candidate dc on dc.candidate_profile_id = cp.id
where cp.deleted_at is null;

comment on view v_candidate_search is
    'Flat search card per candidate: name, headline, city, experience band, skills array, salary expectation and open-to-work flag.';

grant select on v_candidate_search to app_candidate, app_recruiter, app_admin;

-- ─────────────────────────────────────────────────────────────────────────────
-- v_job_search
-- Published job listings for the job board.
-- Only returns jobs whose status is "published".
-- ─────────────────────────────────────────────────────────────────────────────
create or replace view v_job_search as
select
    j.id,
    j.title,
    o.name                                               as org_name,
    ci.name                                              as city_name,
    jr.name                                              as role_name,
    j.salary_min,
    j.salary_max,
    wt.name                                              as work_type_name,
    et.name                                              as emp_type_name,
    j.published_at,
    j.is_open_to_consultants
from job j
join job_status js     on js.id = j.job_status_id  and js.code = 'published'
join organisation o    on o.id  = j.organisation_id
left join city ci      on ci.id = j.city_id
left join job_role jr  on jr.id = j.job_role_id
join work_type wt      on wt.id = j.work_type_id
join employment_type et on et.id = j.employment_type_id
where j.deleted_at is null;

comment on view v_job_search is
    'Published job listings with organisation, location, role, salary range, work type and consultant-open flag.';

grant select on v_job_search to app_candidate, app_recruiter, app_admin;

-- ─────────────────────────────────────────────────────────────────────────────
-- v_application_pipeline
-- Aggregate count of applications per job per pipeline stage.
-- Used by the recruiter kanban / funnel board.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace view v_application_pipeline as
select
    j.id                                                 as job_id,
    j.title                                              as job_title,
    o.name                                               as org_name,
    ast.code                                             as stage_code,
    ast.stage_order,
    count(a.id)                                          as application_count
from application a
join job j             on j.id   = a.job_id
join organisation o    on o.id   = j.organisation_id
join application_stage ast on ast.id = a.application_stage_id
where a.deleted_at is null
  and j.deleted_at is null
group by j.id, j.title, o.name, ast.code, ast.stage_order;

comment on view v_application_pipeline is
    'Per-job, per-stage application counts for the recruiter pipeline / kanban view.';

grant select on v_application_pipeline to app_candidate, app_recruiter, app_admin;

-- ─────────────────────────────────────────────────────────────────────────────
-- v_recruiter_inbox
-- One row per application; gives recruiters the information they need to triage
-- inbound applications without hitting multiple tables.
-- job_organisation_id is exposed so RLS policies can filter by org at the app layer.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace view v_recruiter_inbox as
select
    a.id                                                 as application_id,
    j.title                                              as job_title,
    cp.full_name                                         as candidate_name,
    ci.name                                              as candidate_city,
    a.applied_at,
    ast.code                                             as stage_code,
    j.organisation_id                                    as job_organisation_id
from application a
join job j             on j.id   = a.job_id
join candidate_profile cp on cp.id = a.candidate_profile_id
left join city ci      on ci.id  = cp.city_id
join application_stage ast on ast.id = a.application_stage_id
where a.deleted_at is null
  and j.deleted_at is null
  and cp.deleted_at is null;

comment on view v_recruiter_inbox is
    'One row per application with job title, candidate name, city, applied_at, stage and owning organisation id for RLS filtering.';

grant select on v_recruiter_inbox to app_candidate, app_recruiter, app_admin;

-- ─────────────────────────────────────────────────────────────────────────────
-- v_gig_requests_open
-- Open gig requests available for gig workers to browse and apply to.
-- Filtered to gig_status code "open" only.
-- pay_currency_code is denormalised here to avoid a second round-trip.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace view v_gig_requests_open as
select
    gr.id,
    gr.title,
    o.name                                               as org_name,
    ci.name                                              as city_name,
    gr.starts_at,
    gr.ends_at,
    gr.pay_amount,
    cur.code                                             as pay_currency_code,
    gr.openings
from gig_request gr
join gig_status gs     on gs.id  = gr.gig_status_id    and gs.code = 'open'
join organisation o    on o.id   = gr.organisation_id
left join city ci      on ci.id  = gr.city_id
join currency cur      on cur.id = gr.pay_currency_id
where gr.deleted_at is null;

comment on view v_gig_requests_open is
    'Open gig requests with organisation, location, window, pay and available openings.';

grant select on v_gig_requests_open to app_candidate, app_recruiter, app_admin;

-- ─────────────────────────────────────────────────────────────────────────────
-- v_candidate_profile_full
-- Complete profile snapshot for the candidate profile page.
-- education_summary aggregates the most recent qualification label.
-- skill_names is an ordered array of all skill names for the candidate.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace view v_candidate_profile_full as
select
    cp.id,
    cp.full_name,
    cp.headline,
    cp.contact_email,
    cp.phone_e164,
    ci.name                                                  as city_name,
    cp.total_experience_months,
    cp.expected_salary,
    cur.code                                                 as expected_salary_currency_code,
    cp.notice_period_days,
    cp.is_open_to_work,
    cp.profile_completeness,
    -- aggregated skills
    (
        select array_agg(s.name order by s.name)
        from candidate_skill cs
        join skill s on s.id = cs.skill_id
        where cs.candidate_profile_id = cp.id
          and cs.deleted_at is null
    )                                                        as skill_names,
    -- latest education entry (institution + qualification name)
    (
        select q.name || ' — ' || ce.institution
        from candidate_education ce
        join qualification q on q.id = ce.qualification_id
        where ce.candidate_profile_id = cp.id
          and ce.deleted_at is null
        order by coalesce(ce.end_date, '9999-12-31') desc
        limit 1
    )                                                        as education_summary,
    cp.linkedin_url,
    cp.github_url,
    cp.portfolio_url
from candidate_profile cp
left join city ci  on ci.id  = cp.city_id
left join currency cur on cur.id = cp.expected_salary_currency_id
where cp.deleted_at is null;

comment on view v_candidate_profile_full is
    'Full candidate profile snapshot: personal details, city, experience, skills array, latest education summary, links and open-to-work flag.';

grant select on v_candidate_profile_full to app_candidate, app_recruiter, app_admin;

-- ─────────────────────────────────────────────────────────────────────────────
-- v_org_hiring_kpi
-- Wraps the materialized view dw.mv_organisation_hiring_kpi with cleaner
-- column names for consumption by the recruiter dashboard.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace view v_org_hiring_kpi as
select
    organisation_id,
    organisation_name                                    as org_name,
    jobs_with_applications,
    application_count                                    as total_applications,
    joined_count                                         as total_joined,
    join_rate_pct
from dw.mv_organisation_hiring_kpi;

comment on view v_org_hiring_kpi is
    'Organisation-level hiring KPIs (jobs, applications, joined, join-rate) sourced from the DW materialized view.';

grant select on v_org_hiring_kpi to app_candidate, app_recruiter, app_admin;
