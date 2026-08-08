create table if not exists public.mom_context_extractions (
  id uuid primary key default gen_random_uuid(),
  device_id text not null,
  session_id uuid null references public.mom_chat_sessions(id) on delete set null,
  raw_text text not null,
  extraction jsonb not null default '{}'::jsonb,
  model text null,
  input_characters integer not null default 0,
  output_characters integer not null default 0,
  latency_ms integer null,
  created_at timestamptz not null default now()
);

create index if not exists mom_context_extractions_device_created_idx
  on public.mom_context_extractions(device_id, created_at desc);

create table if not exists public.mom_profile_facts (
  id uuid primary key default gen_random_uuid(),
  device_id text not null,
  category text not null check (category in ('core_emotions','vulnerabilities','life_details','implicit_needs','inferences')),
  normalized_key text not null,
  value text not null,
  truth_state text not null default 'explicit' check (truth_state in ('explicit','inferred')),
  confidence real not null default 1.0 check (confidence >= 0 and confidence <= 1),
  evidence_count integer not null default 1 check (evidence_count >= 1),
  source_session_id uuid null references public.mom_chat_sessions(id) on delete set null,
  source_excerpt text null,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique(device_id, category, normalized_key)
);

create index if not exists mom_profile_facts_device_category_idx
  on public.mom_profile_facts(device_id, category, last_seen_at desc);

create table if not exists public.mom_temporal_items (
  id uuid primary key default gen_random_uuid(),
  device_id text not null,
  session_id uuid null references public.mom_chat_sessions(id) on delete set null,
  extraction_id uuid null references public.mom_context_extractions(id) on delete set null,
  kind text not null check (kind in ('task','reminder','deadline','appointment','follow_up','event')),
  title text not null,
  detail text null,
  due_at timestamptz null,
  time_text text null,
  urgency real not null default 0.5 check (urgency >= 0 and urgency <= 1),
  importance real not null default 0.5 check (importance >= 0 and importance <= 1),
  status text not null default 'open' check (status in ('open','done','dismissed')),
  source_excerpt text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists mom_temporal_items_device_open_due_idx
  on public.mom_temporal_items(device_id, status, due_at);

create table if not exists public.mom_agent_runs (
  id bigserial primary key,
  device_id text not null,
  session_id uuid null references public.mom_chat_sessions(id) on delete set null,
  agent text not null check (agent in ('mother','context_extractor','temporal')),
  model text null,
  success boolean not null default true,
  input_characters integer not null default 0,
  output_characters integer not null default 0,
  facts_produced integer not null default 0,
  temporal_items_produced integer not null default 0,
  latency_ms integer null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists mom_agent_runs_device_created_idx
  on public.mom_agent_runs(device_id, created_at desc);
