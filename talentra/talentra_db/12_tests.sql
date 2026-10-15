\set ON_ERROR_STOP off
begin;
create temp table test_result (name text, passed boolean, detail text);
grant all on test_result to public;

do $$ declare n bigint; begin
  begin update wallet_ledger set credits = 1 where id = (select min(id) from wallet_ledger);
    insert into test_result values ('ledger_update_blocked', false, 'update succeeded');
  exception when restrict_violation then insert into test_result values ('ledger_update_blocked', true, 'append-only'); end;
  begin insert into audit_log (action_code, entity_table) values ('test', 'test'); delete from audit_log; insert into test_result values ('audit_delete_blocked', false, 'delete succeeded');
  exception when restrict_violation then insert into test_result values ('audit_delete_blocked', true, 'append-only'); end;
  begin insert into wallet_ledger (wallet_id, ledger_entry_type_id, credits, idempotency_key) values (1, (select id from ledger_entry_type where code='download'), -100000, 'test-overdraw');
    insert into test_result values ('wallet_overdraw_blocked', false, 'overdraw accepted');
  exception when check_violation then insert into test_result values ('wallet_overdraw_blocked', true, 'check constraint'); end;
  begin insert into wallet_ledger (wallet_id, ledger_entry_type_id, credits, idempotency_key) values (1, (select id from ledger_entry_type where code='download'), 5, 'test-sign');
    insert into test_result values ('ledger_sign_checked', false, 'wrong sign accepted');
  exception when check_violation then insert into test_result values ('ledger_sign_checked', true, 'sign rule'); end;
  begin insert into gig_application (gig_request_id, gig_worker_profile_id, gig_application_status_id) values (1,1,2),(2,1,2);
    insert into gig_assignment (gig_application_id, gig_request_id, gig_worker_profile_id, work_window) select id, gig_request_id, 1, tstzrange(now() + interval '100 days', now() + interval '100 days 8 hours') from gig_application where gig_worker_profile_id = 1;
    insert into test_result values ('gig_overlap_blocked', false, 'overlap accepted');
  exception when exclusion_violation then insert into test_result values ('gig_overlap_blocked', true, 'exclusion constraint'); end;
  begin insert into licence (organisation_id, licence_key, starts_at, ends_at, max_seats, max_concurrent_sessions) values (1, 'test-lic', now() - interval '1 day', now() + interval '1 year', 1, 1);
    insert into seat (licence_id, app_user_id) select currval(pg_get_serial_sequence('licence','id')), id from app_user where id in (2,3) order by id;
    insert into test_result values ('seat_limit_enforced', false, 'second seat accepted');
  exception when check_violation then insert into test_result values ('seat_limit_enforced', true, 'seat trigger'); end;
end $$;

do $$ declare lic bigint; begin
  select id into lic from licence where licence_key = 'test-lic';
  if lic is null then
    insert into licence (organisation_id, licence_key, starts_at, ends_at, max_seats, max_concurrent_sessions) values (1, 'test-lic', now() - interval '1 day', now() + interval '1 year', 1, 1) returning id into lic;
    insert into seat (licence_id, app_user_id) values (lic, 2);
  end if;
  begin
    insert into app_session (app_user_id, session_token_hash, expires_at) values (2, 'h1', now() + interval '1 hour');
    insert into app_session (app_user_id, session_token_hash, expires_at) values (2, 'h2', now() + interval '1 hour');
    insert into test_result values ('session_limit_enforced', false, 'second session accepted');
  exception when check_violation then insert into test_result values ('session_limit_enforced', true, 'session trigger'); end;
end $$;

do $$ declare n integer; own bigint; uid bigint; oid_ bigint; other bigint; begin
  select app_user_id, id into uid, own from candidate_profile where deleted_at is null order by id offset 100 limit 1;
  execute 'set local role app_candidate';
  perform set_config('app.user_id', uid::text, true);
  select count(*) into n from candidate_profile;
  insert into test_result values ('candidate_sees_only_self', n = 1, n || ' rows visible');
  update candidate_profile set headline = 'hacked' where id <> own;
  get diagnostics n = row_count;
  insert into test_result values ('candidate_cannot_edit_others', n = 0, n || ' rows updated');
  select count(*) into n from application;
  insert into test_result values ('candidate_sees_only_own_applications', n = (select count(*) from application a join candidate_profile c on c.id = a.candidate_profile_id where c.app_user_id = uid) , n || ' applications visible');
  begin perform 1 from wallet_ledger; insert into test_result values ('candidate_no_wallet_access', false, 'select allowed');
  exception when insufficient_privilege then insert into test_result values ('candidate_no_wallet_access', true, 'denied'); end;
  reset role; perform set_config('app.user_id', '', true);
end $$;

do $$ declare n integer; rec_user bigint; org bigint; total_jobs integer; own_jobs integer; blocked integer; begin
  select app_user_id, organisation_id into rec_user, org from recruiter order by id offset 4 limit 1;
  execute 'set local role app_recruiter';
  perform set_config('app.user_id', rec_user::text, true);
  select count(*), count(*) filter (where organisation_id = org) into total_jobs, own_jobs from job;
  insert into test_result values ('recruiter_sees_only_own_org_jobs', total_jobs = own_jobs and own_jobs > 0, own_jobs || ' of ' || total_jobs);
  select count(*) into blocked from candidate_profile c where exists (select 1 from block_list b where b.candidate_profile_id = c.id and b.organisation_id = org);
  insert into test_result values ('recruiter_cannot_see_blocking_candidates', blocked = 0, blocked || ' blocked candidates visible');
  select count(*) into n from application a where not exists (select 1 from job j where j.id = a.job_id and j.organisation_id = org);
  insert into test_result values ('recruiter_sees_only_own_applications', n = 0, n || ' foreign applications');
  begin insert into wallet_ledger (wallet_id, ledger_entry_type_id, credits, idempotency_key) values (1, 1, 100, 'rec-direct'); insert into test_result values ('recruiter_cannot_write_ledger', false, 'insert allowed');
  exception when insufficient_privilege then insert into test_result values ('recruiter_cannot_write_ledger', true, 'denied'); end;
  reset role; perform set_config('app.user_id', '', true);
end $$;

do $$ declare d1 bigint; d2 bigint; b1 integer; b2 integer; begin
  select balance_credits into b1 from wallet where organisation_id = 1;
  d1 := sp_download_profile((select id from recruiter where organisation_id = 1), 123);
  d2 := sp_download_profile((select id from recruiter where organisation_id = 1), 123);
  select balance_credits into b2 from wallet where organisation_id = 1;
  insert into test_result values ('download_debits_once_idempotent', d1 = d2 and b1 - b2 = 1, 'balance ' || b1 || ' -> ' || b2);
end $$;

select name, case when passed then 'PASS' else 'FAIL' end result, detail from test_result order by name;
rollback;
