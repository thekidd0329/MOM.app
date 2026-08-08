# MOM Learning Engine

This folder contains the behavior-dataset contract and preparation tooling for future MOM fine-tuning.

The actual review queue already lives in `learning_model/`:

- `learning_model/proposed/` = generated or drafted examples awaiting human review.
- `learning_model/approved/` = examples a human has explicitly approved for MOM to learn from.

Do not create a second dataset queue here.

MOM is taught with examples of how a mother reacts, not encyclopedic question/answer pairs. Training data should teach emotional instinct, relationship continuity, judgment, boundaries, and response scale.

## Canonical sample format

Each JSONL line needs only two required fields:

- `user_message`
- `ideal_response`

Recommended optional fields:

- `topic`: short category such as `drugs`, `grief`, `sex`, `relationships`, `anger`, `self_harm`, `money`, `school`
- `context`: earlier turns as an array of `{ "role": "user" | "assistant", "content": "..." }`
- `known_context`: facts MOM is allowed to remember for this example
- `emotion`: feelings driving MOM's response
- `maternal_intent`: what MOM is trying to do emotionally
- `bad_response`: a response that demonstrates the failure mode
- `failure_reason`: why the bad response is wrong
- `tags`: free-form behavior labels

Do not include hidden chain-of-thought. `emotion` and `maternal_intent` are labels, not private reasoning transcripts.

## Teaching workflow

1. Put raw generated examples in `learning_model/proposed/`.
2. Human-review them. Generated examples are suggestions, not truth.
3. Move only approved rows into `learning_model/approved/`.
4. Run `prepare_sft.py` against an approved JSONL file.
5. Fix every rejected row.
6. Spot-check the normalized output for MOM voice, emotional instinct, factual consistency, and unwanted assistant behavior.
7. Use the resulting `messages` JSONL for supervised fine-tuning or LoRA/QLoRA when the target base model is selected.

Never connect these behavior examples directly to the live runtime as retrieval/RAG. The point is to teach model weights, not make MOM search a response library while talking.

## Core behavior rule

A strong example answers: **what would MOM feel and say?**

A weak example answers: **what information could an AI provide?**

The first teaches MOM. The second teaches an assistant.
