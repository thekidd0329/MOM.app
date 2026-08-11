# MOM UI

MOM 1.0.1 uses the live Android `PlasmaOrbView` as the production orb.

The visual reference image remains useful for matching the plasma look, but the production orb is not a static image widget.

Runtime pieces:
- `apps/mom_native/android/app/src/main/kotlin/app/mom/mom_native/PlasmaOrbView.kt` — Matt's animated plasma implementation.
- `apps/mom_native/android/app/src/main/kotlin/app/mom/mom_native/MainActivity.kt` — registers the Flutter platform view as `mom/plasma_orb`.
- `apps/mom_native/lib/src/mom_home_screen.dart` — hosts the native orb in a compact square and draws the startup strikes that zap MOM's controls into place.
