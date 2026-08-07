# MOM Text MVP

This is the fastest runnable text version of MOM.

It is deliberately small:

- one local browser texting interface;
- one MOM identity prompt;
- one llama.cpp OpenAI-compatible model adapter;
- local SQLite conversation continuity;
- no framework dependencies.

## Run

1. Put a GGUF model on the machine. The default expected path is:

   `$HOME/MomBrain/models/Meta-Llama-3-8B-Instruct-abliterated-v3_q4.gguf`

2. From this folder:

   `bash run.sh`

   Or pass another GGUF:

   `bash run.sh /path/to/model.gguf`

3. Open:

   `http://127.0.0.1:7331`

The runner starts llama.cpp on `127.0.0.1:8080`, waits for it to become healthy, then starts MOM's text interface.

## If llama.cpp is already running

Just run:

`python3 app.py`

Optional environment variables:

- `MOM_LLM_URL` defaults to `http://127.0.0.1:8080/v1/chat/completions`
- `MOM_MODEL` optionally sends a model name to a router/provider
- `MOM_DB` changes the local SQLite path
- `MOM_HOST` defaults to `127.0.0.1`
- `MOM_PORT` defaults to `7331`

## Storage

The MVP keeps chat continuity locally in `mom_local.db` beside the app. Supabase has matching cloud-side session/message/memory tables for the next sync layer, but local chat does not depend on cloud availability.

## Architectural boundary

The model is replaceable. MOM is not.

The base model generates language. MOM identity, continuity, memory semantics, relationship behavior, and future learning logic belong above the model adapter.
