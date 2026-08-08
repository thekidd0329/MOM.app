create or replace function public.upsert_mom_profile_fact(
  p_device_id text,
  p_category text,
  p_normalized_key text,
  p_value text,
  p_truth_state text,
  p_confidence real,
  p_source_session_id uuid,
  p_source_excerpt text,
  p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into public.mom_profile_facts(
    device_id, category, normalized_key, value, truth_state, confidence,
    source_session_id, source_excerpt, metadata
  ) values (
    p_device_id, p_category, p_normalized_key, p_value, p_truth_state,
    greatest(0, least(1, p_confidence)), p_source_session_id, p_source_excerpt,
    coalesce(p_metadata, '{}'::jsonb)
  )
  on conflict (device_id, category, normalized_key) do update set
    value = excluded.value,
    truth_state = case
      when public.mom_profile_facts.truth_state = 'explicit' then 'explicit'
      else excluded.truth_state
    end,
    confidence = greatest(public.mom_profile_facts.confidence, excluded.confidence),
    evidence_count = public.mom_profile_facts.evidence_count + 1,
    source_session_id = coalesce(excluded.source_session_id, public.mom_profile_facts.source_session_id),
    source_excerpt = excluded.source_excerpt,
    last_seen_at = now(),
    metadata = public.mom_profile_facts.metadata || excluded.metadata
  returning id into v_id;

  return v_id;
end;
$$;
