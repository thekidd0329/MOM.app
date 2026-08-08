grant select, insert, update, delete on table
  public.mom_context_extractions,
  public.mom_profile_facts,
  public.mom_temporal_items,
  public.mom_agent_runs
  to service_role;

grant usage, select on sequence public.mom_agent_runs_id_seq to service_role;

grant execute on function public.upsert_mom_profile_fact(
  text, text, text, text, text, real, uuid, text, jsonb
) to service_role;
