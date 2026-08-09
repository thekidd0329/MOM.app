# MOM Orb Animation Spec

Status: Workload 4 implementation contract
Branch: `workload-4-beta-ui`
Source of truth: `2546.png`

## 1. Non-negotiable asset preservation

`2546.png` is the master branded orb reference. It must never be edited in place, recompressed, color-shifted, cropped, overwritten, or used as a scratch/export target.

Verified source fingerprint:

- SHA-256: `8b9a76cdee1075342a864640ac3cd68b2bb661564c5e6c5805a79916666d3bc9`
- Recovered source size: `233784` bytes
- Visual identity: violet plasma globe, dark spherical body, bright white-violet center, branching radial electricity, luminous violet rim, floor/reflection glow.

When the source is added to the Flutter package, preserve it as the immutable master at:

`apps/mom_native/assets/brand/2546.png`

All generated or edited files must use different names. Never overwrite `2546.png`.

Suggested derivative names:

- `orb_base_clean.png` - clean trademark-faithful orb body with electricity removed
- `orb_reflection.png` - optional isolated floor/reflection treatment if raster separation is needed
- procedural/vector electricity remains code-driven and must not be baked back into the master

Before accepting any source-asset change, recompute SHA-256 and confirm it still matches the fingerprint above.

## 2. Visual objective

The final MOM orb must preserve the exact visual language of `2546.png` while allowing the electricity to animate independently.

The orb should feel like the source image has become alive, not like a newly designed plasma ball.

Preserve:

- sphere proportions and silhouette
- deep purple/black internal body
- violet rim energy
- white-violet core placement and bloom
- branching style and density language
- overall luminous contrast
- floor/reflection relationship

Do not preserve baked-in lightning as the motion system. Recreate the electrical motion as an independent overlay that visually matches the source.

## 3. Render stack

Use a layered scene instead of a flattened startup image.

Back to front:

1. theme background (`black` in dark mode, `white` in light mode)
2. clean orb base derived from `2546.png`
3. orb-local glow/bloom
4. animated electricity overlay
5. center-core bloom hit
6. floor/reflection glow
7. status text
8. microphone control
9. settings control
10. version text
11. keyboard control
12. text-entry overlay when invoked

The UI controls must remain independent Flutter widgets. Do not rasterize the controls into the orb artwork.

## 4. Phase 6 - derive the clean base

Goal: produce a base orb that remains recognizably identical to `2546.png` without the baked lightning network.

Requirements:

- preserve the outer sphere edge exactly enough that the branded silhouette does not drift
- preserve the purple depth, center glow foundation, rim bloom, and dimensional shading
- remove the lightning branches without flattening the sphere into a generic gradient
- keep the original master untouched
- compare the derivative side-by-side against `2546.png` at phone size and zoomed crop size

Acceptance gate:

GREEN only when the base reads as the same MOM orb with its electricity temporarily powered off.

RED if the orb shape, purple character, center placement, rim glow, or overall identity visibly changes.

## 5. Phase 7 - electricity system

Goal: animate electricity from the outer edge of the sphere inward toward the center.

Direction:

- arcs originate around the circumference
- major branches travel inward toward the white-violet center
- secondary branches fork naturally off the major paths
- several branches may arrive at slightly different times so the motion feels electrical rather than mechanically synchronized
- the core blooms brighter as more branches converge
- after convergence, energy may relax into a low-intensity living pulse while MOM is idle/listening

Visual matching rules:

- use the same violet-to-white energy language as `2546.png`
- major trunks are brighter and thicker than secondary branches
- branch geometry should be irregular, sharp, organic and radial
- avoid concentric rings, orbital hoops, evenly spaced spokes, or smooth decorative curls
- avoid the previous procedural 'plasma toy' appearance
- no obvious repeating animation loop

Recommended rendering approach:

- keep the clean orb as a raster asset
- render electricity in Flutter `CustomPainter` or an equivalent GPU-friendly layer above it
- seed branch geometry so the overall family remains visually stable while brightness/travel/noise can animate
- use clipped drawing so electricity remains inside the sphere except for controlled rim bloom
- use blur/glow as a secondary pass, with a narrow white-hot pass on top

## 6. Electrical states

The electricity layer should support at least these visual states without coupling directly to unrelated voice code:

### boot

- sparse rim activation
- edge-to-center convergence sequence
- brightest center hit

### idle

- low-energy breathing glow
- occasional faint internal branch activity
- no distracting full-power storm

### listening

- stronger branch activity
- subtle energy movement toward the center
- status text reads `Listening...`

### thinking

- denser or slightly faster energy movement than idle
- avoid turning the orb into a spinner/loading wheel

### speaking

- reserve a modulation hook for later voice-owned integration
- Workload 4 must not alter `voice_service.dart`

## 7. Phase 8 - startup choreography

Returning-user startup sequence:

### Stage A - loading scene

- theme background appears
- branded MOM loading scene appears first
- orb is visible before home controls
- while startup work is unresolved, use subtle pulse/rotation only if it does not distort the trademark look

### Stage B - orb handoff

- orb grows from launch scale
- orb transitions into final home position
- movement should feel continuous rather than replacing one orb with another

### Stage C - energy convergence

- circumference activates
- electricity travels outside-edge -> center
- center bloom peaks
- floor/reflection receives a synchronized light pulse

### Stage D - workflow controls come online

Use the existing staged reveal idea, but the electrical language must match `2546.png`.

Recommended order:

1. microphone
2. settings
3. version
4. keyboard

Controls can receive short outward zap/reveal accents after the core convergence completes. The branded orb electricity itself remains predominantly edge-to-center.

## 8. Timing target

Treat these as initial tuning values, not hard product constants:

- 0-300 ms: background/loading lockup established
- 300-900 ms: orb visible with restrained living motion
- 900-1500 ms: orb grows/settles into home position
- 1500-2150 ms: edge-to-center electrical convergence
- 2050-2350 ms: center/floor bloom response
- 2150-2800 ms: controls reveal in sequence
- after 2800 ms: stable interactive home state

If real startup work finishes earlier, the choreography may accelerate modestly but should not hard-cut.
If startup work takes longer, hold in the restrained loading state instead of replaying the convergence sequence repeatedly.

## 9. Phase 9 - dark and light theme treatment

The orb identity remains the same in both themes.

Dark mode:

- true black background
- stronger violet atmospheric bloom is allowed
- reflection can be more visible

Light mode:

- white background
- preserve enough edge contrast that the sphere remains crisp
- reduce surrounding haze rather than changing the orb itself
- use a softer violet floor/reflection treatment

Do not recolor the master orb separately per theme unless a derivative correction is proven necessary. Prefer theme-specific compositing/glow around the same orb base.

## 10. Performance constraints

- no per-frame asset decoding
- cache raster assets
- electricity painter should repaint only when animation/state requires it
- clip glow bounds to avoid unnecessary full-screen blur work
- target smooth animation on normal Android hardware
- respect reduced-motion/accessibility settings when runtime wiring is added
- loading must never block app startup on animation completion

## 11. Ownership boundaries

Workload 4 owns:

- orb artwork integration
- home-screen composition
- startup visual choreography
- settings visual shell
- UI animation state adapters

Workload 4 does not own:

- `voice_service.dart`
- microphone/voice state-machine behavior
- brain/provider reliability
- runtime data architecture

Do not solve conflicts with another workload by deleting their behavior or globally suppressing analyzer warnings.

## 12. Tests / acceptance

Add or update UI contract tests to verify:

- source asset path is declared once in Flutter assets
- master asset is never used as an export target in code/scripts
- home renders the asset-driven orb instead of `_ElectricOrbPainter` as the final orb body
- startup entrance still reaches the interactive home state
- dark and light themes render without overflow
- version display still comes from `MomBuildInfo`
- settings/mic/keyboard controls remain reachable

Visual manual acceptance must compare against `2546.png` and the `2548.png` dark/light mockup.

## 13. Integration gate

Do not merge Workload 4 before Workloads 1/2/3 are landed in `main` and the combined branch has been tested.

Final status rules:

- GREEN: Workload 4 code and combined Flutter analyze/test/build pass, and the orb remains visually faithful to `2546.png`
- YELLOW: blocked only by unfinished/upstream workload or external dependency
- RED: Workload 4-owned visual/code/test failure

PR #15 remains unmerged until the final combined gate is GREEN.
