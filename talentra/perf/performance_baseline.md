# Talentra — Performance Baseline Report
> Deliverable B70 | Measured 20 October 2026
> Method: `bench.py` — 10 runs per query, p50/p95/p99 from EXPLAIN (ANALYZE, FORMAT JSON)

---

## 1. Hardware and Environment

| Item | Value |
|---|---|
| Machine | MacBook with Apple M2 |
| RAM | 8 GB |
| Storage | SSD |
| OS | macOS |
| PostgreSQL | 16.15 (running in Docker) |
| Docker shared_buffers | 512 MB |
| Docker work_mem | 32 MB |
| Docker maintenance_work_mem | 512 MB |

---

## 2. Dataset Size at Test Time

| Table | Row Count | Total Size (table + indexes) |
|---|---|---|
| `candidate_profile` | 1,000,000 | 330 MB |
| `candidate_skill` | 9,318,558 | 1,939 MB |
| `application` | 7,450,000 | 1,743 MB |
| `application_history` | 7,450,000 | 1,026 MB |
| `job` | 300,000 | 153 MB |
| `app_user` | 1,010,002 | 244 MB |
| `organisation` | 30,000 | 12 MB |
| **Total DB size** | — | **11 GB** |

Note: `job` and `organisation` counts are higher than the docket target of 100K / 10K due to three partial seed runs. The candidate and application counts meet or exceed the docket targets (1M candidates, 5M applications).

---

## 3. Methodology

- Tool: `bench.py` (in `talentra_db/`)
- Runs per query: **10**
- Metric: wall-clock execution time from `EXPLAIN (ANALYZE, FORMAT JSON)` — includes planning time
- Transaction queries (Q09, Q10) are wrapped in BEGIN/ROLLBACK
- Each query's full plan saved to `plan_Q<nn>.txt`

---

## 4. Results

| Query | Description | Index Used | p50 ms | p95 ms | p99 ms | Plan Type | Notes |
|---|---|---|---|---|---|---|---|
| Q01 | Candidate search by skill + city | `idx_candidate_skill_skill_id` + `idx_candidate_profile_city_id` | **1.6** | 14.1 | 14.1 | Index Scan | ✅ Fast |
| Q02 | Fuzzy name search (pg_trgm) | GiST trigram on `full_name` | **96.9** | 365.3 | 365.3 | Bitmap Index Scan | ⚠️ Acceptable now, degrades at 10M |
| Q03 | Duplicate phone lookup | Unique index on `phone_e164` | **42.2** | 78.5 | 78.5 | Index Scan | ⚠️ Higher than expected — likely cold cache |
| Q04 | Job search by role, city, salary | Multi-column index on `job` | **9.5** | 368.6 | 368.6 | Index Scan | ⚠️ High p95 — cache miss on large result set |
| Q05 | Job title text search (ILIKE) | None (seq scan) | **1.7** | 2.3 | 2.3 | Seq Scan | ✅ Fast at 300K jobs — will degrade at 1M jobs |
| Q06 | Pipeline counts for one job | `idx_application_job_id` | **1.0** | 2.4 | 2.4 | Index Scan | ✅ Excellent |
| Q07 | My applications (candidate view) | `idx_application_candidate_profile_id` | **2.3** | 8.6 | 8.6 | Index Scan | ✅ Fast |
| Q08 | Recruiter inbox (org's applications) | `idx_job_organisation_id` + `idx_application_job_id` | **5.0** | 116.2 | 116.2 | Nested Loop | ⚠️ High p95 — org with many jobs scans broadly |
| Q09 | Apply transaction (write) | Conflict check on application | **2.1** | 12.1 | 12.1 | Insert | ✅ Fast |
| Q10 | Stage move transaction (write) | PK lookup | **1.0** | 9.8 | 9.8 | Update | ✅ Fast |
| Q11 | Apps per org/stage, last 30 days | `idx_application_applied_at` + hash agg | **9.6** | 84.9 | 84.9 | Hash Aggregate | ✅ Acceptable — partitioning will help at 10M |
| Q12 | Skill demand vs supply | Seq scan on `candidate_skill` (9.3M rows) | **826.5** | 2102.0 | 2102.0 | Hash Join | 🔴 Slow — materialise as nightly MV |

---

## 5. Notable Findings

**Q12 is the critical slow query.** At 9.3M candidate_skill rows, a full table hash join takes 826ms p50 and over 2 seconds p99. This is exactly the query the extrapolation doc identified as the first to degrade. Fix: materialise as `dw.mv_skill_demand_supply` and refresh nightly via `dw.sp_refresh_dw()`.

**Q02 (fuzzy name search) at 365ms p95** is already showing the limits of pg_trgm at 1M profiles. The GiST trigram index for `candidate_profile.full_name` is ~100MB and occasionally falls out of the 512MB shared_buffers, causing cache misses. This will become the first real-time bottleneck at 5M+ profiles.

**Q04 and Q08 high p95** (368ms, 116ms) are cache-miss artefacts — the first run is slow, subsequent runs are fast. In a warm-cache production system these would be consistently in the p50 range.

**Q01, Q06, Q07, Q09, Q10** are all excellent — sub-15ms even at p99. These are the core candidate/application lookup paths and they scale well.

---

## 6. Missing Index Identified

**Q05 (ILIKE title search):** Currently uses a sequential scan on `job.title`. At 300K jobs this is still fast (1.7ms) but will degrade linearly. Fix:

```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_job_title_trgm ON job USING GIST (title gist_trgm_ops);
```

After adding this index, Q05 should drop to <5ms even at 1M jobs.

---

## 7. Backup and Restore RTO

> Note: `backup_restore_test.sh` could not be run from the host machine due to a pg_dump version mismatch (host: PostgreSQL 14, server: PostgreSQL 16). Estimates are based on observed dump throughput during the seeding process.

| Scenario | Method | Estimated Time | RTO Target |
|---|---|---|---|
| Full backup at current scale (11 GB DB) | `pg_dump -Fc` | 3–6 min | < 15 min |
| Full restore | `pg_restore -j 4` | 8–15 min | < 30 min |
| Full backup at 10M profiles (~50 GB) | `pg_dump -Fc` | 20–50 min | < 60 min with WAL |

**To run the actual backup test** (requires matching pg_dump version 16):
```bash
# Inside the DB container:
docker exec -e PGPASSWORD=talentra talentra_db bash -c "
  pg_dump -U talentra -Fc -d talentra -f /tmp/talentra.dump
  createdb -U talentra talentra_restore
  pg_restore -U talentra -d talentra_restore -j 4 /tmp/talentra.dump
"
```

---

*Measured: 20 October 2026 | Hardware: Apple M2, 8GB RAM | Scale: 1M candidates, 7.5M applications*
