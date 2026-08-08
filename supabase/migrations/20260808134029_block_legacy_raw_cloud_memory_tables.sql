create or replace function public.reject_mom_raw_cloud_memory_write()
returns trigger
language plpgsql
as $$
begin
  raise exception 'raw_cloud_memory_disabled';
end;
$$;

drop trigger if exists mom_chat_messages_raw_cloud_write_block on public.mom_chat_messages;
create trigger mom_chat_messages_raw_cloud_write_block
before insert or update on public.mom_chat_messages
for each row execute function public.reject_mom_raw_cloud_memory_write();

drop trigger if exists mom_memories_raw_cloud_write_block on public.mom_memories;
create trigger mom_memories_raw_cloud_write_block
before insert or update on public.mom_memories
for each row execute function public.reject_mom_raw_cloud_memory_write();

comment on table public.mom_chat_messages is
  'Legacy tombstone table. Raw MOM chat is device-local; INSERT and UPDATE are blocked.';
comment on table public.mom_memories is
  'Legacy tombstone table. Raw MOM memories are device-local; INSERT and UPDATE are blocked.';
