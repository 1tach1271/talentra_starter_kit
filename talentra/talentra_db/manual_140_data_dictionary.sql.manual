create or replace view v_data_dictionary as
select c.table_name, c.column_name, c.data_type, c.is_nullable,
  case
    when c.column_name in ('password_hash','identifier_token','session_token_hash','file_sha256') then 'Sensitive'
    when c.column_name in ('date_of_birth') then 'Sensitive'
    when c.column_name ~ '(email|phone|full_name|ip_address|display_name|expected_salary|salary_|hourly_rate|device_fingerprint|attempted_email|notice_period)' then 'Personal'
    when c.table_name in ('country','state','city','skill','qualification','industry','job_role','language','currency','employment_type','work_type','faq') then 'Public'
    else 'Internal' end as sensitivity,
  case
    when c.column_name in ('password_hash','session_token_hash') then 'hashed'
    when c.column_name = 'identifier_token' then 'tokenised'
    when c.column_name = 'date_of_birth' then 'encrypted at rest, masked in reports'
    when c.column_name ~ '(email|phone)' then 'masked unless consent and privacy setting allow'
    when c.column_name ~ '(full_name|ip_address|display_name|device_fingerprint)' then 'masked in analytics and logs'
    when c.column_name ~ '(expected_salary|salary_|hourly_rate)' then 'visible to recruiters only after application'
    else 'none' end as protection
from information_schema.columns c
join information_schema.tables t on t.table_schema = c.table_schema and t.table_name = c.table_name and t.table_type = 'BASE TABLE'
where c.table_schema = 'public' and c.table_name !~ '^notification_[0-9]|^notification_default$'
order by c.table_name, c.ordinal_position;
