-- 000_setup.sql: extensions and shared helpers
CREATE EXTENSION IF NOT EXISTS btree_gist;      -- exclusion constraints on ranges
CREATE EXTENSION IF NOT EXISTS pg_trgm;         -- fuzzy name search and duplicate detection
CREATE EXTENSION IF NOT EXISTS pgcrypto;        -- gen_random_uuid, digest, pgp encryption
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- keeps updated_at correct on every business table
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- blocks UPDATE/DELETE on append-only tables (audit, ledger, history)
CREATE OR REPLACE FUNCTION forbid_change() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'table % is append-only', TG_TABLE_NAME;
END;
$$ LANGUAGE plpgsql;
