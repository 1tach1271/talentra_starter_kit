# Talentra database (PostgreSQL 16), working baseline

A complete, runnable baseline for the Talentra hackathon: 102 operational tables, a star schema (6 tables, 2 marts), 411 foreign keys, row-level security, seed data, 12 benchmark queries and a test suite. Structure and coverage were modelled on the module layout of https://github.com/DNVerma88/JOBPORTAL (auth, billing, portal, master data, RLS). No code was copied: that repo uses PascalCase, UUIDs and Postgres enums, which break the Talentra rules, so everything here follows the hackathon conventions instead.

## Run it

```
docker run -d --name talentra -e POSTGRES_PASSWORD=pw -p 5432:5432 -v "$PWD":/work postgres:16
docker exec talentra createdb -U postgres talentra
docker exec -w /work talentra env PGUSER=postgres ./run_all.sh talentra
```

Default seed: 200 organisations, 10,000 profiles, 2,000 jobs, 50,000 applications, 50,000 notifications.
Laptop-scale seed (1M profiles, 100K jobs, 5M applications):

```
SEED_ARGS="-v n_orgs=10000 -v n_profiles=1000000 -v n_jobs=100000 -v apps_per_job=50 -v n_notif=2000000" ./run_all.sh talentra
```

Raise `maintenance_work_mem` and `max_wal_size` first. Expect a long run.

## Files

| File | What it holds |
|---|---|
| `01_core.sql` | Master data, app_user, stub organisation / candidate_profile / job |
| `01b_helpers.sql` | `sp_add_audit`, `sp_create_lookup`, `sp_make_append_only`, `sp_index_fks` |
| `02_admin_licence.sql` | Roles, permissions, credentials, consent, licences, seats, devices, sessions, login history, audit log |
| `03_org_sourcing.sql` | Org hierarchy, identifiers, verification, recruiters, sourcing requests, outreach batches, shortlists |
| `04_candidate.sql` | Education, experience, skills, languages, resumes, projects, assessments, activity log, block list |
| `05_jobs_applications.sql` | Job skills, questions, positions, applications, answers, stage history trigger, saved jobs |
| `06_gig_finance.sql` | Gig marketplace (non-overlapping windows), plans, subscriptions, payments, invoices, refunds, wallet ledger, profile downloads |
| `07_notifications_community.sql` | Alert and privacy preferences, partitioned notification table, community, tickets, FAQ |
| `08_analytics.sql` | `dw` star schema: SCD2 dimensions, facts, materialised marts, `dw.sp_refresh_dw()` |
| `09_security_rls.sql` | DB roles and row-level security policies |
| `10_seed.sql` | Seed with duplicate profiles and Hindi / Tamil / Arabic / Chinese names |
| `11_compliance_checks.sql` | Rule checks, expect 0 rows |
| `12_tests.sql` | 16 constraint and RBAC tests, rolled back so it is rerunnable |
| `13_benchmark.sql`, `bench.py` | 12 queries, `python3 bench.py talentra 30` writes p50/p95/p99 and plans |
| `backup_restore_test.sh` | Dump, restore, row-count check, timings for the RTO table |
| `14_data_dictionary.sql`, `data_dictionary.csv` | Draft data dictionary with sensitivity class and protection |

## Rules enforced in the DDL

Every table has a bigint identity `id`, real FKs (all indexed), and audit columns; append-only tables (wallet ledger, audit log, login history, consent record, application history, activity log) block UPDATE, DELETE and TRUNCATE by trigger. Money is `numeric(14,2)` with a currency FK and a CHECK that an amount has a currency. Phones are E.164 with a CHECK. Timestamps are `timestamptz`. Status values are lookup tables, with `lookup_translation` for languages. Soft delete uses `deleted_at` with partial unique indexes. `11_compliance_checks.sql` verifies this and currently returns 0 rows.

## What the tests prove

Overdraft and wrong-sign wallet entries are rejected, the ledger cannot be edited, overlapping gig windows are rejected, seat and session limits are enforced, candidates see only their own profile and applications, recruiters see only their own organisation's jobs and applications and never a candidate who blocked them, and a profile download debits credits exactly once.

## What is still yours to do

1. **Engine decision note, ERD, coverage matrix vs Naukri / Monster / LinkedIn.** Not written. Generate the ERD with DBeaver or SchemaSpy.
2. **Integration boundary table.** The schema stores only references and statuses for payments, gig fulfilment and identity. The legacy-sync tables (sync state, conflict rule) are not modelled, and the brief mentions 8 boundaries; check it for the other three.
3. **Data dictionary review.** `data_dictionary.csv` is a name-based first pass. Check every sensitivity class and protection rule.
4. **Partitioning and indexing story.** Only `notification` is partitioned (monthly, PK `(id, created_at)` as Postgres requires). Partitioning `application` is left for you to try and measure before and after.
5. **Full-scale benchmark and extrapolation.** `bench.py` is ready. Run it at 1M scale, add before and after numbers, then model 10M.
6. **Security note.** Add a threat model and the PII masking rules. RLS covers candidate_profile, job, application and wallet_ledger only.
7. **Simplifications to know about:** wallet credits are a single balance per organisation, the warehouse refresh is a full reload, and `fn_ctx_user_id()` trusts the `app.user_id` setting, so the application layer must set it from the authenticated session.
