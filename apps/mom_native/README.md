# MOM Native

MOM's installable client for Linux Mint, Android, and iOS.

## Product behavior

- Linux: native Flutter desktop app. Server-hosted inference is the default; local llama.cpp remains available as an explicit development/advanced option.
- Android: native APK. Hosted inference always goes through the Supabase `mom-brain` Edge Function. No Hugging Face or other hosted-model credential is stored in the APK or platform secure storage.
- iOS: native Flutter/iOS target. CI compiles an unsigned build; installing on a physical iPhone requires Apple signing/TestFlight.
- All platforms: local transcript persistence, MOM identity prompt, repository knowledge retrieval, Supabase chat sync, per-install server-validated device token, privacy-scoped runtime telemetry, settings, and diagnostics.

## Knowledge / folder access

`tools/build_mom_knowledge.py` creates a read-only JSONL knowledge bundle from supported project text/code across the repository. Models, `.env` files, Git internals, generated builds, caches, and local transcripts are excluded.

Linux additionally reads the configured live repository folder at runtime. Android and iOS use the build-time knowledge bundle, so MOM can reference the same project-authored folders without needing unrestricted mobile filesystem access.

## Supabase

The native clients use two server boundaries:

- `mom-sync` registers installations and brokers chat history, runtime events, history retrieval, and candidate-memory writes.
- `mom-brain` brokers hosted LLM inference and owns the hosted-provider credential server-side. Production can source that credential from Supabase server-side storage without exposing it to the client.

First launch registers a random device ID and receives a device token stored in platform secure storage. Both server functions validate that installation token before protected operations. Hosted provider credentials never need to be present on the device. Older MOM builds that stored a hosted-model key have that legacy key deleted on configuration load.

Cloud tables used by this slice:
- `mom_installations`
- `mom_device_events`
- `mom_chat_sessions`
- `mom_chat_messages`
- `mom_memories`

## Data collection

Cloud conversation sync and product/runtime telemetry are separate switches. Runtime telemetry includes event type, platform/runtime context, response latency, model name, response size, error type, and knowledge-document counts. Hosted provider credentials remain server-side and are not telemetry fields.

## Tests

`.github/workflows/mom-native.yml` runs static analysis and unit tests, checks the live Supabase sync health endpoint, then builds:
- `mom-linux-amd64.deb`
- Android release APK
- unsigned iOS release app archive

`.github/workflows/mom-brain-proxy.yml` additionally performs an end-to-end server smoke test against the deployed `mom-brain` function using a temporary CI installation identity. It verifies Supabase can see its hosted-model secret, that Hugging Face model discovery succeeds, and that a real chat completion can return through the server proxy.

The in-app Diagnostics screen separately validates configuration ranges, local storage, knowledge access, repository access, Supabase connectivity/device registration, optional local llama.cpp status, and model connectivity.
