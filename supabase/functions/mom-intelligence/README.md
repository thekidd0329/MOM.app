# MOM intelligence brain contract

`mom-intelligence` never sends a free-form system prompt or model choice to `mom-brain`.

It uses the authenticated, server-owned `agent` action with one of two bounded modes:

- `context_extractor`
- `temporal`

The corresponding prompts live inside `mom-brain` and cannot be replaced by the client. Intelligence input must already satisfy the `deid-v1` privacy boundary before it reaches this function.

The hosted provider remains Hugging Face. Model selection is server-owned, DeepSeek-family models are forbidden, and MOM's Smaug family is preferred when the configured HF route exposes it.
