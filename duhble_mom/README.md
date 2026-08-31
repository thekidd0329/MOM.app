# MOM on DUHBLE

This tree is a clean-room rewrite of MOM around DUHBLE-native boundaries.

The legacy repository remains reference material only. Nothing in this tree depends on the old placeholder-folder taxonomy, duplicated app prototypes, or legacy runtime ownership.

## Rules

- DUHBLE architecture is the substrate. MOM is the product built on it.
- Do not modify the frozen `double.duh` source from this tree.
- No shadow knowledge store may become authoritative beside the mounted DUHBLE state.
- Time advances only through explicit DUHBLE moments.
- Provenance, impulse force, inhibition, readiness, and activation requests remain first-class.
- Product concerns such as UI, transport, device I/O, permissions, and packaging stay outside the mounted knowledge state.
- This rewrite does not copy the legacy Flutter orchestration structure. Legacy code is behavioral reference only.

## Clean tree

```text
duhble_mom/
  README.md
  mom.duh
  identity/
    purpose.duh
    voice.duh
  interaction/
    conversation.duh
    input.duh
    output.duh
  memory/
    learning.duh
    recall.duh
  behavior/
    attention.duh
    support.duh
  device/
    permissions.duh
    signals.duh
  transport/
    inference.duh
    sync.duh
  tests/
    smoke.duh
```

The first pass establishes ownership and contracts. Later passes port behavior one subsystem at a time and delete every dependency on the legacy orchestration tree before this branch is considered mergeable.
