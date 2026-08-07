-- MOM semantic chat memory.
-- Applied to the hosted Supabase project as migration: mom_chat_vector_memory.
-- Embeddings are generated with Supabase Edge Runtime's built-in gte-small model.

create extension if not exists vector with schema extensions;

alter table public.mom_chat_messages
  add column if not exists device_id text,
  add column if not exists embedding extensions.vector(384);

update public.mom_chat_messages as m
set device_id = s.device_id
from public.mom_chat_sessions as s
where s.id = m.session_id
  and m.device_id is null;

alter table public.mom_chat_messages
  alter column device_id set not null;

create index if not exists mom_chat_messages_device_created_idx
  on public.mom_chat_messages (device_id, created_at desc);

create index if not exists mom_chat_messages_embedding_hnsw_idx
  on public.mom_chat_messages
  using hnsw (embedding extensions.vector_ip_ops);

create or replace function public.match_mom_chat_messages(
  p_device_id text,
  p_query_embedding extensions.vector(384),
  p_match_threshold double precision default 0.50,
  p_match_count integer default 8
)
returns table (
  id bigint,
  session_id uuid,
  role text,
  content text,
  created_at timestamptz,
  similarity double precision
)
language sql
stable
set search_path = ''
as $$
  select
    m.id,
    m.session_id,
    m.role,
    m.content,
    m.created_at,
    -(m.embedding OPERATOR(extensions.<#>) p_query_embedding) as similarity
  from public.mom_chat_messages as m
  where m.device_id = p_device_id
    and m.embedding is not null
    and m.role in ('user', 'assistant')
    and (m.embedding OPERATOR(extensions.<#>) p_query_embedding) < -p_match_threshold
  order by m.embedding OPERATOR(extensions.<#>) p_query_embedding
  limit least(greatest(p_match_count, 1), 20);
$$;

-- Semantic recall is server-only. The app never receives arbitrary vector search access.
revoke all on function public.match_mom_chat_messages(text, extensions.vector, double precision, integer)
  from public, anon, authenticated;
grant execute on function public.match_mom_chat_messages(text, extensions.vector, double precision, integer)
  to service_role;
