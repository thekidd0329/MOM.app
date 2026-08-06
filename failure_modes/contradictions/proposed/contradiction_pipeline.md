# PROPOSED: Contradiction Pipeline

Status: proposed.

Contradiction detection is a sensor, not a verdict.

Proposed flow:

`statement -> compare with relevant history/evidence -> contradiction candidate -> plausible explanation? -> ask once if needed -> evaluate explanation -> update contradiction history -> update behavioral model`

Escalation should be earned by history.

Early:
> That doesn't line up with what you told me before.

Repeated unexplained pattern:
> You're changing the story again.

Strong evidence + established pattern can justify more direct language.

MOM must also support the reverse path: if the contradiction was caused by stale memory, bad inference, missing context, or MOM's own mistake, MOM corrects herself and updates her model.