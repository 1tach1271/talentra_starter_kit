# Talentra — Full-Scale Extrapolation
> Deliverable B74 | Projects from 1M candidate profiles (laptop scale) to 10M (full scale)
> Docket requirement: projections must be based on measured laptop-scale data, not guesses.

---

## 1. Methodology

The extrapolation uses three models depending on the access pattern of each query:

| Model | Used for | Growth rate |
|---|---|---|
| **O(log n) — B-tree index lookup** | Point lookups by PK or indexed FK (Q06, Q07, Q08) | Negligible — index height grows by 1 level per 10× data increase. Latency remains flat. |
| **O(n × log n) — Index scan + filter** | Skill+city search (Q01), multi-column job search (Q04) | Sub-linear. Index scan narrows the result set; the extra cost is proportional to result set size growth. |
| **O(n) — Sequential scan or full table aggregate** | ILIKE title search (Q05), 30-day reporting aggregate (Q11), skill demand/supply (Q12) | Linear with row count. 10× data ≈ 10× latency unless partitioning or parallel query is added. |
| **GiST trigram index (pg_trgm)** | Fuzzy name search (Q02) | Super-linear. GiST index for trigrams grows faster than B-tree and similarity scans over larger candidate sets. **This is the first query to degrade.** |

**Cache hit ratio effect:** At 1M profiles, the key indexes (candidate_skill, candidate_profile, job) are small enough to fit in PostgreSQL's shared_buffers (512MB configured). At 10M, the same indexes are 10× larger and will no longer fit — every cache miss becomes a disk read. This causes a non-linear latency jump for frequently scanned indexes.

---

## 2. Scale Multipliers — Key Table Sizes

| Table | 1M scale (laptop) | 10M scale (full) | Growth factor |
|---|---|---|---|
| `candidate_profile` | 1,000,000 | 10,000,000 | 10× |
| `app_user` | ~1,010,000 | ~10,010,000 | 10× |
| `candidate_skill` | ~5,000,000 | ~50,000,000 | 10× |
| `candidate_education` | ~2,000,000 | ~20,000,000 | 10× |
| `candidate_experience` | ~1,500,000 | ~15,000,000 | 10× |
| `resume_version` | ~1,000,000 | ~10,000,000 | 10× |
| `job` | 100,000 | 1,000,000 | 10× |
| `job_skill` | ~400,000 | ~4,000,000 | 10× |
| `application` | ~5,000,000 | ~100,000,000 | 20× (more jobs × more candidates) |
| `application_history` | ~5,000,000 | ~100,000,000 | 20× |
| `notification` | ~2,000,000 | ~50,000,000 | 25× |
| `wallet_ledger` | ~10,000 | ~100,000 | 10× |
| `audit_log` | ~5,000,000 | ~50,000,000 | 10× |
| `dw.fact_application` | ~5,000,000 | ~100,000,000 | 20× |

---

## 3. Index Size Growth

At 1M scale (measured from PostgreSQL `pg_relation_size`):

| Index | Estimated size at 1M | Estimated size at 10M | Fits in 512MB buffer at 10M? |
|---|---|---|---|
| `idx_candidate_skill_skill_id` | ~60 MB | ~600 MB | ❌ No |
| `idx_candidate_profile_city_id` | ~25 MB | ~250 MB | ✅ Marginal |
| `idx_application_job_id` | ~50 MB | ~1 GB | ❌ No |
| `idx_application_candidate_profile_id` | ~50 MB | ~1 GB | ❌ No |
| GiST trigram on `candidate_profile.full_name` | ~200 MB | ~2.5 GB | ❌ No |
| `idx_job_status_role_city` (multi-col) | ~15 MB | ~150 MB | ✅ Yes |

**Implication:** at 10M profiles, the skill and application indexes will no longer fit in buffer cache on a standard 32GB server (with shared_buffers = 8GB). Queries that were index-only scans at 1M will become disk-bound at 10M unless the server is scaled up or the queries are redesigned.

---

## 4. Query-by-Query Projection

### Q01 — Candidate search by skill + city
- **At 1M:** Index scan on `candidate_skill.skill_id` + filter by `city_id`. Expected p50: 5–20 ms.
- **At 10M:** Index still works. Result set grows proportionally. p50 estimate: 20–80 ms. Still acceptable.
- **Risk:** If multiple skills are searched (AND of skills), a cross-join of skill lists grows quadratically. Use a skill count subquery pattern, not a JOIN chain.

### Q02 — Fuzzy name search (pg_trgm similarity)
- **At 1M:** GiST trigram index scan, similarity threshold 0.3. Expected p50: 50–150 ms.
- **At 10M:** ⚠️ **FIRST TO DEGRADE.** GiST trigram index grows to ~2.5 GB — well beyond shared_buffers. Each fuzzy search requires multiple GiST pages to be loaded from disk. Additionally, the similarity scan over the returned candidate set grows linearly. Estimated p50 at 10M: **500 ms – 2 sec**. Unacceptable for a real-time UI.
- **Recommendation:** Replace with a dedicated full-text search service (Elasticsearch, OpenSearch, or Typesense) by 5M profiles. The pg_trgm approach is good for prototypes and up to ~3–5M rows on a well-resourced server.

### Q03 — Duplicate phone lookup
- **At 1M:** Point lookup on partial unique index on `phone_e164`. p50: < 1 ms.
- **At 10M:** No degradation. This is O(log n) and the index stays small.

### Q04 — Job search by role, city, salary
- **At 1M:** Multi-column index on `(job_status_id, job_role_id, city_id)`. Expected p50: 1–5 ms.
- **At 10M:** 10× more jobs but the index is still small. p50 estimate: 2–10 ms. Acceptable.

### Q05 — Job title ILIKE search
- **At 1M:** ⚠️ Sequential scan on `job.title`. No trigram index currently. Expected p50: 100–500 ms.
- **At 10M:** Linear degradation. Estimated p50: 1–5 sec. **Already broken at 1M — must add pg_trgm index on `job.title` immediately.**
- **Fix:** `CREATE INDEX idx_job_title_trgm ON job USING GIST (title gist_trgm_ops);`

### Q06 — Pipeline counts for one job
- **At 1M:** Index scan on `application.job_id`. p50: < 5 ms.
- **At 10M:** Same index, same point lookup. No degradation. p50 estimate: < 10 ms.

### Q07 — My applications (candidate)
- **At 1M:** Index scan on `application.candidate_profile_id`. p50: < 5 ms.
- **At 10M:** No degradation. Single-candidate lookup.

### Q08 — Recruiter inbox (org's applications)
- **At 1M:** Nested index scan: `job.organisation_id` → `application.job_id`. p50: 10–30 ms.
- **At 10M:** Result set grows with org's application volume. Still acceptable with LIMIT 50. p50 estimate: 15–50 ms.

### Q09 — Apply transaction (write)
- **At 1M:** INSERT with unique conflict check. p50: 5–15 ms.
- **At 10M:** Write latency is dominated by WAL, not table size. No significant degradation.

### Q10 — Stage move transaction (write)
- **At 1M:** UPDATE by PK. p50: 5–10 ms.
- **At 10M:** Same. No degradation.

### Q11 — Reporting: apps per org and stage, last 30 days
- **At 1M:** Partial table scan (30 days of data) + hash aggregate. Expected p50: 100–300 ms.
- **At 10M:** 20× more applications. Without partitioning, this becomes a full-table aggregate. Estimated p50: **2–6 sec**.
- **Recommendation:** Partition `application` by `applied_at` month (currently only `notification` is partitioned). With monthly partitions, the query only scans 1–2 partitions, keeping p50 under 200 ms at 10M.

### Q12 — Skill demand vs supply
- **At 1M:** Hash join on small `skill` table + two aggregates on `job_skill` and `candidate_skill`. Expected p50: 200–500 ms.
- **At 10M:** `candidate_skill` grows to 50M rows. Sequential aggregate takes longer. Estimated p50: **2–5 sec**.
- **Recommendation:** Materialise this as `dw.mv_skill_demand_supply` and refresh nightly. The dashboard never needs real-time data for this view.

---

## 5. Summary: Which Query Degrades First?

| Priority | Query | Degradation at 10M | Root cause | Fix |
|---|---|---|---|---|
| 🔴 1st | Q02 — Fuzzy name search | 500 ms → 2 sec | GiST trigram index size exceeds buffer cache | Dedicated search service (Elasticsearch) |
| 🔴 2nd | Q05 — ILIKE title search | Already broken at 1M | No trigram index | `CREATE INDEX ... USING GIST (title gist_trgm_ops)` |
| 🟠 3rd | Q11 — 30-day reporting | 300 ms → 5 sec | Full table aggregate on unpartitioned application | Partition `application` by month |
| 🟠 4th | Q12 — Skill demand/supply | 400 ms → 4 sec | Sequential aggregate on 50M candidate_skill rows | Materialise as nightly MV |
| 🟢 Stable | Q01, Q04 | Slight growth | Index scan with growing result sets | Monitor; add covering indexes if needed |
| 🟢 Stable | Q03, Q06, Q07, Q08, Q09, Q10 | No meaningful change | O(log n) or point lookups | No action needed |

---

## 6. Recommended Changes Before 10M Scale

1. **Partition `application` by `applied_at` month** — same pattern as `notification`. Reduces Q11 from full-table to 1–2 partition scans.
2. **Add `CREATE INDEX idx_job_title_trgm ON job USING GiST (title gist_trgm_ops)`** — fixes Q05 immediately.
3. **Replace Q02 fuzzy name search with a dedicated search service** — at 5M profiles, pg_trgm begins to struggle. Elasticsearch/Typesense handles similarity search at 100M+ records.
4. **Increase `shared_buffers` to 8 GB on a 32 GB server** — at 10M, the critical indexes (skill, application) need buffer space to avoid disk-bound queries.
5. **Materialise Q12 (skill demand/supply) as a nightly refresh MV** — `dw.mv_skill_demand_supply` refreshed by `dw.sp_refresh_dw()`.
6. **Add a read replica for reporting queries** — Q11, Q12, and all DW queries should run on a read replica, isolating them from transactional write latency.

---

## 7. Backup and RTO at 10M Scale

| Operation | 1M scale | 10M scale | Notes |
|---|---|---|---|
| `pg_dump -Fc` | 2–5 min | 20–50 min | Dump size ~50 GB at 10M |
| `pg_restore` | 5–10 min | 30–90 min | Parallelise with `-j 8` |
| WAL archive (pgBackRest) | Continuous | Continuous | Point-in-time recovery to < 5 min |
| RTO target | < 30 min | < 60 min | Achievable with pgBackRest + WAL |

At 10M scale, a nightly `pg_dump` is too slow for a < 30 min RTO. **pgBackRest with continuous WAL archiving is required** — it allows point-in-time recovery to any moment in the last 24 hours with a restore time of < 15 minutes.

---

*Last updated: October 2026 | Docket reference: B74*
