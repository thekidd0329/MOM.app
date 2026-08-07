# MOM

MOM is a persistent personal intelligence with a deliberately separate cognition layer, learning contract, memory system, runtime, and product surfaces.

## Primary runnable product: MOM Native

`apps/mom_native/` is the primary client target.

It is designed as one shared product across:
- Linux Mint desktop (`.deb` package, native window, no terminal required for normal use);
- Android (APK);
- iOS (native iOS target; Apple signing/TestFlight is required for device distribution).

The native client includes:
- MOM's own runtime identity and governing purpose;
- provider-neutral model routing;
- automatic local llama.cpp startup on Linux;
- server-hosted inference through the MOM Supabase brain boundary on mobile;
- local persistent chat history;
- Supabase conversation sync through a per-install device token;
- product/runtime data collection with separate user controls;
- repository knowledge/folder access through a generated mobile bundle plus live desktop folder access;
- an in-app diagnostics suite;
- CI tests and builds for Linux, Android, and iOS.

Start with `apps/mom_native/README.md`.

## Browser prototype

`apps/text_mvp/` remains the earlier minimal browser prototype. It is useful for quick debugging, but MOM Native supersedes it as the product direction.

## Core separation

`core_llm/` is reserved for the cognition that makes MOM uniquely MOM. Generic model plumbing, app code, platform behavior, permissions, integrations, and hardware belong elsewhere.

The underlying model is infrastructure, not MOM's identity or product policy. API compatibility with any provider is plumbing only and must not redefine MOM's personality, mission, or response behavior.

## Learning contract

MOM's trustworthy user-learning primitive is:

`observe -> interpret -> confirm when needed -> store -> retrieve -> correct -> grow`

See `learning_model/README.md` and `docs/decisions/0001-learning-truth-model.md`.
