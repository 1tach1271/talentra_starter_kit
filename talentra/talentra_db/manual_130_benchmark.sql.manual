-- Q01 candidates by skill and city
select cp.id, cp.full_name from candidate_profile cp join candidate_skill s on s.candidate_profile_id = cp.id where s.skill_id = 3 and cp.city_id = 1 and cp.deleted_at is null order by cp.id limit 50;
-- Q02 fuzzy name search (multilingual)
select id, full_name, similarity(full_name, 'Aarav Sharma') sim from candidate_profile where full_name % 'Aarav Sharma' order by sim desc limit 20;
-- Q03 duplicate lookup by phone
select id, full_name, phone_e164 from candidate_profile where phone_e164 = '+919000000150' and deleted_at is null;
-- Q04 job search by role, city, salary
select id, title, salary_min, published_at from job where job_status_id = 2 and job_role_id = 4 and city_id = 5 and salary_min >= 500000 and deleted_at is null order by published_at desc limit 20;
-- Q05 job search by title text
select id, title from job where title ilike '%data scientist%' and job_status_id = 2 order by published_at desc limit 20;
-- Q06 pipeline counts for one job
select s.code, count(*) from application a join application_stage s on s.id = a.application_stage_id where a.job_id = 17 and a.deleted_at is null group by s.code order by s.code;
-- Q07 my applications with job titles
select a.id, j.title, s.code, a.applied_at from application a join job j on j.id = a.job_id join application_stage s on s.id = a.application_stage_id where a.candidate_profile_id = 100 order by a.applied_at desc limit 50;
-- Q08 recruiter inbox, latest applications for an organisation
select a.id, a.applied_at, j.title, cp.full_name from application a join job j on j.id = a.job_id join candidate_profile cp on cp.id = a.candidate_profile_id where j.organisation_id = 5 order by a.applied_at desc limit 50;
-- Q09 apply transaction (rolled back)
@tx insert into application (job_id, candidate_profile_id, application_stage_id) values (1, 9999, 1) on conflict do nothing;
-- Q10 stage move transaction (rolled back)
@tx update application set application_stage_id = 2, updated_at = now() where id = 500;
-- Q11 reporting: applications per organisation and stage, last 30 days
select j.organisation_id, s.code, count(*) from application a join job j on j.id = a.job_id join application_stage s on s.id = a.application_stage_id where a.applied_at > now() - interval '30 days' group by j.organisation_id, s.code order by 1, 2 limit 200;
-- Q12 reporting: skill demand vs supply
select sk.name, d.demand, sp.supply from skill sk left join (select skill_id, count(*) demand from job_skill group by skill_id) d on d.skill_id = sk.id left join (select skill_id, count(*) supply from candidate_skill group by skill_id) sp on sp.skill_id = sk.id order by d.demand desc nulls last limit 15;
