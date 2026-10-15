# B1: Database provider decision
**Decision: PostgreSQL 16.**  Date: 15 Oct 2026. Signed: Shashi, Kudrat, Kshitij.

| Docket requirement | PostgreSQL mechanism | MySQL gap |
|---|---|---|
| Non-overlapping subscription periods, gig windows, effective-dated recruiter mapping | EXCLUDE USING gist on range types (btree_gist) | No exclusion constraints; needs triggers and locks |
| Recruiter sees only own company; blocked party cannot see candidate | Row-Level Security policies | No native RLS; needs views or app logic |
| Device limit under concurrent logins | SELECT ... FOR UPDATE / advisory lock inside login transaction | Possible, but no advisory locks as clean |
| Partitioning applications and notifications | Declarative range/hash partitioning | Supported, more limits on FKs |
| Append-only audit and ledgers | Triggers + REVOKE UPDATE, DELETE | Similar |
| Check constraints, partial indexes, trigram search | Full support, pg_trgm, partial and expression indexes | Weaker (no partial indexes) |
| Execution plans for evidence | EXPLAIN (ANALYZE, BUFFERS) | EXPLAIN ANALYZE less detailed |

Risk: team must know RLS and gist exclusion. Mitigation: Shashi owns security patterns and shares examples.
Deviation from docket rules caused by this choice: none.
