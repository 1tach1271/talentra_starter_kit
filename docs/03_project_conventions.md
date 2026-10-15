# Project conventions (locked on day 1)
1. snake_case; singular table names; PK `id`; FK `<table>_id`.
2. Index: idx_<table>_<column>. Unique: uq_<table>_<column>. Check: ck_<table>_<rule>. FK: fk_<table>_<column>.
3. PK type: `bigint GENERATED ALWAYS AS IDENTITY` everywhere. Exposed external ids use a separate `public_id uuid` column when needed.
4. Natural keys (iso codes, esco_uri, tax id) are UNIQUE constraints, never PKs.
5. Every FK states an explicit ON DELETE (RESTRICT by default; CASCADE only for owned child rows; SET NULL only for optional links). ON UPDATE is NO ACTION because PKs never change.
6. Timestamps: timestamptz, UTC. Dates: date. Money: numeric(14,2) + currency_code char(3). Percent: numeric(5,2) with CHECK 0..100.
7. Email: text, max 254, lowercase (CHECK email = lower(email)). Phone: E.164 text + country_id.
8. Person name: varchar(150). Free text: varchar with stated limit. Unbounded text only for job description and resume body.
9. Enumerations: reference_code tables (code, per-language display name, is_active, sort_order). No Postgres ENUM, no free text.
10. Booleans: NOT NULL with explicit DEFAULT.
11. Business tables carry created_at, created_by, updated_at, updated_by (trigger sets updated_at).
    created_by/updated_by are nullable (system and seed rows have no actor); FK to app_user added in schema/900_audit_fks.sql.
12. Delete policy: soft delete (deleted_at) for candidate_profile, job_requirement, organisation, gig_request, resume. Master data: deactivate via is_active. Audit, ledger, history, view/download tables: append-only, no delete.
13. Nullable columns: each needs a comment justifying it (COMMENT ON COLUMN). Unknown vs not applicable use separate columns or reference codes, never 0 or 'NA'.
14. Sensitivity class (Public/Internal/Personal/Sensitive) goes in docs/data_dictionary.xlsx for every column.
15. Physical objects: views v_<name>; materialised views mv_<name>; partitions <table>_p<yyyymm>; analytics objects prefixed dw_ (dw_dim_*, dw_fact_*, dw_agg_*).
16. Avoid reserved words: use app_user (not user), job_order (not order), app_role (not role), user_session (not session), no column named key, group, desc, limit, offset, check.
17. Language fallback: requested language -> language row where is_default = true (en).
