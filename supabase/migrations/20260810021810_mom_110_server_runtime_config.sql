create table if not exists public.mom_runtime_config (
  config_key text primary key,
  config_value jsonb not null default '{}'::jsonb,
  enabled boolean not null default true,
  min_app_version text not null default '1.1.0',
  updated_at timestamptz not null default now(),
  constraint mom_runtime_config_key_format check (config_key ~ '^[a-z0-9][a-z0-9._-]{0,79}$'),
  constraint mom_runtime_config_value_object check (jsonb_typeof(config_value) = 'object')
);

comment on table public.mom_runtime_config is
  'Server-authoritative non-secret MOM runtime configuration. Read only through authenticated Edge Functions.';
comment on column public.mom_runtime_config.config_value is
  'Non-secret configuration only. Credentials belong in Supabase secrets or Vault.';

alter table public.mom_runtime_config enable row level security;
revoke all on table public.mom_runtime_config from anon, authenticated;
grant select, insert, update, delete on table public.mom_runtime_config to service_role;

insert into public.mom_runtime_config (
  config_key,
  config_value,
  enabled,
  min_app_version
) values (
  'mobile.runtime',
  jsonb_build_object(
    'schema_version', 1,
    'release', '1.1.0',
    'runtime_authority', 'supabase',
    'prompt_authority', 'mom-brain',
    'model_authority', 'mom-brain',
    'brain_path', '/functions/v1/mom-brain',
    'temperature', 0.72,
    'max_history', 8,
    'request_timeout_seconds', 300,
    'raw_memory_location', 'device_only',
    'cloud_raw_chat_storage', false,
    'bundled_runtime_prompt_required', false,
    'bundled_repository_knowledge_required', false,
    'trademark_ui_assets', 'device_bundled',
    'native_voice_runtime', 'device_bundled'
  ),
  true,
  '1.1.0'
)
on conflict (config_key) do update
set config_value = excluded.config_value,
    enabled = excluded.enabled,
    min_app_version = excluded.min_app_version,
    updated_at = now();
