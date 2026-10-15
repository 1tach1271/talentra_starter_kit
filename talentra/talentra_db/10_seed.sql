\if :{?n_orgs} \else \set n_orgs 200 \endif
\if :{?n_profiles} \else \set n_profiles 10000 \endif
\if :{?n_jobs} \else \set n_jobs 2000 \endif
\if :{?apps_per_job} \else \set apps_per_job 25 \endif
\if :{?n_notif} \else \set n_notif 50000 \endif

insert into country (iso2, iso3, name, phone_code, currency_id) values
  ('IN','IND','India','+91',(select id from currency where code='INR')),
  ('US','USA','United States','+1',(select id from currency where code='USD'));
insert into state (country_id, code, name)
select (select id from country where iso2 = s.c), s.code, s.name from (values
  ('IN','TN','Tamil Nadu'),('IN','KA','Karnataka'),('IN','MH','Maharashtra'),('IN','DL','Delhi'),('IN','TG','Telangana'),('IN','WB','West Bengal'),('US','CA','California'),('US','NY','New York')) s(c, code, name);
insert into city (state_id, name)
select (select st.id from state st where st.code = c.sc), c.name from (values
  ('TN','Chennai'),('TN','Coimbatore'),('KA','Bengaluru'),('KA','Mysuru'),('MH','Mumbai'),('MH','Pune'),('DL','New Delhi'),('TG','Hyderabad'),('WB','Kolkata'),('CA','San Francisco'),('NY','New York City'),('TN','Chengalpattu')) c(sc, name);
insert into skill (code, name)
select lower(replace(n, ' ', '_')), n from unnest(array['Java','Python','SQL','JavaScript','TypeScript','React','Node.js','Spring Boot','Docker','Kubernetes','AWS','Azure','Machine Learning','Deep Learning','Computer Vision','Data Analysis','Power BI','Tableau','Excel','Git','Linux','C++','Go','Rust','DevOps','Testing','Figma','Sales','Accounting','Communication']) n;
insert into qualification (code, name, level_rank) values ('school','School',1),('diploma','Diploma',2),('bachelors','Bachelors',3),('masters','Masters',4),('doctorate','Doctorate',5),('certificate','Certificate',2);
insert into industry (code, name) values ('it','Information Technology'),('fin','Finance'),('health','Healthcare'),('edu','Education'),('mfg','Manufacturing'),('retail','Retail'),('media','Media'),('logistics','Logistics');
insert into job_role (industry_id, code, name)
select (g % 8) + 1, 'role_' || g, r from (select row_number() over () g, r from unnest(array['Software Engineer','Data Scientist','Data Analyst','ML Engineer','DevOps Engineer','Product Manager','QA Engineer','Frontend Developer','Backend Developer','Business Analyst','Accountant','Sales Executive','HR Executive','Designer','Support Engineer','Operations Manager','Teacher','Nurse','Mechanical Engineer','Content Writer']) r) t;
insert into lookup_translation (entity_table, entity_id, language_id, translated_name)
select 'employment_type', e.id, l.id, t.txt from employment_type e
join (values ('full_time','hi','पूर्णकालिक'),('full_time','ta','முழு நேரம்'),('part_time','hi','अंशकालिक'),('part_time','ta','பகுதி நேரம்'),('contract','hi','अनुबंध'),('contract','ta','ஒப்பந்தம்')) t(code, lang, txt) on t.code = e.code
join language l on l.code = t.lang;

insert into organisation (name, country_id, industry_id, org_type_id, verification_status_id, legal_name)
select 'Organisation ' || g, 1, (g % 8) + 1, (g % 3) + 1, (g % 3) + 1, 'Organisation ' || g || ' Pvt Ltd' from generate_series(1, :n_orgs) g;

select coalesce(max(id), 0) as rec_base from app_user \gset
insert into app_user (email, display_name) select 'rec' || g || '@example.com', 'Recruiter ' || g from generate_series(1, :n_orgs) g order by g;
insert into recruiter (app_user_id, organisation_id, job_title) select :rec_base + g, g, 'Talent Acquisition' from generate_series(1, :n_orgs) g;
insert into app_user_role (app_user_id, app_role_id, organisation_id) select :rec_base + g, (select id from app_role where code = 'recruiter'), g from generate_series(1, :n_orgs) g;

select max(id) as cand_base from app_user \gset
insert into app_user (email, display_name) select 'cand' || g || '@example.com', 'Candidate ' || g from generate_series(1, :n_profiles) g order by g;

with names as (
  select array['Aarav','Priya','Kudrat','Ananya','Rohan','Meera','Vikram','Divya','Arjun','Sneha','आरव','प्रिया','ஆரவ்','பிரியா','Ahmed','Fatima','李伟','王芳','Maria','John'] f,
         array['Sharma','Iyer','Anand','Reddy','Nair','Singh','Patel','Khan','Das','Gupta','शर्मा','अय्यर','ஆனந்த்','நாயர்','陈','Garcia','Smith','Kumar','Rao','Mehta'] l)
insert into candidate_profile (app_user_id, full_name, headline, phone_e164, city_id, total_experience_months, contact_email, expected_salary, expected_salary_currency_id, is_open_to_work)
select :cand_base + g,
       n.f[(b % 20) + 1] || ' ' || n.l[((b / 20) % 20) + 1],
       (select name from job_role where id = (g % 20) + 1),
       '+91' || (9000000000 + b)::text,
       (b % 12) + 1, (b * 7) % 180, 'p' || g || '@example.com',
       400000 + (b * 37) % 2000000, 1, g % 7 <> 0
from (select g, case when g % 50 = 0 then g - 1 else g end b from generate_series(1, :n_profiles) g order by g) s, names n;

insert into candidate_skill (candidate_profile_id, skill_id, skill_proficiency_id, years_experience)
select g, ((g + (k - 1) * 10) % 30) + 1, ((g + k) % 4) + 1, ((g + k) % 10)::numeric from generate_series(1, :n_profiles) g, generate_series(1, 3) k;
insert into candidate_education (candidate_profile_id, qualification_id, institution, start_date, end_date)
select g, (g % 6) + 1, 'University ' || (g % 500), date '2015-07-01', date '2019-05-31' from generate_series(1, :n_profiles) g;
insert into candidate_experience (candidate_profile_id, job_role_id, employment_type_id, employer_name, job_title, start_date, is_current)
select g, (g % 20) + 1, (g % 5) + 1, 'Employer ' || (g % 800), 'Engineer', date '2020-01-01', true from generate_series(1, :n_profiles) g where g % 5 <> 0;
insert into resume_version (candidate_profile_id, version_no, file_reference, is_primary)
select g, 1, 'resumes/' || g || '.pdf', true from generate_series(1, :n_profiles) g;
insert into block_list (candidate_profile_id, organisation_id) select g, (g % :n_orgs) + 1 from generate_series(1, 20) g;

insert into job (organisation_id, job_role_id, employment_type_id, work_type_id, job_status_id, city_id, title, salary_min, salary_max, salary_currency_id, published_at, description, experience_min_years, experience_max_years, openings)
select (g % :n_orgs) + 1, (g % 20) + 1, (g % 5) + 1, (g % 3) + 1,
       case g % 10 when 8 then 1 when 9 then 4 else 2 end, (g % 12) + 1,
       r.name || ' #' || g, 300000 + (g * 13) % 1500000, 300000 + (g * 13) % 1500000 + (g * 7) % 500000, 1,
       now() - ((g % 90) || ' days')::interval, 'Seeded job description ' || g, (g % 5), (g % 5) + 3, (g % 4) + 1
from generate_series(1, :n_jobs) g join job_role r on r.id = (g % 20) + 1;
insert into job_skill (job_id, skill_id, is_mandatory) select g, ((g + (k - 1) * 7) % 30) + 1, k <= 2 from generate_series(1, :n_jobs) g, generate_series(1, 4) k;

alter table application disable trigger trg_application_history;
insert into application (job_id, candidate_profile_id, application_stage_id, applied_at)
select j, ((j * 37 + k * 104729) % :n_profiles) + 1,
       case when h < 40 then 1 when h < 60 then 2 when h < 72 then 3 when h < 80 then 4 when h < 84 then 5 else 6 end,
       now() - (((j * 13 + k * 29) % 90) || ' days')::interval - (((k * 7) % 24) || ' hours')::interval
from (select j, k, (j * 31 + k * 17) % 100 h from generate_series(1, :n_jobs) j, generate_series(0, :apps_per_job - 1) k) s;
insert into application_history (application_id, from_stage_id, to_stage_id, changed_at) select id, null, application_stage_id, applied_at from application;
alter table application enable trigger trg_application_history;

insert into plan (code, name, price, currency_id, billing_period_months, download_credits, max_seats) values
  ('basic','Basic',4999,1,12,100,2),('pro','Pro',14999,1,12,500,10),('enterprise','Enterprise',49999,1,12,2500,50);
insert into subscription (organisation_id, plan_id, subscription_status_id, period_start, period_end)
select g, (g % 3) + 1, 1, now() - interval '30 days', now() + interval '335 days' from generate_series(1, :n_orgs) g;
insert into payment_order (organisation_id, subscription_id, payment_status_id, amount, currency_id, gateway_reference, idempotency_key, paid_at)
select s.organisation_id, s.id, 2, p.price, 1, 'gw_' || s.id, 'seed-pay-' || s.id, now() - interval '30 days' from subscription s join plan p on p.id = s.plan_id;
insert into invoice (organisation_id, payment_order_id, invoice_status_id, invoice_number, subtotal, tax_amount, total_amount, currency_id)
select organisation_id, id, 2, 'INV-' || lpad(id::text, 8, '0'), amount, round(amount * 0.18, 2), amount + round(amount * 0.18, 2), 1 from payment_order;
insert into wallet (organisation_id) select g from generate_series(1, :n_orgs) g;
insert into wallet_ledger (wallet_id, ledger_entry_type_id, credits, payment_order_id, idempotency_key)
select w.id, 1, p.download_credits, po.id, 'seed-credit-' || po.id
from payment_order po join subscription s on s.id = po.subscription_id join plan p on p.id = s.plan_id join wallet w on w.organisation_id = po.organisation_id;

insert into notification (app_user_id, notification_channel_id, notification_status_id, event_code, created_at, sent_at)
select :cand_base + (g % :n_profiles) + 1, (g % 4) + 1, (g % 4) + 1, (array['job_match','application_update','profile_view','alert_digest'])[(g % 4) + 1],
       timestamptz '2026-07-01' + ((g * 7919) % (106 * 24 * 60)) * interval '1 minute', null
from generate_series(1, :n_notif) g;

insert into gig_worker_profile (app_user_id, headline, hourly_rate, rate_currency_id) select :cand_base + g, 'Gig worker ' || g, 300 + g * 10, 1 from generate_series(1, 5) g;
insert into gig_request (organisation_id, city_id, gig_status_id, title, starts_at, ends_at, pay_amount, pay_currency_id)
select (g % :n_orgs) + 1, (g % 12) + 1, 1, 'Event staff ' || g, now() + (g || ' days')::interval, now() + (g || ' days')::interval + interval '8 hours', 2000, 1 from generate_series(1, 20) g;
insert into faq (language_id, question, answer) select l.id, 'How do I reset my password?', 'Use the reset link on the login page.' from language l;
insert into community_post (app_user_id, title, body) select :cand_base + g, 'Interview tips ' || g, 'Seeded post' from generate_series(1, 20) g;

analyze;
call dw.sp_refresh_dw();
select 'candidate_profile' t, count(*) from candidate_profile union all select 'job', count(*) from job union all select 'application', count(*) from application
union all select 'notification', count(*) from notification union all select 'fact_application', count(*) from dw.fact_application;
