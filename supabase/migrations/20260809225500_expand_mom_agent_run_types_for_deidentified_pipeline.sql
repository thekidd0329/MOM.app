alter table public.mom_agent_runs
  drop constraint if exists mom_agent_runs_agent_check;

alter table public.mom_agent_runs
  add constraint mom_agent_runs_agent_check
  check (
    agent = any (
      array[
        'mother'::text,
        'context_extractor'::text,
        'temporal'::text,
        'context_extractor_deidentified'::text,
        'temporal_deidentified'::text
      ]
    )
  );
