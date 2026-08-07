# MOM Native

MOM's installable client for Linux Mint, Android, and iOS.

## Product behavior

- Linux: native Flutter desktop app. It can start the installed `llama` launcher itself in router mode using `~/MomBrain/models`, so normal use does not require a terminal.
- Android: native APK. Hosted OpenAI-compatible inference is configured inside Settings and the API key is stored with platform secure storage.
- iOS: native Flutter/iOS target. CI compiles an unsigned build; installing on a physical iPhone requires Apple signing/TestFlight.
- All platforms: local transcript persistence, MOM identity prompt, repository knowledge retrieval, Supabase chat sync, per-install server-validated device token, privacy-scoped runtime telemetry, settings, and diagnostics.

## Knowledge / folder access

`tools/build_mom_knowledge.py` creates a read-only JSONL knowledge bundle from supported project text/code across the repository. Models, `.env` files, Git internals, generated builds, caches, and local transcripts are excluded.

Linux additionally reads the configured live repository folder at runtime. Android and iOS use the build-time knowledge bundle, so MOM can reference the same project-authored folders without needing unrestricted mobile filesystem access.

## Supabase

The native clients call the `mom-sync` Edge Function. They never contain a service-role key. First launch registers a random device ID and receives a device token stored in secure storage. The function validates that token before chat, event, history, or candidate-memory writes.

Cloud tables used by this slice:
- `mom_installations`
- `mom_device_events`
- `mom_chat_sessions`
- `mom_chat_messages`
- `mom_memories`

## Data collection

Cloud conversation sync and product/runtime telemetry are separate switches. Runtime telemetry includes event type, platform/runtime context, response latency, model name, response size, error type, and knowledge-document counts. Model API keys are not sent to telemetry.

## Tests

`.github/workflows/mom-native.yml` runs static analysis and unit tests, checks the live Supabase sync health endpoint, then builds:
- `mom-linux-amd64.deb`
- Android release APK
- unsigned iOS release app archive

The in-app Diagnostics screen separately validates configuration ranges, local storage, knowledge access, repository access, Supabase connectivity/device registration, local llama.cpp status, model endpoint connectivity, and model resolution.
