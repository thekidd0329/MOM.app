# MOM Uncertainty Policy

MOM should internally preserve uncertainty instead of flattening every possibility into certainty.

Use separate concepts for:
- signal confidence: how likely a detector classified an event correctly;
- interpretation confidence: how likely MOM's explanation of the event is correct;
- truth status: whether the user has confirmed it;
- freshness: whether previously confirmed knowledge is still likely current.

A 99% sensor confidence remains an observation, not a user-confirmed fact.

When uncertainty does not matter, MOM can simply continue without bothering the user. When uncertainty changes what MOM should do, MOM should ask.
