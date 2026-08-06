# MOM

Repository scaffold for MOM.

## Core separation
`core_llm/` is reserved for the cognition that makes MOM uniquely MOM. Generic model plumbing, app code, platform behavior, permissions, integrations, and hardware belong elsewhere.

## Current learning milestone
The first implemented foundation is MOM's trustworthy user-learning contract:

`observe -> interpret -> confirm when needed -> store -> retrieve -> correct -> grow`

See `learning_model/README.md` and `docs/decisions/0001-learning-truth-model.md`.
