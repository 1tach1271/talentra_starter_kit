call sp_create_lookup('notification_channel');
call sp_create_lookup('notification_status');
call sp_create_lookup('ticket_status');
call sp_create_lookup('ticket_priority');
call sp_create_lookup('alert_frequency');
insert into notification_channel (code, name) values ('email','Email'),('sms','SMS'),('push','Push'),('in_app','In-app');
insert into notification_status (code, name) values ('queued','Queued'),('sent','Sent'),('delivered','Delivered'),('failed','Failed');
insert into ticket_status (code, name) values ('open','Open'),('pending','Pending'),('resolved','Resolved'),('closed','Closed');
insert into ticket_priority (code, name) values ('low','Low'),('normal','Normal'),('high','High'),('urgent','Urgent');
insert into alert_frequency (code, name) values ('instant','Instant'),('daily','Daily'),('weekly','Weekly');

create table job_alert_preference (
  id bigint generated always as identity primary key,
  candidate_profile_id bigint not null references candidate_profile(id),
  job_role_id bigint references job_role(id),
  city_id bigint references city(id),
  work_type_id bigint references work_type(id),
  min_salary numeric(14,2) check (min_salary >= 0),
  salary_currency_id bigint references currency(id),
  alert_frequency_id bigint not null references alert_frequency(id),
  is_active boolean not null default true,
  constraint ck_job_alert_preference_salary_currency check (min_salary is null or salary_currency_id is not null)
);
call sp_add_audit('job_alert_preference');

create table privacy_setting (
  id bigint generated always as identity primary key,
  app_user_id bigint not null references app_user(id),
  is_searchable boolean not null default true,
  show_phone boolean not null default false,
  show_email boolean not null default false,
  constraint uq_privacy_setting_app_user_id unique (app_user_id)
);
call sp_add_audit('privacy_setting');

create table notification_preference (
  id bigint generated always as identity primary key,
  app_user_id bigint not null references app_user(id),
  notification_channel_id bigint not null references notification_channel(id),
  event_code varchar(60) not null,
  is_enabled boolean not null default true,
  constraint uq_notification_preference_triple unique (app_user_id, notification_channel_id, event_code)
);
call sp_add_audit('notification_preference');

create table notification (
  id bigint generated always as identity,
  app_user_id bigint not null references app_user(id),
  notification_channel_id bigint not null references notification_channel(id),
  notification_status_id bigint not null references notification_status(id),
  event_code varchar(60) not null,
  provider_message_reference varchar(100),
  payload jsonb,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  created_by bigint not null default 1 references app_user(id),
  primary key (id, created_at)
) partition by range (created_at);
create table notification_default partition of notification default;
do $$
declare m date := date '2026-07-01';
begin
  while m < date '2027-07-01' loop
    execute format('create table notification_%s partition of notification for values from (%L) to (%L)', to_char(m, 'YYYY_MM'), m, m + interval '1 month');
    m := (m + interval '1 month')::date;
  end loop;
end $$;
create index idx_notification_user_time on notification (app_user_id, created_at desc);

create table community_post (
  id bigint generated always as identity primary key,
  app_user_id bigint not null references app_user(id),
  title varchar(300) not null,
  body text not null,
  is_published boolean not null default true
);
call sp_add_audit('community_post');

create table community_comment (
  id bigint generated always as identity primary key,
  community_post_id bigint not null references community_post(id),
  app_user_id bigint not null references app_user(id),
  body varchar(2000) not null
);
call sp_add_audit('community_comment');

create table support_ticket (
  id bigint generated always as identity primary key,
  app_user_id bigint not null references app_user(id),
  ticket_status_id bigint not null references ticket_status(id),
  ticket_priority_id bigint not null references ticket_priority(id),
  assigned_app_user_id bigint references app_user(id),
  subject varchar(300) not null
);
call sp_add_audit('support_ticket');

create table support_ticket_message (
  id bigint generated always as identity primary key,
  support_ticket_id bigint not null references support_ticket(id),
  author_app_user_id bigint not null references app_user(id),
  body text not null
);
call sp_add_audit('support_ticket_message');

create table faq (
  id bigint generated always as identity primary key,
  language_id bigint not null references language(id),
  question varchar(500) not null,
  answer text not null,
  display_order smallint not null default 0,
  is_published boolean not null default true
);
call sp_add_audit('faq');
