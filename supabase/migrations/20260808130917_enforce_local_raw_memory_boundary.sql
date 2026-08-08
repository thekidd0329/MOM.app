alter table public.mom_context_extractions alter column raw_text drop not null;

alter table public.mom_research_corpus
  add column if not exists privacy_version text not null default 'deid-v1',
  add column if not exists redaction_count integer not null default 0;

-- Legacy cloud-stored conversational content is intentionally removed without
-- reading it. MOM raw memory belongs on-device.
delete from public.mom_chat_messages;
delete from public.mom_memories;
delete from public.mom_context_extractions;
delete from public.mom_profile_facts;
delete from public.mom_temporal_items;

alter table public.mom_context_extractions
  drop constraint if exists mom_context_extractions_no_raw_text;
alter table public.mom_context_extractions
  add constraint mom_context_extractions_no_raw_text check (raw_text is null);

alter table public.mom_profile_facts
  drop constraint if exists mom_profile_facts_no_source_excerpt;
alter table public.mom_profile_facts
  add constraint mom_profile_facts_no_source_excerpt check (source_excerpt is null);

alter table public.mom_temporal_items
  drop constraint if exists mom_temporal_items_no_source_excerpt;
alter table public.mom_temporal_items
  add constraint mom_temporal_items_no_source_excerpt check (source_excerpt is null);

alter table public.mom_research_corpus
  drop constraint if exists mom_research_corpus_no_obvious_identifiers;
alter table public.mom_research_corpus
  add constraint mom_research_corpus_no_obvious_identifiers check (
    extraction::text !~* '([A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}|https?://|www\.|@[A-Za-z0-9_]{2,32}|\m[0-9]{3}-[0-9]{2}-[0-9]{4}\M)'
  );

comment on column public.mom_context_extractions.raw_text is
  'Privacy tombstone only. Raw conversation text is device-local and this column must remain NULL.';
comment on table public.mom_research_corpus is
  'Detached de-identified research corpus. Must contain no device, user, session, or raw transcript identifiers.';
