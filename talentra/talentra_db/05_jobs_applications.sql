alter table job
  add column sourcing_request_id bigint references sourcing_request(id),
  add column description text,
  add column experience_min_years numeric(4,1) check (experience_min_years >= 0),
  add column experience_max_years numeric(4,1),
  add column openings integer not null default 1 check (openings > 0),
  add column application_deadline timestamptz,
  add constraint ck_job_experience_range check (experience_max_years is null or experience_min_years is null or experience_max_years >= experience_min_years);

create table job_skill (
  id bigint generated always as identity primary key,
  job_id bigint not null references job(id),
  skill_id bigint not null references skill(id),
  is_mandatory boolean not null default true,
  constraint uq_job_skill_pair unique (job_id, skill_id)
);
call sp_add_audit('job_skill');
create index idx_job_skill_skill_job on job_skill (skill_id, job_id);

create table job_qualification (
  id bigint generated always as identity primary key,
  job_id bigint not null references job(id),
  qualification_id bigint not null references qualification(id),
  constraint uq_job_qualification_pair unique (job_id, qualification_id)
);
call sp_add_audit('job_qualification');

create table job_question (
  id bigint generated always as identity primary key,
  job_id bigint not null references job(id),
  question_text varchar(1000) not null,
  is_required boolean not null default false,
  display_order smallint not null default 0
);
call sp_add_audit('job_question');

create table job_position (
  id bigint generated always as identity primary key,
  job_id bigint not null references job(id),
  position_no integer not null check (position_no > 0),
  is_filled boolean not null default false,
  constraint uq_job_position_pair unique (job_id, position_no)
);
call sp_add_audit('job_position');

create table application (
  id bigint generated always as identity primary key,
  job_id bigint not null references job(id),
  candidate_profile_id bigint not null references candidate_profile(id),
  resume_version_id bigint references resume_version(id),
  application_stage_id bigint not null references application_stage(id),
  cover_note varchar(2000),
  expected_salary numeric(14,2) check (expected_salary >= 0),
  salary_currency_id bigint references currency(id),
  applied_at timestamptz not null default now(),
  rejection_reason varchar(300),
  constraint ck_application_salary_currency check (expected_salary is null or salary_currency_id is not null)
);
call sp_add_audit('application');
create unique index uq_application_job_candidate on application (job_id, candidate_profile_id) where deleted_at is null;
create index idx_application_candidate_applied on application (candidate_profile_id, applied_at desc);
create index idx_application_job_stage on application (job_id, application_stage_id);
create index idx_application_applied_at on application (applied_at);

alter table job_position add column filled_application_id bigint references application(id);

create table application_answer (
  id bigint generated always as identity primary key,
  application_id bigint not null references application(id),
  job_question_id bigint not null references job_question(id),
  answer_text varchar(2000) not null,
  constraint uq_application_answer_pair unique (application_id, job_question_id)
);
call sp_add_audit('application_answer');

create table application_history (
  id bigint generated always as identity primary key,
  application_id bigint not null references application(id),
  from_stage_id bigint references application_stage(id),
  to_stage_id bigint not null references application_stage(id),
  changed_at timestamptz not null default now()
);
call sp_add_audit('application_history', false);
call sp_make_append_only('application_history');
create index idx_application_history_application_time on application_history (application_id, changed_at);

create function fn_application_history() returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    insert into application_history (application_id, from_stage_id, to_stage_id, created_by) values (new.id, null, new.application_stage_id, new.created_by);
  elsif new.application_stage_id is distinct from old.application_stage_id then
    insert into application_history (application_id, from_stage_id, to_stage_id, created_by) values (new.id, old.application_stage_id, new.application_stage_id, new.updated_by);
  end if;
  return null;
end $$;
create trigger trg_application_history after insert or update of application_stage_id on application for each row execute function fn_application_history();

create table saved_job (
  id bigint generated always as identity primary key,
  candidate_profile_id bigint not null references candidate_profile(id),
  job_id bigint not null references job(id),
  constraint uq_saved_job_pair unique (candidate_profile_id, job_id)
);
call sp_add_audit('saved_job');
