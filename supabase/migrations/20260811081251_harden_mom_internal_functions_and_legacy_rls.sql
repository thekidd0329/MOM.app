-- MOM 1.1.0 server hardening.
-- These helpers are invoked internally by triggers/event triggers or by Edge
-- Functions using service_role. They are not public Data API endpoints.

alter function public.reject_mom_raw_cloud_memory_write()
  set search_path = '';
revoke execute on function public.reject_mom_raw_cloud_memory_write()
  from public, anon, authenticated;

alter function public.upsert_mom_profile_fact(
  text, text, text, text, text, real, uuid, text, jsonb
) set search_path = '';
revoke execute on function public.upsert_mom_profile_fact(
  text, text, text, text, text, real, uuid, text, jsonb
) from public, anon, authenticated;
grant execute on function public.upsert_mom_profile_fact(
  text, text, text, text, text, real, uuid, text, jsonb
) to service_role;

-- These functions exist in production but predate the repository's migration
-- history. Guard them so a clean database can still replay every migration.
do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    execute 'revoke execute on function public.rls_auto_enable() from public, anon, authenticated';
  end if;

  if to_regprocedure(
    'public.upsert_mom_profile_fact_v2(uuid,text,text,text,text,text,real,uuid,text,jsonb)'
  ) is not null then
    execute 'alter function public.upsert_mom_profile_fact_v2(uuid,text,text,text,text,text,real,uuid,text,jsonb) set search_path = ''''';
    execute 'revoke execute on function public.upsert_mom_profile_fact_v2(uuid,text,text,text,text,text,real,uuid,text,jsonb) from public, anon, authenticated';
    execute 'grant execute on function public.upsert_mom_profile_fact_v2(uuid,text,text,text,text,text,real,uuid,text,jsonb) to service_role';
  end if;
end;
$$;

-- Cache auth.uid() once per statement instead of re-evaluating it per row.
drop policy if exists mom_sessions_owner_all on public.mom_chat_sessions;
create policy mom_sessions_owner_all
on public.mom_chat_sessions
for all
to authenticated
using (owner_id = (select auth.uid()))
with check (owner_id = (select auth.uid()));

drop policy if exists mom_messages_owner_all on public.mom_chat_messages;
create policy mom_messages_owner_all
on public.mom_chat_messages
for all
to authenticated
using (
  exists (
    select 1
    from public.mom_chat_sessions as session
    where session.id = mom_chat_messages.session_id
      and session.owner_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1
    from public.mom_chat_sessions as session
    where session.id = mom_chat_messages.session_id
      and session.owner_id = (select auth.uid())
  )
);

drop policy if exists mom_memories_owner_all on public.mom_memories;
create policy mom_memories_owner_all
on public.mom_memories
for all
to authenticated
using (owner_id = (select auth.uid()))
with check (owner_id = (select auth.uid()));
