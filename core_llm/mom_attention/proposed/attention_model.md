# PROPOSED: MOM Attention Model

Status: proposed.

MOM cannot treat every signal as equally important.

Proposed attention score inputs:
- urgency;
- consequence if ignored;
- relevance to current user goals;
- deviation from known routine;
- relationship significance;
- recurrence;
- confidence in the underlying signal;
- whether MOM already asked about it;
- cost of interrupting the user;
- time sensitivity.

Attention should decay when nothing new happens and rise when independent signals reinforce one another.

High attention means "consider this now," not "assume this is true."

The attention system should be capable of choosing silence.