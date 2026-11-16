-- Apply only after the real external schema is audited and separately authorized.
-- No backfill, deletion or reassignment of historical rows. Duplicate scoped
-- calls block this transaction; they must never be resolved by guessing.
begin;

create unique index if not exists uq_voice_quality_account_call
  on public.chamadas_pabx(account_id, call_id) where account_id is not null;
create unique index if not exists uq_voice_quality_account_parent
  on public.chamadas_pabx(account_id, id);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'voice_transcription_account_parent'
                 and conrelid = 'public.transcricoes_pabx'::regclass) then
    alter table public.transcricoes_pabx add constraint voice_transcription_account_parent
      foreign key(account_id, chamada_id) references public.chamadas_pabx(account_id, id) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'voice_analysis_account_parent'
                 and conrelid = 'public.analises_qualidade_pabx'::regclass) then
    alter table public.analises_qualidade_pabx add constraint voice_analysis_account_parent
      foreign key(account_id, chamada_id) references public.chamadas_pabx(account_id, id) not valid;
  end if;
end $$;

create or replace function public.jrc_voice_quality_scope_guard() returns trigger
language plpgsql set search_path = pg_catalog, public as $$
begin
  if new.account_id is null or new.account_id <= 0 then
    raise exception 'Account scope required' using errcode = '23514';
  end if;
  if tg_op = 'UPDATE' and old.account_id is distinct from new.account_id then
    raise exception 'Account scope immutable' using errcode = '23514';
  end if;
  return new;
end $$;
revoke all on function public.jrc_voice_quality_scope_guard() from public;

do $$
declare target text; role_name text;
begin
  foreach target in array array['chamadas_pabx','transcricoes_pabx','analises_qualidade_pabx'] loop
    if not exists (select 1 from pg_trigger where tgname = 'jrc_voice_quality_scope_guard'
                    and tgrelid = ('public.' || target)::regclass) then
      execute format('create trigger jrc_voice_quality_scope_guard before insert or update on public.%I '
                     'for each row execute function public.jrc_voice_quality_scope_guard()', target);
    end if;
    execute format('alter table public.%I enable row level security', target);
    execute format('revoke all on public.%I from public', target);
    foreach role_name in array array['anon','authenticated'] loop
      if exists (select 1 from pg_roles where rolname = role_name) then
        execute format('revoke all on public.%I from %I', target, role_name);
      end if;
    end loop;
  end loop;
  if to_regclass('public.vw_qualidade_pabx_dashboard') is not null then
    alter view public.vw_qualidade_pabx_dashboard set (security_invoker = true);
    revoke all on public.vw_qualidade_pabx_dashboard from public;
    foreach role_name in array array['anon','authenticated'] loop
      if exists (select 1 from pg_roles where rolname = role_name) then
        execute format('revoke all on public.vw_qualidade_pabx_dashboard from %I', role_name);
      end if;
    end loop;
  end if;
end $$;
commit;
