do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'app_candidate') then create role app_candidate nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'app_recruiter') then create role app_recruiter nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'app_admin') then create role app_admin nologin; end if;
end $$;

create function fn_ctx_user_id() returns bigint language sql stable as $$
  select nullif(current_setting('app.user_id', true), '')::bigint $$;

create function fn_ctx_org_id() returns bigint language sql stable security definer set search_path = public as $$
  select r.organisation_id from recruiter r where r.app_user_id = fn_ctx_user_id() and r.deleted_at is null limit 1 $$;

grant usage on schema public to app_candidate, app_recruiter, app_admin;
grant select, insert, update on all tables in schema public to app_candidate, app_recruiter;
grant all on all tables in schema public to app_admin;
grant usage on all sequences in schema public to app_candidate, app_recruiter, app_admin;
grant execute on all functions in schema public to app_candidate, app_recruiter, app_admin;

alter table candidate_profile enable row level security;
create policy p_candidate_profile_self on candidate_profile for all to app_candidate
  using (app_user_id = fn_ctx_user_id()) with check (app_user_id = fn_ctx_user_id());
create policy p_candidate_profile_recruiter on candidate_profile for select to app_recruiter
  using (deleted_at is null
    and coalesce((select ps.is_searchable from privacy_setting ps where ps.app_user_id = candidate_profile.app_user_id and ps.deleted_at is null), true)
    and not exists (select 1 from block_list b where b.candidate_profile_id = candidate_profile.id and b.organisation_id = fn_ctx_org_id() and b.deleted_at is null));
create policy p_candidate_profile_admin on candidate_profile for all to app_admin using (true) with check (true);

alter table job enable row level security;
create policy p_job_candidate on job for select to app_candidate
  using (deleted_at is null and job_status_id = (select id from job_status where code = 'published'));
create policy p_job_recruiter on job for all to app_recruiter
  using (organisation_id = fn_ctx_org_id()) with check (organisation_id = fn_ctx_org_id());
create policy p_job_admin on job for all to app_admin using (true) with check (true);

alter table application enable row level security;
create policy p_application_candidate on application for all to app_candidate
  using (candidate_profile_id in (select id from candidate_profile where app_user_id = fn_ctx_user_id()))
  with check (candidate_profile_id in (select id from candidate_profile where app_user_id = fn_ctx_user_id()));
create policy p_application_recruiter on application for select to app_recruiter
  using (job_id in (select id from job where organisation_id = fn_ctx_org_id()));
create policy p_application_recruiter_update on application for update to app_recruiter
  using (job_id in (select id from job where organisation_id = fn_ctx_org_id()))
  with check (job_id in (select id from job where organisation_id = fn_ctx_org_id()));
create policy p_application_admin on application for all to app_admin using (true) with check (true);

alter table wallet_ledger enable row level security;
create policy p_wallet_ledger_recruiter on wallet_ledger for select to app_recruiter
  using (wallet_id in (select id from wallet where organisation_id = fn_ctx_org_id()));
create policy p_wallet_ledger_admin on wallet_ledger for all to app_admin using (true) with check (true);
revoke all on wallet_ledger, audit_log, login_history, consent_record from app_candidate;
revoke insert, update on wallet_ledger from app_recruiter;
