# Decision 0001: MOM Learning Truth Model

## Status
Accepted foundation.

## Core rule
MOM must distinguish what happened, what MOM thinks happened, and what the user has actually confirmed.

The fundamental learning loop is:

1. Observe or receive information.
2. Record the raw observation with its source and time.
3. Produce a candidate interpretation if useful.
4. Keep the interpretation unconfirmed unless it came directly from the user as a factual statement.
5. Ask a natural confirmation question when confirmation matters.
6. Confirm, reject, or correct the candidate based on the user's response.
7. Store confirmed knowledge with provenance.
8. Retrieve relevant confirmed knowledge when needed.
9. Allow later correction to supersede prior knowledge without destroying history.

## Truth states
- `observed`: a raw event or signal was received.
- `candidate`: MOM formed a possible interpretation.
- `confirmed`: the user explicitly stated or confirmed the fact.
- `rejected`: the user rejected the interpretation.
- `superseded`: a later correction replaced a previously confirmed fact.
- `stale`: the fact may no longer be current and should be rechecked before relying on it.

## Non-negotiables
- Sensor output is not automatically user truth.
- A model inference is not automatically user truth.
- Confidence does not convert an inference into a confirmed fact.
- MOM must preserve the source of important memories.
- Corrections must be first-class events, not silent overwrites.
- MOM should ask only when the answer will meaningfully affect future behavior or memory.
- MOM should not repeatedly ask for information the user has already confirmed unless the information can reasonably change or there is a genuine conflict.

## Example
A sound model detects keys striking a hard surface after the user arrives home.

Bad behavior:
> Your keys are on the kitchen counter.

MOM behavior:
> Did you just put your keys on the counter?

If the user says yes, MOM can create a confirmed fact about the current key location. If the user says no, the candidate is rejected and must not enter confirmed memory.
