create schema if not exists dw;

create table dw.dim_date (
  id integer primary key,
  full_date date not null unique,
  year_no smallint not null, quarter_no smallint not null, month_no smallint not null,
  day_no smallint not null, week_no smallint not null, day_name varchar(10) not null,
  is_weekend boolean not null
);
insert into dw.dim_date
select to_char(d, 'YYYYMMDD')::int, d, extract(year from d), extract(quarter from d), extract(month from d),
       extract(day from d), extract(week from d), trim(to_char(d, 'Day')), extract(isodow from d) in (6, 7)
from generate_series(date '2025-01-01', date '2028-12-31', interval '1 day') d;

create table dw.dim_organisation (
  id bigint generated always as identity primary key,
  organisation_id bigint not null,
  name varchar(300) not null,
  industry_name varchar(200), country_name varchar(150), verification_code varchar(60),
  valid_from timestamptz not null, valid_to timestamptz not null, is_current boolean not null
);
create index idx_dim_organisation_current on dw.dim_organisation (organisation_id) where is_current;

create table dw.dim_job (
  id bigint generated always as identity primary key,
  job_id bigint not null,
  title varchar(300) not null,
  job_status_code varchar(60), role_name varchar(200), city_name varchar(150),
  valid_from timestamptz not null, valid_to timestamptz not null, is_current boolean not null
);
create index idx_dim_job_current on dw.dim_job (job_id) where is_current;

create table dw.dim_candidate (
  id bigint generated always as identity primary key,
  candidate_profile_id bigint not null unique,
  city_name varchar(150),
  experience_band varchar(20) not null
);

create table dw.fact_application (
  id bigint generated always as identity primary key,
  application_id bigint not null unique,
  dim_job_id bigint not null references dw.dim_job(id),
  dim_organisation_id bigint not null references dw.dim_organisation(id),
  dim_candidate_id bigint not null references dw.dim_candidate(id),
  dim_date_id integer not null references dw.dim_date(id),
  stage_code varchar(60) not null,
  is_terminal boolean not null,
  loaded_at timestamptz not null default now()
);
create index idx_fact_application_date_stage on dw.fact_application (dim_date_id, stage_code);
create index idx_fact_application_dim_organisation_id on dw.fact_application (dim_organisation_id);

create table dw.fact_payment (
  id bigint generated always as identity primary key,
  payment_order_id bigint not null unique,
  dim_organisation_id bigint not null references dw.dim_organisation(id),
  dim_date_id integer not null references dw.dim_date(id),
  amount numeric(14,2) not null,
  currency_code char(3) not null,
  status_code varchar(60) not null,
  loaded_at timestamptz not null default now()
);

create or replace procedure dw.sp_refresh_dw() language plpgsql as $$
begin
  create temp table src_org on commit drop as
    select o.id, o.name, i.name industry_name, c.name country_name, v.code verification_code
    from organisation o left join industry i on i.id = o.industry_id left join country c on c.id = o.country_id
    left join verification_status v on v.id = o.verification_status_id where o.deleted_at is null;
  update dw.dim_organisation d set valid_to = now(), is_current = false
  from src_org s where d.organisation_id = s.id and d.is_current
    and (d.name, d.industry_name, d.country_name, d.verification_code) is distinct from (s.name, s.industry_name, s.country_name, s.verification_code);
  insert into dw.dim_organisation (organisation_id, name, industry_name, country_name, verification_code, valid_from, valid_to, is_current)
  select s.id, s.name, s.industry_name, s.country_name, s.verification_code, now(), 'infinity', true from src_org s
  where not exists (select 1 from dw.dim_organisation d where d.organisation_id = s.id and d.is_current);

  create temp table src_job on commit drop as
    select j.id, j.title, js.code job_status_code, r.name role_name, c.name city_name
    from job j join job_status js on js.id = j.job_status_id left join job_role r on r.id = j.job_role_id left join city c on c.id = j.city_id
    where j.deleted_at is null;
  update dw.dim_job d set valid_to = now(), is_current = false
  from src_job s where d.job_id = s.id and d.is_current
    and (d.title, d.job_status_code, d.role_name, d.city_name) is distinct from (s.title, s.job_status_code, s.role_name, s.city_name);
  insert into dw.dim_job (job_id, title, job_status_code, role_name, city_name, valid_from, valid_to, is_current)
  select s.id, s.title, s.job_status_code, s.role_name, s.city_name, now(), 'infinity', true from src_job s
  where not exists (select 1 from dw.dim_job d where d.job_id = s.id and d.is_current);

  insert into dw.dim_candidate (candidate_profile_id, city_name, experience_band)
  select cp.id, c.name, case when cp.total_experience_months < 12 then '0-1' when cp.total_experience_months < 36 then '1-3'
         when cp.total_experience_months < 72 then '3-6' else '6+' end
  from candidate_profile cp left join city c on c.id = cp.city_id where cp.deleted_at is null
  on conflict (candidate_profile_id) do update set city_name = excluded.city_name, experience_band = excluded.experience_band;

  insert into dw.fact_application (application_id, dim_job_id, dim_organisation_id, dim_candidate_id, dim_date_id, stage_code, is_terminal)
  select a.id, dj.id, dorg.id, dc.id, to_char(a.applied_at, 'YYYYMMDD')::int, s.code, s.is_terminal
  from application a
  join application_stage s on s.id = a.application_stage_id
  join job j on j.id = a.job_id
  join dw.dim_job dj on dj.job_id = a.job_id and dj.is_current
  join dw.dim_organisation dorg on dorg.organisation_id = j.organisation_id and dorg.is_current
  join dw.dim_candidate dc on dc.candidate_profile_id = a.candidate_profile_id
  where a.deleted_at is null
  on conflict (application_id) do update set stage_code = excluded.stage_code, is_terminal = excluded.is_terminal, loaded_at = now();

  insert into dw.fact_payment (payment_order_id, dim_organisation_id, dim_date_id, amount, currency_code, status_code)
  select p.id, dorg.id, to_char(coalesce(p.paid_at, p.created_at), 'YYYYMMDD')::int, p.amount, cur.code, ps.code
  from payment_order p join currency cur on cur.id = p.currency_id join payment_status ps on ps.id = p.payment_status_id
  join dw.dim_organisation dorg on dorg.organisation_id = p.organisation_id and dorg.is_current
  on conflict (payment_order_id) do update set status_code = excluded.status_code, loaded_at = now();

  refresh materialized view dw.mv_daily_application_funnel;
  refresh materialized view dw.mv_organisation_hiring_kpi;
end $$;

create materialized view dw.mv_daily_application_funnel as
select d.full_date, f.stage_code, count(*) as application_count
from dw.fact_application f join dw.dim_date d on d.id = f.dim_date_id
group by d.full_date, f.stage_code;
create unique index uq_mv_daily_application_funnel on dw.mv_daily_application_funnel (full_date, stage_code);

create materialized view dw.mv_organisation_hiring_kpi as
select o.organisation_id, o.name as organisation_name,
       count(distinct f.dim_job_id) as jobs_with_applications,
       count(*) as application_count,
       count(*) filter (where f.stage_code = 'joined') as joined_count,
       round(100.0 * count(*) filter (where f.stage_code = 'joined') / nullif(count(*), 0), 2) as join_rate_pct
from dw.fact_application f join dw.dim_organisation o on o.id = f.dim_organisation_id
group by o.organisation_id, o.name;
create unique index uq_mv_organisation_hiring_kpi on dw.mv_organisation_hiring_kpi (organisation_id);
