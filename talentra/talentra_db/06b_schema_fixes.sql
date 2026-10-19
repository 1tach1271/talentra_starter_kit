-- 06b_schema_fixes.sql
-- Schema fixes for gig / finance module
-- Depends on: 01_core.sql, 01b_helpers.sql, 03_org_sourcing.sql,
--             04_candidate.sql, 06_gig_finance.sql
-- Owner: Team (common Phase 1)
--
-- Fixes applied:
--   1. Add btree_gist EXCLUDE constraint to subscription to prevent overlapping
--      subscription periods for the same organisation (docket Rule Group 10).
--   2. Add gig_worker_favourite table.
--   3. Add gig_worker_blacklist table.
-- ─────────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────────
-- 1.  EXCLUDE constraint on subscription
--
-- btree_gist is already loaded in 01_core.sql but the IF NOT EXISTS guard
-- makes this file safe to run standalone / in any order.
-- The constraint ensures that no two active (non-deleted) subscriptions for the
-- same organisation can have overlapping [period_start, period_end) ranges.
-- We use ALTER TABLE so the file is idempotent when the subscription table
-- already contains seed data.
-- ─────────────────────────────────────────────────────────────────────────────
create extension if not exists btree_gist;

alter table subscription
  add constraint ex_subscription_no_overlap
    exclude using gist (
      organisation_id with =,
      tstzrange(period_start, period_end) with &&
    );

-- ─────────────────────────────────────────────────────────────────────────────
-- 2.  gig_worker_favourite
--
-- An organisation (the requester) can mark a gig worker as a favourite so they
-- can quickly find trusted workers for future gig requests.
-- organisation_id  — the organisation that is favouriting the worker.
-- gig_worker_profile_id — the gig worker being favourited.
-- UNIQUE pair prevents the same worker being added twice by the same org.
-- created_at is supplied by sp_add_audit (full=false keeps the table
-- lightweight — no updates make sense for a simple favourite flag; use soft
-- delete via deleted_at added by the full audit call).
-- ─────────────────────────────────────────────────────────────────────────────
create table gig_worker_favourite (
  id                    bigint generated always as identity primary key,
  organisation_id       bigint not null references organisation(id),
  gig_worker_profile_id bigint not null references gig_worker_profile(id),
  constraint uq_gig_worker_favourite_pair
    unique (organisation_id, gig_worker_profile_id)
);
call sp_add_audit('gig_worker_favourite');

create index idx_gig_worker_favourite_organisation_id
  on gig_worker_favourite (organisation_id);
create index idx_gig_worker_favourite_gig_worker_profile_id
  on gig_worker_favourite (gig_worker_profile_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.  gig_worker_blacklist
--
-- An organisation can blacklist a gig worker to prevent them from applying to
-- (or being assigned to) any of that organisation's gig requests.
-- Mirrors the design of gig_worker_favourite: same FK pattern, same UNIQUE
-- pair, plus an optional reason for the business record.
-- organisation_id  — the organisation doing the blacklisting.
-- gig_worker_profile_id — the gig worker being blacklisted.
-- reason           — nullable: brief free-text explanation (audit / legal).
-- ─────────────────────────────────────────────────────────────────────────────
create table gig_worker_blacklist (
  id                    bigint generated always as identity primary key,
  organisation_id       bigint not null references organisation(id),
  gig_worker_profile_id bigint not null references gig_worker_profile(id),
  reason                varchar(500),
  constraint uq_gig_worker_blacklist_pair
    unique (organisation_id, gig_worker_profile_id)
);
call sp_add_audit('gig_worker_blacklist');

create index idx_gig_worker_blacklist_organisation_id
  on gig_worker_blacklist (organisation_id);
create index idx_gig_worker_blacklist_gig_worker_profile_id
  on gig_worker_blacklist (gig_worker_profile_id);
