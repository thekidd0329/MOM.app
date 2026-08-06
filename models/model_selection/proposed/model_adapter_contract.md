# PROPOSED: Model Adapter Contract

Status: proposed.

MOM should not be welded to one LLM.

The MOM runtime talks to a common model adapter. Adapters may target:
- a small local GGUF model for development/testing;
- a local Transformers model;
- Hugging Face hosted inference;
- another remote inference provider;
- a future MOM-specific model.

The adapter is responsible for translating MOM's normalized request into the provider/runtime format and translating responses back.

MOM memory, personality, learning, user model, and relationship logic must live above the adapter so swapping the base model does not erase MOM.