create table if not exists public.mom_users (
  id uuid primary key default gen_random_uuid(),
  access_code_hash text unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  reset_at timestamptz
);

alter table public.mom_installations add column if not exists user_id uuid;
alter table public.mom_chat_sessions add column if not exists user_id uuid;
alter table public.mom_chat_messages add column if not exists user_id uuid;
alter table public.mom_profile_facts add column if not exists user_id uuid;
alter table public.mom_context_extractions add column if not exists user_id uuid;
alter table public.mom_temporal_items add column if not exists user_id uuid;
alter table public.mom_memories add column if not exists user_id uuid;
alter table public.mom_device_events add column if not exists user_id uuid;
alter table public.mom_agent_runs add column if not exists user_id uuid;

do $$
declare
  r record;
  v_user_id uuid;
begin
  for r in select id, device_id from public.mom_installations where user_id is null loop
    insert into public.mom_users default values returning id into v_user_id;
    update public.mom_installations set user_id = v_user_id where id = r.id;
    update public.mom_chat_sessions set user_id = v_user_id where device_id = r.device_id and user_id is null;
    update public.mom_chat_messages set user_id = v_user_id where device_id = r.device_id and user_id is null;
    update public.mom_profile_facts set user_id = v_user_id where device_id = r.device_id and user_id is null;
    update public.mom_context_extractions set user_id = v_user_id where device_id = r.device_id and user_id is null;
    update public.mom_temporal_items set user_id = v_user_id where device_id = r.device_id and user_id is null;
    update public.mom_agent_runs set user_id = v_user_id where device_id = r.device_id and user_id is null;
    update public.mom_device_events set user_id = v_user_id where installation_id = r.id and user_id is null;
    update public.mom_memories m
      set user_id = v_user_id
      from public.mom_chat_sessions s
      where m.user_id is null and m.session_id = s.id and s.device_id = r.device_id;
  end loop;
end $$;

create index if not exists mom_installations_user_id_idx on public.mom_installations(user_id);
create index if not exists mom_chat_sessions_user_id_idx on public.mom_chat_sessions(user_id);
create index if not exists mom_chat_messages_user_id_idx on public.mom_chat_messages(user_id);
create index if not exists mom_profile_facts_user_id_idx on public.mom_profile_facts(user_id);
create index if not exists mom_context_extractions_user_id_idx on public.mom_context_extractions(user_id);
create index if not exists mom_temporal_items_user_id_idx on public.mom_temporal_items(user_id);
create index if not exists mom_memories_user_id_idx on public.mom_memories(user_id);
create index if not exists mom_device_events_user_id_idx on public.mom_device_events(user_id);
create index if not exists mom_agent_runs_user_id_idx on public.mom_agent_runs(user_id);
create unique index if not exists mom_profile_facts_user_category_key_uidx
  on public.mom_profile_facts(user_id, category, normalized_key)
  where user_id is not null;

create table if not exists public.mom_research_corpus (
  id uuid primary key default gen_random_uuid(),
  extraction jsonb not null,
  model text,
  input_characters integer not null default 0,
  output_characters integer not null default 0,
  latency_ms integer,
  original_created_at timestamptz,
  detached_at timestamptz not null default now()
);

create table if not exists public.mom_data_dump (
  id uuid primary key default gen_random_uuid(),
  reset_id uuid not null default gen_random_uuid(),
  prior_user_id uuid,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.match_mom_chat_messages_for_user(
  p_user_id uuid,
  p_query_embedding vector,
  p_match_threshold double precision default 0.50,
  p_match_count integer default 12
)
returns table(
  id bigint,
  session_id uuid,
  role text,
  content text,
  created_at timestamptz,
  similarity double precision
)
language sql
stable
set search_path to ''
as $$
  select
    m.id,
    m.session_id,
    m.role,
    m.content,
    m.created_at,
    -(m.embedding operator(extensions.<#>) p_query_embedding) as similarity
  from public.mom_chat_messages as m
  where m.user_id = p_user_id
    and m.embedding is not null
    and m.role in ('user', 'assistant')
    and (m.embedding operator(extensions.<#>) p_query_embedding) < -p_match_threshold
  order by m.embedding operator(extensions.<#>) p_query_embedding
  limit least(greatest(p_match_count, 1), 24);
$$;

create or replace function public.upsert_mom_profile_fact_v2(
  p_user_id uuid,
  p_device_id text,
  p_category text,
  p_normalized_key text,
  p_value text,
  p_truth_state text,
  p_confidence real,
  p_source_session_id uuid,
  p_source_excerpt text,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_id uuid;
  v_existing public.mom_profile_facts%rowtype;
begin
  select * into v_existing
  from public.mom_profile_facts
  where user_id = p_user_id
    and category = p_category
    and normalized_key = p_normalized_key
  order by last_seen_at desc
  limit 1;

  if found then
    update public.mom_profile_facts
    set
      value = p_value,
      truth_state = case
        when v_existing.truth_state in ('explicit', 'confirmed') and p_truth_state = 'candidate'
          then v_existing.truth_state
        else p_truth_state
      end,
      confidence = case
        when v_existing.truth_state in ('explicit', 'confirmed') and p_truth_state = 'candidate'
          then v_existing.confidence
        else greatest(0, least(1, p_confidence))
      end,
      evidence_count = evidence_count + 1,
      source_session_id = coalesce(p_source_session_id, source_session_id),
      source_excerpt = p_source_excerpt,
      last_seen_at = now(),
      metadata = metadata || coalesce(p_metadata, '{}'::jsonb)
    where id = v_existing.id
    returning id into v_id;
    return v_id;
  end if;

  insert into public.mom_profile_facts(
    user_id, device_id, category, normalized_key, value, truth_state, confidence,
    source_session_id, source_excerpt, metadata
  ) values (
    p_user_id, p_device_id, p_category, p_normalized_key, p_value, p_truth_state,
    greatest(0, least(1, p_confidence)), p_source_session_id, p_source_excerpt,
    coalesce(p_metadata, '{}'::jsonb)
  ) returning id into v_id;

  return v_id;
end;
$$;

grant select, insert, update, delete on public.mom_users to service_role;
grant select, insert, update, delete on public.mom_research_corpus to service_role;
grant select, insert, update, delete on public.mom_data_dump to service_role;
grant execute on function public.match_mom_chat_messages_for_user(uuid, vector, double precision, integer) to service_role;
grant execute on function public.upsert_mom_profile_fact_v2(uuid, text, text, text, text, text, real, uuid, text, jsonb) to service_role;
