call sp_create_lookup('gig_status');
call sp_create_lookup('gig_application_status');
call sp_create_lookup('subscription_status');
call sp_create_lookup('payment_status');
call sp_create_lookup('invoice_status');
call sp_create_lookup('ledger_entry_type');
call sp_create_lookup('refund_status');
insert into gig_status (code, name) values ('open','Open'),('assigned','Assigned'),('completed','Completed'),('cancelled','Cancelled');
insert into gig_application_status (code, name) values ('applied','Applied'),('accepted','Accepted'),('declined','Declined'),('withdrawn','Withdrawn');
insert into subscription_status (code, name) values ('active','Active'),('expired','Expired'),('cancelled','Cancelled');
insert into payment_status (code, name) values ('created','Created'),('paid','Paid'),('failed','Failed'),('refunded','Refunded');
insert into invoice_status (code, name) values ('issued','Issued'),('paid','Paid'),('void','Void');
insert into ledger_entry_type (code, name) values ('purchase','Credit purchase'),('download','Profile download'),('refund','Refund'),('adjustment','Adjustment');
insert into refund_status (code, name) values ('requested','Requested'),('approved','Approved'),('processed','Processed'),('rejected','Rejected');

create table gig_request (
  id bigint generated always as identity primary key,
  organisation_id bigint not null references organisation(id),
  city_id bigint references city(id),
  gig_status_id bigint not null references gig_status(id),
  title varchar(300) not null,
  description text,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  pay_amount numeric(14,2) not null check (pay_amount >= 0),
  pay_currency_id bigint not null references currency(id),
  openings integer not null default 1 check (openings > 0),
  constraint ck_gig_request_window check (ends_at > starts_at)
);
call sp_add_audit('gig_request');

create table gig_worker_profile (
  id bigint generated always as identity primary key,
  app_user_id bigint not null references app_user(id),
  headline varchar(300),
  hourly_rate numeric(14,2) check (hourly_rate >= 0),
  rate_currency_id bigint references currency(id),
  rating_average numeric(3,2) check (rating_average between 1 and 5),
  is_available boolean not null default true,
  constraint ck_gig_worker_profile_rate_currency check (hourly_rate is null or rate_currency_id is not null)
);
call sp_add_audit('gig_worker_profile');
create unique index uq_gig_worker_profile_app_user_id on gig_worker_profile (app_user_id) where deleted_at is null;

create table gig_availability (
  id bigint generated always as identity primary key,
  gig_worker_profile_id bigint not null references gig_worker_profile(id),
  available_window tstzrange not null,
  constraint ck_gig_availability_not_empty check (not isempty(available_window)),
  constraint ex_gig_availability_no_overlap exclude using gist (gig_worker_profile_id with =, available_window with &&)
);
call sp_add_audit('gig_availability');

create table gig_application (
  id bigint generated always as identity primary key,
  gig_request_id bigint not null references gig_request(id),
  gig_worker_profile_id bigint not null references gig_worker_profile(id),
  gig_application_status_id bigint not null references gig_application_status(id),
  applied_at timestamptz not null default now(),
  constraint uq_gig_application_pair unique (gig_request_id, gig_worker_profile_id)
);
call sp_add_audit('gig_application');

create table gig_assignment (
  id bigint generated always as identity primary key,
  gig_application_id bigint not null references gig_application(id),
  gig_request_id bigint not null references gig_request(id),
  gig_worker_profile_id bigint not null references gig_worker_profile(id),
  work_window tstzrange not null,
  fulfilment_reference varchar(100),
  is_cancelled boolean not null default false,
  constraint uq_gig_assignment_application unique (gig_application_id),
  constraint ck_gig_assignment_not_empty check (not isempty(work_window)),
  constraint ex_gig_assignment_no_overlap exclude using gist (gig_worker_profile_id with =, work_window with &&) where (not is_cancelled)
);
call sp_add_audit('gig_assignment');

create table gig_rating (
  id bigint generated always as identity primary key,
  gig_assignment_id bigint not null references gig_assignment(id),
  rated_by_app_user_id bigint not null references app_user(id),
  rating smallint not null check (rating between 1 and 5),
  comment varchar(1000),
  constraint uq_gig_rating_assignment_rater unique (gig_assignment_id, rated_by_app_user_id)
);
call sp_add_audit('gig_rating');

create table gig_earning_reference (
  id bigint generated always as identity primary key,
  gig_assignment_id bigint not null references gig_assignment(id),
  external_reference varchar(100) not null,
  amount numeric(14,2) not null check (amount >= 0),
  currency_id bigint not null references currency(id),
  reconciled_at timestamptz,
  constraint uq_gig_earning_reference_external unique (external_reference)
);
call sp_add_audit('gig_earning_reference');

create table plan (
  id bigint generated always as identity primary key,
  code varchar(60) not null, name varchar(200) not null,
  price numeric(14,2) not null check (price >= 0),
  currency_id bigint not null references currency(id),
  billing_period_months smallint not null check (billing_period_months > 0),
  download_credits integer not null default 0 check (download_credits >= 0),
  max_seats integer not null default 1 check (max_seats > 0),
  constraint uq_plan_code unique (code)
);
call sp_add_audit('plan');

create table subscription (
  id bigint generated always as identity primary key,
  organisation_id bigint not null references organisation(id),
  plan_id bigint not null references plan(id),
  subscription_status_id bigint not null references subscription_status(id),
  period_start timestamptz not null,
  period_end timestamptz not null,
  constraint ck_subscription_period check (period_end > period_start)
);
call sp_add_audit('subscription');

create table payment_order (
  id bigint generated always as identity primary key,
  organisation_id bigint not null references organisation(id),
  subscription_id bigint references subscription(id),
  payment_status_id bigint not null references payment_status(id),
  amount numeric(14,2) not null check (amount > 0),
  currency_id bigint not null references currency(id),
  gateway_reference varchar(100),
  idempotency_key varchar(100) not null,
  paid_at timestamptz,
  constraint uq_payment_order_idempotency_key unique (idempotency_key)
);
call sp_add_audit('payment_order');

create table invoice (
  id bigint generated always as identity primary key,
  organisation_id bigint not null references organisation(id),
  payment_order_id bigint references payment_order(id),
  invoice_status_id bigint not null references invoice_status(id),
  invoice_number varchar(40) not null,
  subtotal numeric(14,2) not null check (subtotal >= 0),
  tax_amount numeric(14,2) not null default 0 check (tax_amount >= 0),
  total_amount numeric(14,2) not null,
  currency_id bigint not null references currency(id),
  issued_at timestamptz not null default now(),
  constraint uq_invoice_invoice_number unique (invoice_number),
  constraint ck_invoice_total check (total_amount = subtotal + tax_amount)
);
call sp_add_audit('invoice');

create table refund (
  id bigint generated always as identity primary key,
  payment_order_id bigint not null references payment_order(id),
  refund_status_id bigint not null references refund_status(id),
  amount numeric(14,2) not null check (amount > 0),
  currency_id bigint not null references currency(id),
  reason varchar(300),
  gateway_reference varchar(100),
  refunded_at timestamptz
);
call sp_add_audit('refund');

create table wallet (
  id bigint generated always as identity primary key,
  organisation_id bigint not null references organisation(id),
  balance_credits integer not null default 0,
  constraint ck_wallet_balance check (balance_credits >= 0),
  constraint uq_wallet_organisation_id unique (organisation_id)
);
call sp_add_audit('wallet');

create table wallet_ledger (
  id bigint generated always as identity primary key,
  wallet_id bigint not null references wallet(id),
  ledger_entry_type_id bigint not null references ledger_entry_type(id),
  credits integer not null check (credits <> 0),
  balance_after integer not null default 0,
  payment_order_id bigint references payment_order(id),
  reference_table varchar(63),
  reference_id bigint,
  idempotency_key varchar(100) not null,
  occurred_at timestamptz not null default now(),
  constraint uq_wallet_ledger_idempotency_key unique (idempotency_key)
);
call sp_add_audit('wallet_ledger', false);
create index idx_wallet_ledger_wallet_time on wallet_ledger (wallet_id, occurred_at desc);

create function fn_wallet_ledger_apply() returns trigger language plpgsql as $$
declare v_code text;
begin
  select code into v_code from ledger_entry_type where id = new.ledger_entry_type_id;
  if (v_code = 'download' and new.credits > 0) or (v_code in ('purchase','refund') and new.credits < 0) then
    raise exception 'credit sign does not match entry type %', v_code using errcode = 'check_violation';
  end if;
  update wallet set balance_credits = balance_credits + new.credits where id = new.wallet_id
  returning balance_credits into new.balance_after;
  return new;
end $$;
create trigger trg_wallet_ledger_apply before insert on wallet_ledger for each row execute function fn_wallet_ledger_apply();
call sp_make_append_only('wallet_ledger');

create table profile_download (
  id bigint generated always as identity primary key,
  organisation_id bigint not null references organisation(id),
  recruiter_id bigint not null references recruiter(id),
  candidate_profile_id bigint not null references candidate_profile(id),
  wallet_ledger_id bigint not null references wallet_ledger(id),
  downloaded_at timestamptz not null default now(),
  constraint uq_profile_download_ledger unique (wallet_ledger_id)
);
call sp_add_audit('profile_download');
create index idx_profile_download_org_time on profile_download (organisation_id, downloaded_at desc);

create function sp_download_profile(p_recruiter_id bigint, p_candidate_profile_id bigint, p_cost integer default 1) returns bigint language plpgsql security definer set search_path = public as $$
declare v_org bigint; v_wallet bigint; v_ledger bigint; v_type bigint; v_key text; v_id bigint;
begin
  select organisation_id into v_org from recruiter where id = p_recruiter_id and deleted_at is null;
  if v_org is null then raise exception 'unknown recruiter %', p_recruiter_id; end if;
  if fn_ctx_user_id() is not null and not exists (select 1 from recruiter where id = p_recruiter_id and app_user_id = fn_ctx_user_id()) then
    raise exception 'recruiter % does not belong to the current user', p_recruiter_id using errcode = 'insufficient_privilege';
  end if;
  select id into v_wallet from wallet where organisation_id = v_org;
  select id into v_type from ledger_entry_type where code = 'download';
  v_key := 'dl:' || v_org || ':' || p_candidate_profile_id;
  select id into v_ledger from wallet_ledger where idempotency_key = v_key;
  if v_ledger is null then
    insert into wallet_ledger (wallet_id, ledger_entry_type_id, credits, reference_table, reference_id, idempotency_key)
    values (v_wallet, v_type, -p_cost, 'candidate_profile', p_candidate_profile_id, v_key) returning id into v_ledger;
    insert into profile_download (organisation_id, recruiter_id, candidate_profile_id, wallet_ledger_id)
    values (v_org, p_recruiter_id, p_candidate_profile_id, v_ledger) returning id into v_id;
  else
    select id into v_id from profile_download where wallet_ledger_id = v_ledger;
  end if;
  return v_id;
end $$;
