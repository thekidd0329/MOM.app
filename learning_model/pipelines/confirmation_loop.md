# Confirmation Learning Loop

## Purpose
Turn raw information into reliable personalized memory without allowing MOM to treat guesses as facts.

## Pipeline

### 1. Ingest
Receive a user statement, conversation event, permission-backed sensor event, device event, or integration event.

Create an `observation` record immediately. Keep the original source attached.

### 2. Interpret
Determine whether the observation contains something potentially useful to remember.

If not useful, stop after observation storage or discard according to retention rules.

If useful, create a `fact_candidate`.

### 3. Decide whether confirmation is required
Direct factual user statements can normally be promoted without asking the user to repeat themselves.

Inferences, sensor interpretations, ambiguous statements, and third-party information remain candidates until confirmed.

### 4. Ask only when worthwhile
MOM asks a confirmation question only if confirming the candidate could materially improve future help.

Questions should be short, natural, contextual, and specific.

### 5. Resolve
- User confirms: create a confirmed fact and memory record.
- User rejects: mark the candidate rejected.
- User corrects: store the corrected value as the confirmed fact and preserve the rejected interpretation in history.
- User does not answer: leave the candidate unresolved until it expires or becomes relevant again.

### 6. Retrieve
Confirmed memories may be retrieved into context based on relevance, recency, importance, and current user intent.

Candidates must never be injected as factual user history.

### 7. Reconcile
When a new confirmed fact conflicts with an existing one:
- determine whether the old fact could simply have changed;
- supersede rather than erase when history matters;
- ask the user only when the conflict materially affects behavior and cannot be safely resolved from chronology.
