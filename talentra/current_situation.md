# Talentra — Current Situation Report
> Written: 19 October 2026 | Author: Kiro (analysis of all context docs + codebase)
> Purpose: Your single-source-of-truth before the next work session.

---

## Table of Contents
1. [What the Judges Are Expecting — Framework Explained](#1-what-the-judges-are-expecting--framework-explained)
2. [The Hackathon Docket — What Northbridge Wants](#2-the-hackathon-docket--what-northbridge-wants)
3. [What We Have Built So Far](#3-what-we-have-built-so-far)
4. [Where We Stand Against the Docket Milestones](#4-where-we-stand-against-the-docket-milestones)
5. [The Scorecard — What It Is and How to Satisfy It](#5-the-scorecard--what-it-is-and-how-to-satisfy-it)
6. [What Is Pending — Brutally Honest Gap List](#6-what-is-pending--brutally-honest-gap-list)
7. [The UI / API Layer — What We Need to Leave for Your Friend](#7-the-ui--api-layer--what-we-need-to-leave-for-your-friend)
8. [Our Plan — How We Will Finish](#8-our-plan--how-we-will-finish)

---

## 1. What the Judges Are Expecting — Framework Explained

There are **two documents** in `my-context/` that define the philosophy the judges come from:

- `DATA-DRIVEN-DEVELOPMENT-FRAMEWORK.pdf` — the high-level philosophy
- `Talencia Global - Data-Driven Development Lifecycle - Detailed Playbook.pdf` — the 46-step, 8-gate lifecycle

### What they are preaching

The core idea is a complete reversal of how most people build software:

```
Traditional order:  Requirements → Design UI → Write Code → Test → Release
Their order:        Data → Prove → Insight → Specify → Design → Code → Release
```

They call it **Data-Driven Development (DDD)**. The working thesis is:

> "Build the app is the easy part now. AI coding agents can generate an application in hours.
> What still decides success is the data, the requirements, the features and the proof."

In plain English: they don't care about the app. They care about whether you **understand your data deeply**, can **prove your model works with realistic data**, and can **measure outcomes with KPIs** — all **before** a single line of application code is written.

### The 8 phases they expect

| Phase | Name | What you do |
|---|---|---|
| 1 | Discover | Understand the problem, map actors, list NFRs, draw workflows |
| 2 | Model | Design entities, attributes, state machines, ER model, data dictionary |
| 3 | Prove | Generate realistic data, run tests against it, prove it covers all workflows |
| 4 | Platform | Load full volume (1M rows), automate all tests, prove performance |
| 5 | Insight | Build KPIs and analytics — prove the data can answer leadership questions |
| 6 | Specify | Write a PRD (after learning from data, not before), traceability matrix |
| 7 | Design | Prototype, architecture, HLD, LLD, write all tests BEFORE code |
| 8 | Release | Generate code, review AI output, run all suites, ship |

### The 4 core principles they test against

1. **Data first** — the data model and its rules are built and proven before any application is designed
2. **Tests before code** — every rule has a test written before any code that implements it
3. **Insight before specification** — KPIs and analytics are defined before the PRD is written
4. **Everything traceable** — every requirement links to an entity, a rule, a test, and a KPI (using ID prefixes: REQ-, ENT-, BR-, TC-, KPI-)

### What they hate (Anti-patterns that fail the panel)

| What NOT to do | Why it fails |
|---|---|
| Jump straight to code with an AI agent | Code is built on guesses |
| Use uniform random test data | Hides real edge cases |
| Only test the happy path | Cancel, retry, and failure paths break the system |
| Freeze the ER model too early | Can't absorb gaps found later |
| Define KPIs after launch | Schema can't compute them |
| Trust AI-generated code unreviewed | Invented fields and insecure code |

### The 9 Quality Gates

Each phase ends with a gate. A gate is checked by someone who did NOT write the work. If it fails, you go back — you don't move forward with a gap attached. The gates that matter most for us:

- **G2 (Model defined):** Data dictionary v1 complete. Every rule states where it is enforced. Every personal-data column classified with a retention period.
- **G3 (Model proven):** 100% workflow coverage. Test suite v2 passes on sample data. DDL runs clean.
- **G4 (Data platform ready):** Full-volume data loaded and reconciled. All automated test suites pass. NFR targets met.
- **G5 (Insight validated):** Every KPI is computable from the schema, and every dashboard number reconciles with its source.

---

## 2. The Hackathon Docket — What Northbridge Wants

The docket is from `Talentra-Database-Design-Hackathon-Docket.pdf`.

### The problem we are solving

Northbridge Workforce Systems has legacy systems with inconsistent data. No single view of the hiring pipeline. Low candidate retention. They want a **production-grade PostgreSQL database** for "LinkedIn + Naukri + Uber for short-term work" — serving candidates, employers, recruiters, consultants, TPOs, and admins.

### Scope in / out (critical)

**In scope (we own this):**
- Logical and physical data model
- Seed data generation
- Performance validation
- Security design
- Analytics layer
- Licence and device management
- Payments and subscriptions
- Multilingual UI data support
- Panel defence

**Explicitly out of scope:**
- Building the user interface (that's your friend's job)
- Integrating with live external services
- Loading the full 10M profiles on a laptop (extrapolation is sufficient)
- ETL and data migration

### The 10 Rule Groups (mandatory compliance)

Every single submitted design is checked against these. An undocumented deviation is scored as a defect.

| Rule Group | What it covers | Key things we must prove |
|---|---|---|
| 1 | Naming conventions | snake_case, singular tables, PK named `id`, FK named `<table>_id` |
| 2 | Keys and constraints | Surrogate PKs, natural keys as UNIQUE, every FK with ON DELETE stated, concurrency enforced in DB |
| 3 | Standard domains | Money = numeric(14,2), timestamps = timestamptz UTC, enums = lookup tables (NOT postgres ENUM), booleans NOT NULL with DEFAULT |
| 4 | Audit and lifecycle | Every business table has created_at / created_by / updated_at / updated_by, soft delete with deleted_at, audit tables append-only |
| 5 | Nullability | Every nullable column has a written justification |
| 6 | Sensitive data classification | Every column tagged Public / Internal / Personal / Sensitive in the data dictionary |
| 7 | Multilingual data | UTF-8 end to end, UI strings stored by key with translation table |
| 8 | Physical object naming | Views = v_, materialized views = mv_, partitions = _p<yyyymm>, analytics = dw_ prefix |
| 9 | Licences, devices, sessions | Licence has max_seats and max_devices columns, concurrent session limit enforced IN THE DATABASE, revocation is auditable |
| 10 | Money, subscriptions, history | Ledgers append-only, subscription periods EXCLUDE overlaps, download history append-only |

### Scale targets (what the judges will ask about)

| | Laptop scale (what we demo) | Full scale (what we extrapolate) |
|---|---|---|
| Candidate profiles | 1,000,000 | 10,000,000 |
| Job requirements | 100,000 | 1,000,000 |
| Applications | 5,000,000 | 100,000,000 |

The **extrapolation is mandatory**. We must measure at laptop scale, then project to full scale using a stated method (index size growth, buffer cache hit ratio change, query plan changes). Projections without measured basis are rejected.

### The Integration Boundaries Table (reviewed at the panel)

Section 6 of the docket is a table with 9 external systems. For each one, the judges will ask:
- What does the DB store vs. just reference?
- What happens when that system is down?
- How do we prevent duplicate events (idempotency)?
- How is the exchange audited?

We need a filled-in version of this table. Currently it is blank.

---

## 3. What We Have Built So Far

### Schema — what exists

All 11 modules have SQL files in `talentra_db/`. Here is the honest state:

| File | Module | Status |
|---|---|---|
| `01_core.sql` | Master data + core stubs | ✅ Done |
| `01b_helpers.sql` | Helper procedures (sp_add_audit, sp_make_append_only, sp_index_fks) | ✅ Done |
| `02_admin_licence.sql` | Administration, licences, sessions, devices | ✅ Done |
| `03_org_sourcing.sql` | Organisation, recruiter mapping, sourcing, outreach | ✅ Done |
| `04_candidate.sql` | Candidate profile, education, experience, skills, resume | ✅ Done |
| `04b_candidate_missing.sql` | Course enrolments, profile view history, referral tracking, resume template, shortlist bookmark history | ✅ Done |
| `05_jobs_applications.sql` | Jobs, applications (with history trigger), saved_job | ✅ Done |
| `05b_jobs_applications_missing.sql` | Job categories, job search history, extended block_list | ✅ Done |
| `06_gig_finance.sql` | Gig marketplace + subscriptions + payments + wallet | ✅ Done |
| `07_notifications_community.sql` | Notifications (partitioned by month), community posts, support tickets, FAQs | ✅ Done |
| `08_analytics.sql` | dw schema, SCD2 dimensions, fact tables, materialised views | ✅ Done |
| `09_security_rls.sql` | DB roles (app_candidate, app_recruiter, app_admin), RLS policies | ✅ Done |
| `10_seed.sql` | psql-based bulk seed (200 orgs, 10K profiles, 2K jobs, 50K applications) | ✅ Done |
| `11_compliance_checks.sql` | 14 automated rule-violation checks | ✅ Done |
| `12_tests.sql` | Constraint and RLS tests (manual) | ✅ Done |
| `13_benchmark.sql` | 12 benchmark queries | ✅ Done |
| `14_data_dictionary.sql` | Data dictionary view | ✅ Stub exists |

**Total: ~128 tables, 0 rule violations per compliance_checks.sql**

### Key rules enforced at the database level

| Business rule | Mechanism |
|---|---|
| Wallet can't go negative | CHECK constraint on `wallet.balance_credits >= 0` |
| Wallet ledger is immutable | BEFORE UPDATE/DELETE trigger raises exception |
| Seat limit enforced | BEFORE INSERT trigger on `seat` checks count against licence |
| Session limit enforced at login | BEFORE INSERT trigger on `app_session` |
| Gig windows can't overlap for same worker | EXCLUDE USING GIST constraint |
| Recruiter only sees their company's jobs | Row-Level Security policy |
| Blocked candidate not visible to blocker | RLS policy checks `block_list` |
| Append-only tables (audit, ledger, history) | Trigger blocks UPDATE, DELETE, TRUNCATE |
| Profile download deducts exactly 1 credit | `sp_download_profile()` with idempotency key |

### Seed data — current state (DEV scale, NOT demo scale)

| Table | Current rows | Required for demo |
|---|---|---|
| candidate_profile | ~10,500 | **1,000,000** |
| job | ~2,100 | **100,000** |
| application | ~51,000 | **5,000,000** |
| notification | ~50,200 | varies |
| organisation | ~220 | 10,000 |
| app_user | ~10,722 | matches candidates |

The scale constants in `seed/config.py` are currently at dev mode (N_CANDIDATES = 500, N_ORGS = 20, N_JOBS = 100). They need to be scaled up significantly.

### Tests and benchmarks

- `12_tests.sql` — 10 tests covering: ledger append-only, audit append-only, wallet overdraw, gig overlap, seat limit, session limit, RLS for candidate, RLS for recruiter, and download idempotency. These are **manual** (prefix `.manual` — not auto-run).
- `13_benchmark.sql` — 12 benchmark queries (Q01–Q12) covering skill+city search, fuzzy name search, job search, pipeline counts, recruiter inbox, reporting. They exist but **haven't been run at scale yet**.
- `bench.py` — Python script to run all 12 queries and record p50/p95/p99. **Never been executed**.

---

## 4. Where We Stand Against the Docket Milestones

The docket has 5 phases, 23 milestones, and 82 backlogs (B1–B82).

### Phase 1 — Foundation (B1–B23) ✅ COMPLETE

All common modules (Master Data, Profile, Jobs & Applications) have tables, columns, keys, and constraints. The team signed off on PostgreSQL (B1), agreed module list (B2–B3), and worked through entities → relationships → columns → keys for both Profile and Jobs/Applications (B4–B23).

**Evidence:** All SQL files exist and run. Compliance checks return 0 violations.

### Phase 2 — Individual Modules (B24–B35) ✅ COMPLETE

Administration (Shashi), Organisation (Kudrat), and Gig Marketplace (Kshitij) are all built, including keys and constraints.

**Evidence:** SQL files 02, 03, 06 cover these modules.

### Phase 3 — Licences, Sourcing, Subscriptions (B36–B47) ✅ COMPLETE

Licences/sessions (Shashi), Sourcing/consultant requests (Kudrat), Subscriptions/wallet/payments (Kshitij) are all built.

**One gap:** Subscription non-overlap EXCLUDE constraint is flagged as missing in the project explainer. Need to verify.

**Evidence:** SQL files 02 (licences), 03 (sourcing), 06 (subscriptions, wallet) cover these.

### Phase 4 — Notifications, Analytics, Shared Items (B48–B59) ✅ COMPLETE

Notifications (partitioned), analytics star schema (dw.*), credentials, consent, audit, blocking all built.

**Evidence:** SQL files 07 (notifications), 08 (analytics), 02 (admin/shared).

### Phase 5 — Seeding, Performance and Security (B60–B82) 🔴 MOSTLY PENDING

This is the biggest gap. Almost nothing in Phase 5 is done to the required level.

| Backlog | What it needs | Current state |
|---|---|---|
| B60 — Seed Master data + Profile at 1M scale | 1,000,000 candidate profiles | ~10,500 rows (dev mode) |
| B61 — Seed Jobs + Applications at scale | 100K jobs, 5M applications | ~2,100 jobs, ~51K applications |
| B62 — Seed Admin, Org, Gig at scale | Overlap attempts in seed data | Dev scale only |
| B63 — Seed Licences, Sourcing, Subscriptions | Full licence/session/payment data | Dev scale only |
| B64 — Seed Notifications, Analytics, Shared | Full notifications + analytics DW populated | Dev scale only |
| B65 — Run query set with execution plans | 12 queries + EXPLAIN ANALYZE output | Queries written, never run at scale |
| B66 — Seed validation report | Validate against 10 data standards rules | Not done |
| B67–B69 — Module-specific query results | Per-module validation | Not done |
| B70 — Performance baseline report | p50/p95/p99 for all 12 queries | Not done |
| B71–B73 — Index justification per module | Before/after measurement | Not done |
| B74 — Full-scale extrapolation | Project to 10M profiles, identify first-to-degrade query | Not done |
| B75–B77 — PII handling notes per module | Encryption/tokenisation/masking stated for each | Not done |
| B78 — Threat model | Access control, audit, password hashing, session controls | Not done |
| B79 — Access and audit test results | Prove no role can read outside its boundary | Tests exist, not run/documented |
| B80 — Backup and restore log | pg_dump → pg_restore with timing vs RTO | Not done |
| B81 — Security design note | Combined security document | Not done |
| B82 — Gate 2 sign-off | Final confirmation of all Phase 5 deliverables | Not done |

---

## 5. The Scorecard — What It Is and How to Satisfy It

You mentioned you didn't understand the "scorecard" they mentioned. Here is the full picture.

### The Rule Compliance Table (Section 5 of the docket)

This is the main "scorecard." It is a simple grid:

| Rule group | Complies? | Deviation with reason |
|---|---|---|
| 1: Naming conventions | ✅ / ❌ | if ❌, write why |
| 2: Keys and constraints | | |
| 3: Standard domains | | |
| 4: Audit and lifecycle | | |
| 5: Nullability | | |
| 6: Sensitive data classification | | |
| 7: Multilingual data | | |
| 8: Naming of physical objects | | |
| Reserved keyword check | | |
| 9: Licensing, devices, sessions | | |
| 10: Money, subscriptions, history | | |

**We need to fill this in and submit it.** The `11_compliance_checks.sql` file automates some of the checks (naming, float columns, missing audit columns, etc.) but that's only structural. The compliance table also requires *stated justifications* — written in a document.

### The Competitive Coverage Matrix (Section 4 of the docket)

A second "scorecard" — a table comparing our design against Naukri, Monster, and LinkedIn:

| Feature / Data Element | Naukri | Monster | LinkedIn | Talentra (us) |
|---|---|---|---|---|
| Candidate skills | ✅ | ✅ | ✅ | ✅ |
| Video resume | ✅ | ❌ | ✅ | ? |
| Gig marketplace | ❌ | ❌ | ❌ | ✅ (differentiator) |
| ... | | | | |

The aim is to **exceed** all three in the domains that matter. This document does not exist yet.

### The DDD Framework Scorecard (what the judges bring to the panel)

From the playbook, the judges will informally score against their DDD lifecycle:
- Do you have IDs on requirements (REQ-), entities (ENT-), business rules (BR-), test cases (TC-)?
- Do you have a traceability thread — can you show how REQ-07 → ENT-12 → BR-05 → TC-23?
- Do you have a data dictionary with every column classified?
- Did you generate scenario-based datasets (not just uniform random data)?
- Can you compute every KPI from the schema?

### The Integration Boundary Table (Section 6 of the docket)

The third "scorecard." Nine external systems, five columns each. **Reviewed at the panel.** Currently empty.

---

## 6. What Is Pending — Brutally Honest Gap List

### Critical (blocks the panel defence)

1. **Scale the seed data to 1M profiles** — everything else (performance, queries, extrapolation) depends on having real volume. `seed/config.py` just needs its constants updated, then the containers re-run.

2. **Run bench.py and capture output** — the 12 benchmark queries need to run at 1M-profile scale with `EXPLAIN (ANALYZE, BUFFERS)` output captured. This is the evidence for p50/p95/p99.

3. **Write the performance baseline report** — hardware spec + dataset size + query text + p50/p95/p99 for all 12 queries. One markdown file.

4. **Write the full-scale extrapolation** — from 1M to 10M profiles. Which query degrades first and why? Must be based on measured data, not guesses.

5. **Fill in the Integration Boundary Table** — 9 rows, 5 columns. This is reviewed at the panel.

6. **Fill in the Rule Compliance Table** — 11 rule groups, complies/deviations. Submit this.

### High priority (likely asked at the panel)

7. **Write the Competitive Coverage Matrix** — compare against Naukri, Monster, LinkedIn for all Tier 1 and Tier 2 data elements.

8. **Write per-module PII handling notes** — what is encrypted, tokenised, or masked? In which table? This is B75–B77.

9. **Write the threat model** — access control by role, audit trail coverage, password hashing approach, session controls. This is B78.

10. **Write the security design note** — combines B75–B78 into one document. B81.

11. **Write Gig model decision (D4)** — decision log says "TBD." The docket explicitly requires a written justification for whether gig sits in a separate subsystem or shares the core job/application model. Kshitij owns this.

12. **Document index justifications per module** — at least one index per module with before/after query time. B71–B73.

### Medium priority (clean up, documentation)

13. **Validate seed data against the 10 data standards rules** — seed validation report (B66). Need to run SQL checks against the seeded data.

14. **Generate the ERD diagram** — a visual ER diagram. Doesn't exist yet. Can be generated from the schema.

15. **Write data dictionary in spreadsheet form** — `14_data_dictionary.sql` is a stub. The actual data dictionary (with sensitivity class, nullability justification, etc.) needs to be in a file that can be shared.

16. **Check and add missing gig tables** — the explainer flags "Gig fav/blacklist table" and "Org location table" as pending schema items. Verify these.

17. **Verify subscription non-overlap EXCLUDE constraint** — flagged as missing in the explainer. The docket requires this (Rule Group 10).

18. **Run the compliance checks SQL and document zero-violation state** — capture the output and include it in the compliance table.

---

## 7. The UI / API Layer — What We Need to Leave for Your Friend

The docket explicitly says building the UI is **out of scope for us**. Your friend is handling it. What we need to give them is:

### Clean, well-named PostgreSQL endpoints (as functions/procedures)

The pattern in our codebase already uses stored procedures. We should expose these cleanly:

| Functionality | What to expose |
|---|---|
| Candidate search by skill + city | `SELECT` query → could become a view `v_candidate_search` |
| Job search by role + city + salary | `SELECT` query → view `v_job_search` |
| Pipeline summary for a job | View `v_job_pipeline` |
| Organisation hiring KPI | Already exists: `dw.mv_organisation_hiring_kpi` |
| Daily application funnel | Already exists: `dw.mv_daily_application_funnel` |
| Profile download | Already a stored procedure: `sp_download_profile()` |
| DW refresh | Already a stored procedure: `dw.sp_refresh_dw()` |

### What we need to create for your friend

We need to create a set of **clean, documented views and functions** that your friend can call from their backend. Think of these as the "API contract" between our DB work and their UI work.

We should write a short `api_contract.md` document that lists:
- View name / function name
- What it returns (columns, types)
- Parameters it accepts
- Example call
- Expected response

This is Phase 7 territory from the DDD playbook (LLD and API specs), but a simplified version. We should create at least:

1. `v_candidate_search(skill_id, city_id)` → candidate list
2. `v_job_search(role_id, city_id, salary_min)` → job list
3. `v_application_pipeline(job_id)` → stage counts
4. `v_recruiter_inbox(organisation_id)` → recent applications
5. `v_gig_requests_open()` → available gig requests
6. `dw.mv_daily_application_funnel` → already exists
7. `dw.mv_organisation_hiring_kpi` → already exists

These should all be **idempotent reads** (SELECT only). No side effects except the stored procedures that already exist.

---

## 8. Our Plan — How We Will Finish

### Where we are in the DDD lifecycle

We have done most of **Phases 1–3 (Discover, Model, Prove at small scale)**. We are at the start of **Phase 4 (Platform)**. We have not touched Phases 5–8 at all, but Phases 6–8 (Specify, Design, Release) are partially out of scope for a DB-design hackathon.

The judges' primary concern is **Gates G2, G3, and G4**:
- G2: Data dictionary done, rules stated, data classified ← partially done
- G3: Workflow coverage 100%, test suite passes, DDL clean ← tests exist but not documented formally
- G4: Full-volume data loaded, automated suites pass, NFRs met at volume ← not started

### Recommended order of work

**Session 1 — Scale the data (everything else depends on this)**
1. Update `seed/config.py` to: N_CANDIDATES=1_000_000, N_ORGS=10_000, N_JOBS=100_000, APPS_PER_JOB=50
2. Re-run `docker compose down -v && docker compose up` to rebuild with scale data
3. Capture row counts to confirm the seed ran correctly

**Session 2 — Run benchmarks and capture performance evidence**
4. Run `bench.py` against the 1M-scale database
5. Run the 12 queries in `13_benchmark.sql` with `EXPLAIN (ANALYZE, BUFFERS)`
6. Write `perf/performance_baseline.md` with hardware spec, dataset size, p50/p95/p99

**Session 3 — Write the extrapolation**
7. Write `perf/full_scale_extrapolation.md` projecting 1M → 10M profiles
8. Identify which query degrades first (likely Q01 or Q02 — skill+city search or fuzzy name)
9. State the degradation model (index size vs. cache hit ratio change)

**Session 4 — Documents the panel will review**
10. Fill in `docs/rule_compliance_table.md` (11 rule groups)
11. Fill in `docs/integration_boundary_table.md` (9 external systems × 5 columns)
12. Write `docs/competitive_coverage_matrix.md` (Naukri, Monster, LinkedIn vs. Talentra)
13. Write `docs/gig_model_decision.md` (D4 from decision log — Kshitij)

**Session 5 — Security documents**
14. Write `security/pii_handling_notes.md` (B75–B77)
15. Write `security/threat_model.md` (B78)
16. Combine into `security/security_design_note.md` (B81)

**Session 6 — API contract for your friend (the UI)**
17. Create clean views in a new SQL file `talentra_db/15_api_views.sql`
18. Write `docs/api_contract.md` documenting each view/function

**Session 7 — Final cleanup and verification**
19. Run backup and restore test (`backup_restore_test.sh`), record timing (B80)
20. Run tests in `12_tests.sql`, document pass/fail results (B79)
21. Generate ERD diagram
22. Final compliance check run: `11_compliance_checks.sql` → confirm 0 violations

### What "done" looks like

You should be able to walk into the panel and:
- Show a live database with 1M+ candidate profiles
- Run a skill+city search and show `EXPLAIN ANALYZE` output with index scans
- Show p50/p95/p99 latencies for all 12 queries
- Show the extrapolation to 10M, say which query breaks first and why
- Show the rule compliance table: all 11 rule groups checked, zero undocumented deviations
- Show the integration boundary table filled in for all 9 systems
- Show that every sensitive column has a data classification
- Show that the wallet ledger, audit log, and download history are append-only (with the test proof)
- Show RLS working: a recruiter cannot see another org's jobs (with the test proof)
- Explain the gig model decision (separate subsystem, not shared job model — with trade-offs written)

---

## Quick Reference — File Map for What Needs to be Created

| File to create | What it covers | Docket reference |
|---|---|---|
| `seed/config.py` (update only) | Scale to 1M profiles | B60–B64 |
| `perf/performance_baseline.md` | p50/p95/p99 for 12 queries at 1M scale | B70 |
| `perf/full_scale_extrapolation.md` | 1M → 10M projection | B74 |
| `docs/rule_compliance_table.md` | 11 rule groups, complies/deviations | Section 5 |
| `docs/integration_boundary_table.md` | 9 external systems × 5 columns | Section 6 |
| `docs/competitive_coverage_matrix.md` | Naukri/Monster/LinkedIn vs Talentra | Section 4 |
| `docs/gig_model_decision.md` | Gig subsystem vs shared model justification | Decision D4 |
| `docs/erd_diagram.md` (or .png) | Visual ER diagram | General |
| `security/pii_handling_notes.md` | Encryption/masking per module | B75–B77 |
| `security/threat_model.md` | Access control, audit, hashing, sessions | B78 |
| `security/security_design_note.md` | Combined security document | B81 |
| `talentra_db/15_api_views.sql` | Clean views for friend's UI to build on | Implicit |
| `docs/api_contract.md` | Document each view/function for the UI team | Implicit |

---

*This document was generated by analysing: `my-context/` PDFs (docket, framework, playbook), all `docs/` markdown files, all `talentra_db/` SQL files, and `seed/config.py`. Last updated: 19 October 2026.*
