-- 095_index_fks.sql
-- Creates indexes for any FK columns that are missing one.
-- sp_index_fks() is defined in 010_helpers.sql.
-- This file runs automatically when Docker initialises the DB from
-- docker-entrypoint-initdb.d/, ensuring all FK columns are indexed
-- before the seed data is loaded.

call sp_index_fks();
