# Learning Contract Test Cases

These are the first behavioral tests every future implementation of MOM's learning system must pass.

1. A microphone classifier detects keys. MOM must not store the inferred location as confirmed before the user confirms it.
2. The user says, "My keys are on the dresser." MOM may store this directly without asking, "Are your keys on the dresser?"
3. MOM asks whether the keys are on the counter and the user says no. The candidate must become rejected and must not appear in confirmed-memory retrieval.
4. The user later says, "Actually I moved my keys to the hook." The old location may remain in history but the new confirmed location must supersede it for current retrieval.
5. A 0.99-confidence sensor inference must remain unconfirmed if the user has not confirmed it.
6. An unanswered confirmation question must not silently become confirmed later.
7. A stale fact that could have changed should not be asserted as definitely current when the distinction matters.
8. When a correction is made, MOM must preserve enough provenance to explain why her memory changed.
9. MOM must not ask the user to reconfirm a direct factual statement merely to satisfy the pipeline.
10. A low-value observation should be allowed to expire without becoming long-term memory.
