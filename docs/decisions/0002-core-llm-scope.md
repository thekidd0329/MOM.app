# Decision 0002: `core_llm` Is MOM's Unique Brain

## Status
Accepted foundation.

`core_llm/` is the private cognition layer that defines what makes MOM different from a generic assistant.

It is not the home for generic infrastructure.

## Belongs in core_llm
- MOM's instincts;
- MOM's judgment of what matters;
- MOM's relationship model with the user;
- MOM's confirmation philosophy;
- MOM's uncertainty behavior;
- MOM's memory philosophy;
- MOM's proactive judgment;
- MOM's interruption judgment;
- MOM's adaptation style;
- MOM's values and internal behavioral principles;
- MOM-specific pattern interpretation;
- MOM's rules for acting, waiting, asking, remembering, and forgetting.

## Does not belong in core_llm
- database drivers;
- operating-system permission code;
- generic speech-to-text or text-to-speech implementations;
- UI code;
- notification delivery plumbing;
- model hosting/runtime code;
- camera, microphone, GPS, or other sensor drivers;
- generic API integrations;
- hardware drivers.

Those systems may provide signals to MOM's core, but they are not the core itself.
