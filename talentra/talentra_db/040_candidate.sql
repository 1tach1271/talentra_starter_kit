call sp_create_lookup('skill_proficiency');
call sp_create_lookup('assessment_type');
call sp_create_lookup('activity_type');
insert into skill_proficiency (code, name) values ('beginner','Beginner'),('intermediate','Intermediate'),('advanced','Advanced'),('expert','Expert');
insert into assessment_type (code, name) values ('coding','Coding test'),('aptitude','Aptitude test'),('language','Language test');
insert into activity_type (code, name) values ('login','Login'),('profile_update','Profile update'),('job_view','Job view'),('job_apply','Job apply'),('resume_upload','Resume upload');

alter table candidate_profile
  add column contact_email varchar(320),
  add column alternate_phone_e164 varchar(16) check (alternate_phone_e164 ~ '^\+[1-9][0-9]{6,14}$'),
  add column date_of_birth date check (date_of_birth <= current_date),
  add column preferred_language_id bigint references language(id),
  add column expected_salary numeric(14,2) check (expected_salary >= 0),
  add column expected_salary_currency_id bigint references currency(id),
  add column notice_period_days integer check (notice_period_days between 0 and 365),
  add column is_open_to_work boolean not null default true,
  add column profile_completeness smallint not null default 0 check (profile_completeness between 0 and 100),
  add constraint ck_candidate_profile_salary_currency check (expected_salary is null or expected_salary_currency_id is not null);

create table candidate_education (
  id bigint generated always as identity primary key,
  candidate_profile_id bigint not null references candidate_profile(id),
  qualification_id bigint not null references qualification(id),
  institution varchar(300) not null,
  field_of_study varchar(200),
  start_date date, end_date date,
  grade varchar(30),
  constraint ck_candidate_education_dates check (end_date is null or start_date is null or end_date >= start_date)
);
call sp_add_audit('candidate_education');

create table candidate_experience (
  id bigint generated always as identity primary key,
  candidate_profile_id bigint not null references candidate_profile(id),
  job_role_id bigint references job_role(id),
  employment_type_id bigint references employment_type(id),
  employer_name varchar(300) not null,
  job_title varchar(300) not null,
  start_date date not null, end_date date,
  is_current boolean not null default false,
  description text,
  constraint ck_candidate_experience_dates check (end_date is null or end_date >= start_date),
  constraint ck_candidate_experience_current check (not is_current or end_date is null)
);
call sp_add_audit('candidate_experience');

create table candidate_skill (
  id bigint generated always as identity primary key,
  candidate_profile_id bigint not null references candidate_profile(id),
  skill_id bigint not null references skill(id),
  skill_proficiency_id bigint references skill_proficiency(id),
  years_experience numeric(4,1) check (years_experience >= 0),
  constraint uq_candidate_skill_pair unique (candidate_profile_id, skill_id)
);
call sp_add_audit('candidate_skill');
create index idx_candidate_skill_skill_candidate on candidate_skill (skill_id, candidate_profile_id);

create table candidate_language (
  id bigint generated always as identity primary key,
  candidate_profile_id bigint not null references candidate_profile(id),
  language_id bigint not null references language(id),
  skill_proficiency_id bigint references skill_proficiency(id),
  constraint uq_candidate_language_pair unique (candidate_profile_id, language_id)
);
call sp_add_audit('candidate_language');

create table resume_version (
  id bigint generated always as identity primary key,
  candidate_profile_id bigint not null references candidate_profile(id),
  version_no integer not null check (version_no > 0),
  file_reference varchar(500) not null,
  file_sha256 char(64),
  is_primary boolean not null default false,
  constraint uq_resume_version_candidate_version unique (candidate_profile_id, version_no)
);
call sp_add_audit('resume_version');
create unique index uq_resume_version_primary on resume_version (candidate_profile_id) where is_primary and deleted_at is null;

create table candidate_project (
  id bigint generated always as identity primary key,
  candidate_profile_id bigint not null references candidate_profile(id),
  title varchar(300) not null, project_url varchar(500),
  start_date date, end_date date, description text,
  constraint ck_candidate_project_dates check (end_date is null or start_date is null or end_date >= start_date)
);
call sp_add_audit('candidate_project');

create table candidate_assessment (
  id bigint generated always as identity primary key,
  candidate_profile_id bigint not null references candidate_profile(id),
  assessment_type_id bigint not null references assessment_type(id),
  score numeric(5,2) not null check (score between 0 and 100),
  taken_at timestamptz not null
);
call sp_add_audit('candidate_assessment');

create table candidate_activity_log (
  id bigint generated always as identity primary key,
  candidate_profile_id bigint not null references candidate_profile(id),
  activity_type_id bigint not null references activity_type(id),
  detail jsonb,
  occurred_at timestamptz not null default now()
);
call sp_add_audit('candidate_activity_log', false);
call sp_make_append_only('candidate_activity_log');
create index idx_candidate_activity_log_candidate_time on candidate_activity_log (candidate_profile_id, occurred_at desc);

create table block_list (
  id bigint generated always as identity primary key,
  candidate_profile_id bigint not null references candidate_profile(id),
  organisation_id bigint not null references organisation(id),
  reason varchar(300)
);
call sp_add_audit('block_list');
create unique index uq_block_list_pair on block_list (candidate_profile_id, organisation_id) where deleted_at is null;
