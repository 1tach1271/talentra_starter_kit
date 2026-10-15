call sp_create_lookup('device_type');
call sp_create_lookup('consent_type');
insert into device_type (code, name) values ('web','Web'),('android','Android'),('ios','iOS'),('desktop','Desktop');
insert into consent_type (code, name) values ('terms','Terms of service'),('privacy','Privacy policy'),('marketing','Marketing communication'),('profile_sharing','Profile sharing with recruiters');

create table app_role (
  id bigint generated always as identity primary key,
  code varchar(60) not null, name varchar(200) not null, description varchar(500),
  constraint uq_app_role_code unique (code)
);
call sp_add_audit('app_role');

create table permission (
  id bigint generated always as identity primary key,
  code varchar(100) not null, name varchar(200) not null,
  constraint uq_permission_code unique (code)
);
call sp_add_audit('permission');

create table role_permission (
  id bigint generated always as identity primary key,
  app_role_id bigint not null references app_role(id),
  permission_id bigint not null references permission(id),
  constraint uq_role_permission_pair unique (app_role_id, permission_id)
);
call sp_add_audit('role_permission');

create table app_user_role (
  id bigint generated always as identity primary key,
  app_user_id bigint not null references app_user(id),
  app_role_id bigint not null references app_role(id),
  organisation_id bigint references organisation(id)
);
call sp_add_audit('app_user_role');
create unique index uq_app_user_role_scope on app_user_role (app_user_id, app_role_id, coalesce(organisation_id, 0)) where deleted_at is null;

create table credential (
  id bigint generated always as identity primary key,
  app_user_id bigint not null references app_user(id),
  password_hash varchar(255) not null,
  hash_algorithm varchar(30) not null default 'argon2id',
  must_change boolean not null default false,
  last_changed_at timestamptz not null default now(),
  constraint uq_credential_app_user_id unique (app_user_id)
);
call sp_add_audit('credential');

create table consent_record (
  id bigint generated always as identity primary key,
  app_user_id bigint not null references app_user(id),
  consent_type_id bigint not null references consent_type(id),
  is_granted boolean not null,
  policy_version varchar(20) not null,
  ip_address inet,
  recorded_at timestamptz not null default now()
);
call sp_add_audit('consent_record', false);
call sp_make_append_only('consent_record');
create index idx_consent_record_user_type on consent_record (app_user_id, consent_type_id, recorded_at desc);

create table licence (
  id bigint generated always as identity primary key,
  organisation_id bigint not null references organisation(id),
  licence_key varchar(64) not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  max_seats integer not null check (max_seats > 0),
  max_devices_per_seat integer not null default 3 check (max_devices_per_seat > 0),
  max_concurrent_sessions integer not null default 2 check (max_concurrent_sessions > 0),
  constraint uq_licence_licence_key unique (licence_key),
  constraint ck_licence_period check (ends_at > starts_at)
);
call sp_add_audit('licence');

create table seat (
  id bigint generated always as identity primary key,
  licence_id bigint not null references licence(id),
  app_user_id bigint not null references app_user(id),
  assigned_at timestamptz not null default now(),
  revoked_at timestamptz,
  constraint ck_seat_revoked check (revoked_at is null or revoked_at >= assigned_at)
);
call sp_add_audit('seat');
create unique index uq_seat_active on seat (licence_id, app_user_id) where revoked_at is null;
create index idx_seat_app_user_id on seat (app_user_id);

create function fn_check_seat_limit() returns trigger language plpgsql as $$
declare v_max integer; v_used integer;
begin
  if new.revoked_at is null then
    select max_seats into v_max from licence where id = new.licence_id for update;
    select count(*) into v_used from seat where licence_id = new.licence_id and revoked_at is null and id is distinct from new.id;
    if v_used >= v_max then
      raise exception 'seat limit % reached for licence %', v_max, new.licence_id using errcode = 'check_violation';
    end if;
  end if;
  return new;
end $$;
create trigger trg_seat_limit before insert or update on seat for each row execute function fn_check_seat_limit();

create table device (
  id bigint generated always as identity primary key,
  app_user_id bigint not null references app_user(id),
  device_type_id bigint not null references device_type(id),
  device_fingerprint varchar(128) not null,
  label varchar(200),
  registered_at timestamptz not null default now(),
  revoked_at timestamptz,
  constraint uq_device_user_fingerprint unique (app_user_id, device_fingerprint)
);
call sp_add_audit('device');

create table app_session (
  id bigint generated always as identity primary key,
  app_user_id bigint not null references app_user(id),
  device_id bigint references device(id),
  session_token_hash varchar(128) not null,
  ip_address inet,
  started_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  expires_at timestamptz not null,
  ended_at timestamptz,
  constraint uq_app_session_token_hash unique (session_token_hash),
  constraint ck_app_session_expiry check (expires_at > started_at)
);
call sp_add_audit('app_session');
create index idx_app_session_active on app_session (app_user_id) where ended_at is null;

create function fn_check_session_limit() returns trigger language plpgsql as $$
declare v_limit integer; v_active integer;
begin
  select min(l.max_concurrent_sessions) into v_limit
  from seat s join licence l on l.id = s.licence_id
  where s.app_user_id = new.app_user_id and s.revoked_at is null and now() between l.starts_at and l.ends_at;
  if v_limit is not null then
    select count(*) into v_active from app_session
    where app_user_id = new.app_user_id and ended_at is null and expires_at > now();
    if v_active >= v_limit then
      raise exception 'concurrent session limit % reached for user %', v_limit, new.app_user_id using errcode = 'check_violation';
    end if;
  end if;
  if new.device_id is not null and exists (select 1 from device where id = new.device_id and revoked_at is not null) then
    raise exception 'device % is revoked', new.device_id using errcode = 'check_violation';
  end if;
  return new;
end $$;
create trigger trg_app_session_limit before insert on app_session for each row execute function fn_check_session_limit();

create table login_history (
  id bigint generated always as identity primary key,
  app_user_id bigint references app_user(id),
  attempted_email varchar(320),
  is_success boolean not null,
  failure_reason varchar(100),
  device_id bigint references device(id),
  ip_address inet,
  occurred_at timestamptz not null default now()
);
call sp_add_audit('login_history', false);
call sp_make_append_only('login_history');
create index idx_login_history_user_time on login_history (app_user_id, occurred_at desc);

create table audit_log (
  id bigint generated always as identity primary key,
  actor_app_user_id bigint references app_user(id),
  action_code varchar(60) not null,
  entity_table varchar(63) not null,
  entity_id bigint,
  old_data jsonb,
  new_data jsonb,
  occurred_at timestamptz not null default now()
);
call sp_add_audit('audit_log', false);
call sp_make_append_only('audit_log');
create index idx_audit_log_entity on audit_log (entity_table, entity_id, occurred_at desc);

insert into app_role (code, name) values ('admin','Administrator'),('recruiter','Recruiter'),('candidate','Candidate'),('gig_worker','Gig worker'),('support','Support agent');
insert into permission (code, name) values ('profile.read','Read candidate profiles'),('profile.download','Download candidate profiles'),('job.write','Create and edit jobs'),('application.manage','Manage applications'),('billing.manage','Manage billing'),('user.manage','Manage users');
insert into role_permission (app_role_id, permission_id)
select r.id, p.id from app_role r join permission p on
  (r.code = 'admin') or
  (r.code = 'recruiter' and p.code in ('profile.read','profile.download','job.write','application.manage')) or
  (r.code = 'support' and p.code in ('profile.read'));
