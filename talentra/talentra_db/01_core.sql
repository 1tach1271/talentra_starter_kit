set timezone = 'UTC';
create extension if not exists pg_trgm;
create extension if not exists btree_gist;

create or replace function fn_set_updated_at() returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ===== app_user (needed first: audit columns reference it) =====
create table app_user (
  id           bigint generated always as identity primary key,
  email        varchar(320) not null,
  display_name varchar(200) not null,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  created_by   bigint not null default 1 references app_user(id),
  updated_at   timestamptz not null default now(),
  updated_by   bigint not null default 1 references app_user(id),
  deleted_at   timestamptz
);
create unique index uq_app_user_email on app_user (lower(email)) where deleted_at is null;

insert into app_user (email, display_name) values ('system@talentra.local', 'System');

-- ===== MASTER DATA =====
create table currency (
  id bigint generated always as identity primary key,
  code char(3) not null, name varchar(100) not null, minor_unit smallint not null default 2,
  is_active boolean not null default true,
  created_at timestamptz not null default now(), created_by bigint not null default 1 references app_user(id),
  updated_at timestamptz not null default now(), updated_by bigint not null default 1 references app_user(id),
  deleted_at timestamptz,
  constraint uq_currency_code unique (code)
);

create table language (
  id bigint generated always as identity primary key,
  code varchar(10) not null, name varchar(100) not null, native_name varchar(100),
  is_active boolean not null default true,
  created_at timestamptz not null default now(), created_by bigint not null default 1 references app_user(id),
  updated_at timestamptz not null default now(), updated_by bigint not null default 1 references app_user(id),
  deleted_at timestamptz,
  constraint uq_language_code unique (code)
);

create table country (
  id bigint generated always as identity primary key,
  iso2 char(2) not null, iso3 char(3) not null, name varchar(150) not null,
  phone_code varchar(8) not null, currency_id bigint references currency(id),
  is_active boolean not null default true,
  created_at timestamptz not null default now(), created_by bigint not null default 1 references app_user(id),
  updated_at timestamptz not null default now(), updated_by bigint not null default 1 references app_user(id),
  deleted_at timestamptz,
  constraint uq_country_iso2 unique (iso2),
  constraint uq_country_iso3 unique (iso3)
);
create index idx_country_currency_id on country (currency_id);

create table state (
  id bigint generated always as identity primary key,
  country_id bigint not null references country(id),
  code varchar(10) not null, name varchar(150) not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(), created_by bigint not null default 1 references app_user(id),
  updated_at timestamptz not null default now(), updated_by bigint not null default 1 references app_user(id),
  deleted_at timestamptz,
  constraint uq_state_country_id_code unique (country_id, code)
);

create table city (
  id bigint generated always as identity primary key,
  state_id bigint not null references state(id),
  name varchar(150) not null,
  latitude numeric(9,6) check (latitude between -90 and 90),
  longitude numeric(9,6) check (longitude between -180 and 180),
  is_active boolean not null default true,
  created_at timestamptz not null default now(), created_by bigint not null default 1 references app_user(id),
  updated_at timestamptz not null default now(), updated_by bigint not null default 1 references app_user(id),
  deleted_at timestamptz,
  constraint uq_city_state_id_name unique (state_id, name)
);
create index idx_city_name on city using gin (name gin_trgm_ops);

create table skill (
  id bigint generated always as identity primary key,
  code varchar(60) not null, name varchar(200) not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(), created_by bigint not null default 1 references app_user(id),
  updated_at timestamptz not null default now(), updated_by bigint not null default 1 references app_user(id),
  deleted_at timestamptz,
  constraint uq_skill_code unique (code)
);
create index idx_skill_name on skill using gin (name gin_trgm_ops);

create table qualification (
  id bigint generated always as identity primary key,
  code varchar(60) not null, name varchar(200) not null, level_rank smallint not null check (level_rank >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(), created_by bigint not null default 1 references app_user(id),
  updated_at timestamptz not null default now(), updated_by bigint not null default 1 references app_user(id),
  deleted_at timestamptz,
  constraint uq_qualification_code unique (code)
);

create table industry (
  id bigint generated always as identity primary key,
  parent_industry_id bigint references industry(id),
  code varchar(60) not null, name varchar(200) not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(), created_by bigint not null default 1 references app_user(id),
  updated_at timestamptz not null default now(), updated_by bigint not null default 1 references app_user(id),
  deleted_at timestamptz,
  constraint uq_industry_code unique (code),
  constraint ck_industry_not_self_parent check (parent_industry_id is distinct from id)
);
create index idx_industry_parent_industry_id on industry (parent_industry_id);

create table job_role (
  id bigint generated always as identity primary key,
  industry_id bigint references industry(id),
  code varchar(60) not null, name varchar(200) not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(), created_by bigint not null default 1 references app_user(id),
  updated_at timestamptz not null default now(), updated_by bigint not null default 1 references app_user(id),
  deleted_at timestamptz,
  constraint uq_job_role_code unique (code)
);
create index idx_job_role_industry_id on job_role (industry_id);
create index idx_job_role_name on job_role using gin (name gin_trgm_ops);

create table employment_type (
  id bigint generated always as identity primary key,
  code varchar(40) not null, name varchar(100) not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(), created_by bigint not null default 1 references app_user(id),
  updated_at timestamptz not null default now(), updated_by bigint not null default 1 references app_user(id),
  deleted_at timestamptz,
  constraint uq_employment_type_code unique (code)
);

create table work_type (
  id bigint generated always as identity primary key,
  code varchar(40) not null, name varchar(100) not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(), created_by bigint not null default 1 references app_user(id),
  updated_at timestamptz not null default now(), updated_by bigint not null default 1 references app_user(id),
  deleted_at timestamptz,
  constraint uq_work_type_code unique (code)
);

create table job_status (
  id bigint generated always as identity primary key,
  code varchar(40) not null, name varchar(100) not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(), created_by bigint not null default 1 references app_user(id),
  updated_at timestamptz not null default now(), updated_by bigint not null default 1 references app_user(id),
  deleted_at timestamptz,
  constraint uq_job_status_code unique (code)
);

create table application_stage (
  id bigint generated always as identity primary key,
  code varchar(40) not null, name varchar(100) not null, stage_order smallint not null,
  is_terminal boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(), created_by bigint not null default 1 references app_user(id),
  updated_at timestamptz not null default now(), updated_by bigint not null default 1 references app_user(id),
  deleted_at timestamptz,
  constraint uq_application_stage_code unique (code)
);

create table lookup_translation (
  id bigint generated always as identity primary key,
  entity_table varchar(63) not null,
  entity_id bigint not null,
  language_id bigint not null references language(id),
  translated_name varchar(300) not null,
  created_at timestamptz not null default now(), created_by bigint not null default 1 references app_user(id),
  updated_at timestamptz not null default now(), updated_by bigint not null default 1 references app_user(id),
  deleted_at timestamptz,
  constraint uq_lookup_translation_entity unique (entity_table, entity_id, language_id)
);
create index idx_lookup_translation_language_id on lookup_translation (language_id);

-- ===== STUBS (owners extend in their own files) =====
create table organisation (
  id bigint generated always as identity primary key,
  name varchar(300) not null,
  country_id bigint references country(id),
  industry_id bigint references industry(id),
  is_active boolean not null default true,
  created_at timestamptz not null default now(), created_by bigint not null default 1 references app_user(id),
  updated_at timestamptz not null default now(), updated_by bigint not null default 1 references app_user(id),
  deleted_at timestamptz
);
create index idx_organisation_country_id on organisation (country_id);
create index idx_organisation_industry_id on organisation (industry_id);
create index idx_organisation_name on organisation using gin (name gin_trgm_ops);

create table candidate_profile (
  id bigint generated always as identity primary key,
  app_user_id bigint not null references app_user(id),
  full_name varchar(300) not null,
  headline varchar(300),
  phone_e164 varchar(16) check (phone_e164 ~ '^\+[1-9][0-9]{6,14}$'),
  city_id bigint references city(id),
  total_experience_months integer not null default 0 check (total_experience_months >= 0),
  created_at timestamptz not null default now(), created_by bigint not null default 1 references app_user(id),
  updated_at timestamptz not null default now(), updated_by bigint not null default 1 references app_user(id),
  deleted_at timestamptz
);
create unique index uq_candidate_profile_app_user_id on candidate_profile (app_user_id) where deleted_at is null;
create index idx_candidate_profile_city_id on candidate_profile (city_id);
create index idx_candidate_profile_full_name on candidate_profile using gin (full_name gin_trgm_ops);

create table job (
  id bigint generated always as identity primary key,
  organisation_id bigint not null references organisation(id),
  job_role_id bigint references job_role(id),
  employment_type_id bigint not null references employment_type(id),
  work_type_id bigint not null references work_type(id),
  job_status_id bigint not null references job_status(id),
  city_id bigint references city(id),
  title varchar(300) not null,
  salary_min numeric(14,2) check (salary_min >= 0),
  salary_max numeric(14,2) check (salary_max >= 0),
  salary_currency_id bigint references currency(id),
  published_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now(), created_by bigint not null default 1 references app_user(id),
  updated_at timestamptz not null default now(), updated_by bigint not null default 1 references app_user(id),
  deleted_at timestamptz,
  constraint ck_job_salary_range check (salary_max is null or salary_min is null or salary_max >= salary_min),
  constraint ck_job_salary_currency check ((salary_min is null and salary_max is null) or salary_currency_id is not null),
  constraint ck_job_expiry check (expires_at is null or published_at is null or expires_at > published_at)
);
create index idx_job_organisation_id on job (organisation_id);
create index idx_job_job_role_id on job (job_role_id);
create index idx_job_city_id on job (city_id);
create index idx_job_status_published on job (job_status_id, published_at desc);
create index idx_job_title on job using gin (title gin_trgm_ops);

-- ===== updated_at triggers on every table =====
do $$
declare t record;
begin
  for t in select table_name from information_schema.columns
           where table_schema = 'public' and column_name = 'updated_at' loop
    execute format('create trigger trg_%1$s_updated_at before update on %1$I for each row execute function fn_set_updated_at()', t.table_name);
  end loop;
end $$;

-- ===== minimal seed =====
insert into currency (code, name) values ('INR','Indian Rupee'),('USD','US Dollar'),('EUR','Euro');
insert into language (code, name, native_name) values ('en','English','English'),('hi','Hindi','हिन्दी'),('ta','Tamil','தமிழ்');
insert into employment_type (code, name) values ('full_time','Full time'),('part_time','Part time'),('contract','Contract'),('internship','Internship'),('gig','Gig');
insert into work_type (code, name) values ('onsite','On-site'),('remote','Remote'),('hybrid','Hybrid');
insert into job_status (code, name) values ('draft','Draft'),('published','Published'),('paused','Paused'),('closed','Closed');
insert into application_stage (code, name, stage_order, is_terminal) values
  ('applied','Applied',1,false),('shortlisted','Shortlisted',2,false),('interviewed','Interviewed',3,false),
  ('offered','Offered',4,false),('joined','Joined',5,true),('rejected','Rejected',6,true);
