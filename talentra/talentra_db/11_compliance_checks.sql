select 'missing_created_at' as rule, c.relname as object from pg_class c
 where c.relkind in ('r','p') and c.relnamespace = 'public'::regnamespace and not c.relispartition
   and not exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'created_at' and not a.attisdropped)
union all
select 'missing_created_by', c.relname from pg_class c
 where c.relkind in ('r','p') and c.relnamespace = 'public'::regnamespace and not c.relispartition
   and not exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'created_by' and not a.attisdropped)
union all
select 'primary_key_not_named_id', c.conrelid::regclass::text from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
 where c.contype = 'p' and c.connamespace = 'public'::regnamespace and a.attname <> 'id' and not exists (select 1 from pg_class k where k.oid = c.conrelid and k.relispartition) and c.conrelid::regclass::text <> 'notification'
union all
select 'fk_without_index', c.conrelid::regclass::text || '.' || a.attname from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
 join pg_class k on k.oid = c.conrelid
 where c.contype = 'f' and c.connamespace = 'public'::regnamespace and a.attname not in ('created_by','updated_by') and not k.relispartition
   and not exists (select 1 from pg_index i where i.indrelid = c.conrelid and i.indkey[0] = c.conkey[1])
union all
select 'float_column', table_name || '.' || column_name from information_schema.columns
 where table_schema in ('public','dw') and data_type in ('real','double precision')
union all
select 'timestamp_without_timezone', table_name || '.' || column_name from information_schema.columns
 where table_schema in ('public','dw') and data_type = 'timestamp without time zone'
union all
select 'not_snake_case', table_name || '.' || column_name from information_schema.columns
 where table_schema in ('public','dw') and column_name ~ '[A-Z ]'
union all
select 'plural_table_name', c.relname from pg_class c
 where c.relkind in ('r','p') and c.relnamespace = 'public'::regnamespace and not c.relispartition and c.relname ~ 's$' and c.relname !~ '(status|address|business|class)$'
union all
select 'reserved_word', c.relname from pg_class c join pg_get_keywords() k on k.word = c.relname and k.catcode = 'R'
 where c.relkind in ('r','p') and c.relnamespace in ('public'::regnamespace, 'dw'::regnamespace)
union all
select 'reserved_word_column', table_name || '.' || column_name from information_schema.columns c join pg_get_keywords() k on k.word = c.column_name and k.catcode = 'R'
 where table_schema in ('public','dw')
union all
select 'money_not_numeric', table_name || '.' || column_name from information_schema.columns
 where table_schema in ('public','dw') and column_name ~ '(amount|price|salary|fee|rate|total|subtotal)$' and data_type <> 'numeric' and column_name !~ '(rating|_id$)'
union all
select 'fk_column_not_ending_id', c.conrelid::regclass::text || '.' || a.attname from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
 where c.contype = 'f' and c.connamespace in ('public'::regnamespace, 'dw'::regnamespace) and a.attname !~ '_id$' and a.attname not in ('created_by','updated_by');
