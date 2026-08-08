# MOM Learning Model Foundation

This folder begins the implementation contract for MOM's personalized learning system.

The first milestone is not model training. It is trustworthy accumulation of user-specific knowledge.

MOM's initial learning primitive is:

`observe -> interpret -> confirm when needed -> store -> retrieve -> correct -> grow`

## Current contents
- `contracts/`: language-neutral JSON Schemas for learning objects.
- `storage/schema.sql`: local relational storage foundation.
- `pipelines/confirmation_loop.md`: lifecycle from raw event to confirmed memory.
- `state/`: reserved runtime state partitions.
- `examples/`: concrete expected behavior.
- `evaluation/`: future learning quality measurements.
- `proposed/`: behavior examples awaiting human review.
- `approved/`: behavior examples explicitly approved for model teaching or regression evaluation.

## Behavior teaching review
Generated behavior examples always enter `proposed/` first. They are not training truth merely because another model produced them.

After human review, approved examples move into `approved/`. The behavior dataset contract and SFT preparation tool live under `core_llm/learning_engine/` so the data queue is not duplicated.

Behavior examples teach emotional instinct, relationship continuity, maternal judgment, boundaries, and response scale. They are not injected into live chat as lookup material. Their destination is model training and evaluation.

## Next implementation layer
A runtime service should implement these operations without changing their semantics:
- record observation;
- create candidate;
- decide whether confirmation is required;
- resolve confirmation;
- store/supersede confirmed fact;
- retrieve relevant memories;
- mark stale knowledge;
- apply correction;
- emit an auditable learning event.
