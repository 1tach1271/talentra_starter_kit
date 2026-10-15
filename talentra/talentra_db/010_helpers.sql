create or replace procedure sp_add_audit(p_table text, p_full boolean default true) language plpgsql as $$
begin
  execute format('alter table %I add column created_at timestamptz not null default now(), add column created_by bigint not null default 1 references app_user(id)', p_table);
  if p_full then
    execute format('alter table %I add column updated_at timestamptz not null default now(), add column updated_by bigint not null default 1 references app_user(id), add column deleted_at timestamptz', p_table);
    execute format('create trigger trg_%s_updated_at before update on %I for each row execute function fn_set_updated_at()', p_table, p_table);
  end if;
end $$;

create or replace function fn_block_mutation() returns trigger language plpgsql as $$
begin
  raise exception 'table % is append-only', tg_table_name using errcode = 'restrict_violation';
end $$;

create or replace procedure sp_make_append_only(p_table text) language plpgsql as $$
begin
  execute format('create trigger trg_%s_append_only before update or delete on %I for each row execute function fn_block_mutation()', p_table, p_table);
  execute format('create trigger trg_%s_no_truncate before truncate on %I for each statement execute function fn_block_mutation()', p_table, p_table);
end $$;

create or replace procedure sp_create_lookup(p_table text) language plpgsql as $$
begin
  execute format('create table %I (id bigint generated always as identity primary key, code varchar(60) not null, name varchar(200) not null, is_active boolean not null default true, constraint uq_%s_code unique (code))', p_table, p_table);
  call sp_add_audit(p_table);
end $$;

create or replace procedure sp_index_fks() language plpgsql as $$
declare r record;
begin
  for r in
    select c.conrelid::regclass::text as tbl, a.attname as col, c.conrelid as relid, c.conkey[1] as attnum
    from pg_constraint c
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    join pg_class t on t.oid = c.conrelid
    where c.contype = 'f' and array_length(c.conkey, 1) = 1
      and a.attname not in ('created_by', 'updated_by')
      and t.relispartition = false
      and c.connamespace = 'public'::regnamespace
      and not exists (select 1 from pg_index i where i.indrelid = c.conrelid and i.indkey[0] = c.conkey[1])
  loop
    execute format('create index idx_%s_%s on %s (%I)', r.tbl, r.col, r.tbl, r.col);
  end loop;
end $$;
