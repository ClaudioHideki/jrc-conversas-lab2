\set ON_ERROR_STOP on
-- Exclusive disposable database created by CI; never the application's DB.
create role anon nologin;
create role authenticated nologin;
create table public.chamadas_pabx(id uuid primary key, account_id bigint, call_id text);
create table public.transcricoes_pabx(id bigserial primary key, account_id bigint, chamada_id uuid);
create table public.analises_qualidade_pabx(id bigserial primary key, account_id bigint, chamada_id uuid);
create view public.vw_qualidade_pabx_dashboard as select * from public.chamadas_pabx;
insert into public.chamadas_pabx values ('00000000-0000-0000-0000-000000000001',null,'legacy');
\ir ../../db/supabase_migrations/20261116000000_enforce_voice_quality_scope.sql
\ir ../../db/supabase_migrations/20261116000000_enforce_voice_quality_scope.sql
insert into public.chamadas_pabx values
 ('00000000-0000-0000-0000-000000000011',11,'same-call'),
 ('00000000-0000-0000-0000-000000000022',22,'same-call');
insert into public.transcricoes_pabx(account_id,chamada_id) values(11,'00000000-0000-0000-0000-000000000011');
do $$
begin
  begin
    insert into public.analises_qualidade_pabx(account_id,chamada_id) values(22,'00000000-0000-0000-0000-000000000011');
    raise exception 'Foreign parent accepted';
  exception when foreign_key_violation then null; end;
  begin
    insert into public.chamadas_pabx values ('00000000-0000-0000-0000-000000000033',null,'unscoped');
    raise exception 'Unscoped write accepted';
  exception when check_violation then null; end;
  begin
    update public.chamadas_pabx set account_id=22 where account_id=11;
    raise exception 'Account reassignment accepted';
  exception when check_violation then null; end;
  begin
    insert into public.chamadas_pabx values ('00000000-0000-0000-0000-000000000044',11,'same-call');
    raise exception 'Duplicate scoped call accepted';
  exception when unique_violation then null; end;
  if (select count(*) from public.chamadas_pabx where account_id is null) <> 1 then
    raise exception 'Legacy row changed';
  end if;
  if has_table_privilege('authenticated','public.vw_qualidade_pabx_dashboard','SELECT') or
     has_table_privilege('anon','public.chamadas_pabx','SELECT') then
    raise exception 'Browser role access granted';
  end if;
end $$;
select 'PASS: scoped duplicate IDs, parent isolation, immutable account, legacy preservation, browser denial, reexecution' as result;
