call sp_create_lookup('org_type');
call sp_create_lookup('verification_status');
call sp_create_lookup('identifier_type');
call sp_create_lookup('sourcing_request_status');
call sp_create_lookup('outreach_status');
insert into org_type (code, name) values ('employer','Employer'),('consultancy','Consultancy'),('agency','Staffing agency');
insert into verification_status (code, name) values ('pending','Pending'),('verified','Verified'),('rejected','Rejected');
insert into identifier_type (code, name) values ('gstin','GSTIN'),('pan','PAN'),('cin','CIN'),('ein','EIN');
insert into sourcing_request_status (code, name) values ('open','Open'),('in_progress','In progress'),('fulfilled','Fulfilled'),('cancelled','Cancelled');
insert into outreach_status (code, name) values ('planned','Planned'),('sending','Sending'),('sent','Sent'),('failed','Failed');

alter table organisation
  add column legal_name varchar(300),
  add column org_type_id bigint references org_type(id),
  add column parent_organisation_id bigint references organisation(id),
  add column verification_status_id bigint references verification_status(id),
  add column website varchar(300),
  add constraint ck_organisation_not_self_parent check (parent_organisation_id is distinct from id);

create table organisation_identifier (
  id bigint generated always as identity primary key,
  organisation_id bigint not null references organisation(id),
  identifier_type_id bigint not null references identifier_type(id),
  identifier_token varchar(200) not null
);
call sp_add_audit('organisation_identifier');
create unique index uq_organisation_identifier_value on organisation_identifier (identifier_type_id, identifier_token) where deleted_at is null;

create table organisation_verification (
  id bigint generated always as identity primary key,
  organisation_id bigint not null references organisation(id),
  verification_status_id bigint not null references verification_status(id),
  provider_reference varchar(100),
  verified_at timestamptz,
  note varchar(500)
);
call sp_add_audit('organisation_verification');

create table recruiter (
  id bigint generated always as identity primary key,
  app_user_id bigint not null references app_user(id),
  organisation_id bigint not null references organisation(id),
  job_title varchar(200)
);
call sp_add_audit('recruiter');
create unique index uq_recruiter_user_org on recruiter (app_user_id, organisation_id) where deleted_at is null;
create index idx_recruiter_organisation_id on recruiter (organisation_id);

create table sourcing_request (
  id bigint generated always as identity primary key,
  organisation_id bigint not null references organisation(id),
  recruiter_id bigint not null references recruiter(id),
  job_role_id bigint references job_role(id),
  sourcing_request_status_id bigint not null references sourcing_request_status(id),
  title varchar(300) not null,
  openings integer not null default 1 check (openings > 0),
  due_date date,
  is_open_to_consultants boolean not null default false
);
call sp_add_audit('sourcing_request');

create table sourcing_request_assignment (
  id bigint generated always as identity primary key,
  sourcing_request_id bigint not null references sourcing_request(id),
  consultant_organisation_id bigint not null references organisation(id),
  accepted_at timestamptz,
  constraint uq_sourcing_request_assignment_pair unique (sourcing_request_id, consultant_organisation_id)
);
call sp_add_audit('sourcing_request_assignment');

create table outreach_batch (
  id bigint generated always as identity primary key,
  sourcing_request_id bigint not null references sourcing_request(id),
  recruiter_id bigint not null references recruiter(id),
  outreach_status_id bigint not null references outreach_status(id),
  planned_at timestamptz,
  sent_at timestamptz,
  recipient_count integer not null default 0 check (recipient_count >= 0),
  constraint ck_outreach_batch_sent check (sent_at is null or planned_at is null or sent_at >= planned_at)
);
call sp_add_audit('outreach_batch');

create table outreach_recipient (
  id bigint generated always as identity primary key,
  outreach_batch_id bigint not null references outreach_batch(id),
  candidate_profile_id bigint not null references candidate_profile(id),
  delivery_reference varchar(100),
  constraint uq_outreach_recipient_pair unique (outreach_batch_id, candidate_profile_id)
);
call sp_add_audit('outreach_recipient');

create table shortlist (
  id bigint generated always as identity primary key,
  sourcing_request_id bigint references sourcing_request(id),
  recruiter_id bigint not null references recruiter(id),
  name varchar(200) not null
);
call sp_add_audit('shortlist');

create table shortlist_member (
  id bigint generated always as identity primary key,
  shortlist_id bigint not null references shortlist(id),
  candidate_profile_id bigint not null references candidate_profile(id),
  note varchar(500),
  constraint uq_shortlist_member_pair unique (shortlist_id, candidate_profile_id)
);
call sp_add_audit('shortlist_member');
