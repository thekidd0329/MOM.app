# MOM Text MVP

A minimal texting interface for MOM.

## What this slice does

- serves a small browser chat UI;
- sends chat turns to an OpenAI-compatible model endpoint;
- keeps MOM-specific cognition in `core_llm/` and generic model plumbing here;
- persists a lightweight local transcript to `data/conversations.jsonl` when running locally;
- defaults to llama.cpp at `http://127.0.0.1:8080/v1` but can point at any compatible hosted endpoint.

## Run

From the repository root:

```bash
cd apps/text_mvp
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
python app.py
```

Open `http://127.0.0.1:8787`.

If llama.cpp is running locally in router mode, set `MOM_MODEL` to the model/preset name it exposes. For a hosted OpenAI-compatible endpoint, set `MOM_API_BASE`, `MOM_API_KEY`, and `MOM_MODEL` in `.env`.

## Design boundary

This folder is infrastructure and UI. MOM's identity, judgment, memory philosophy, and behavioral rules belong under `core_llm/`, consistent with the repository architecture decisions.
