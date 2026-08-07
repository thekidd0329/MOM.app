# MOM

Repository scaffold and runtime experiments for MOM.

## Runnable text MVP

The first runnable MOM surface now lives at:

`apps/text_mvp/`

It provides:
- a minimal browser texting interface;
- MOM's runtime identity loaded from `core_llm/mom_identity/runtime_prompt.md`;
- an OpenAI-compatible model adapter that defaults to local llama.cpp at `http://127.0.0.1:8080/v1`;
- local persistent conversation transcripts;
- optional mirroring into the existing Supabase `mom_chat_sessions` and `mom_chat_messages` tables.

Start with `apps/text_mvp/README.md`.

## Core separation

`core_llm/` is reserved for the cognition that makes MOM uniquely MOM. Generic model plumbing, app code, platform behavior, permissions, integrations, and hardware belong elsewhere.

## Current learning milestone

The first implemented foundation is MOM's trustworthy user-learning contract:

`observe -> interpret -> confirm when needed -> store -> retrieve -> correct -> grow`

See `learning_model/README.md` and `docs/decisions/0001-learning-truth-model.md`.
