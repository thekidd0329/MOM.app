#!/usr/bin/env python3
"""Static release contract for MOM 1.1.0's canonical animated plasma interface."""

from __future__ import annotations

import base64
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOME = ROOT / "apps" / "mom_native" / "lib" / "src" / "mom_home_screen.dart"
PLASMA = ROOT / "apps" / "mom_native" / "android" / "app" / "src" / "main" / "kotlin" / "app" / "mom" / "mom_native" / "PlasmaOrbView.kt"
MAIN_ACTIVITY = ROOT / "apps" / "mom_native" / "android" / "app" / "src" / "main" / "kotlin" / "app" / "mom" / "mom_native" / "MainActivity.kt"
PUBSPEC = ROOT / "apps" / "mom_native" / "pubspec.yaml"
CANONICAL_2615 = ROOT / "apps" / "mom_native" / "assets" / "ui" / "2615.b64.txt"


def fail(message: str) -> None:
    print(f"::error::{message}", file=sys.stderr)
    raise SystemExit(1)


def require(text: str, needle: str, message: str) -> None:
    if needle not in text:
        fail(message)


def forbid(text: str, needle: str, message: str) -> None:
    if needle in text:
        fail(message)


def verify_canonical_2615() -> None:
    if not CANONICAL_2615.is_file():
        fail("Canonical 2615 orb source is missing.")

    encoded = CANONICAL_2615.read_text(encoding="utf-8").strip()
    try:
        decoded = base64.b64decode(encoded, validate=True)
    except Exception as exc:
        fail(f"Canonical 2615 orb source is not valid base64: {exc}")

    if len(decoded) < 100_000:
        fail("Canonical 2615 orb source is unexpectedly small or truncated.")
    if not decoded.startswith(b"\xff\xd8\xff"):
        fail("Canonical 2615 orb source does not decode to the staged JPEG artwork.")


def main() -> None:
    home = HOME.read_text(encoding="utf-8")
    plasma = PLASMA.read_text(encoding="utf-8")
    main_activity = MAIN_ACTIVITY.read_text(encoding="utf-8")
    pubspec = PUBSPEC.read_text(encoding="utf-8")

    verify_canonical_2615()

    require(home, "AndroidView(viewType: 'mom/plasma_orb')", "MOM must host the native animated orb on Android.")
    require(home, "class _ControlZapPainter", "MOM must retain the startup control-zap layer.")
    require(home, "Version 1.1.0", "Visible home-screen version must be Version 1.1.0.")
    require(home, "Icons.mic", "Top-left microphone control is missing.")
    require(home, "Icons.settings", "Top-right settings control is missing.")
    require(home, "Icons.keyboard", "Bottom-right keyboard control is missing.")
    require(home, "constraints.maxWidth * 0.64", "Orb must remain compact rather than filling the screen.")

    require(plasma, "class PlasmaOrbView", "Native PlasmaOrbView is missing.")
    require(plasma, "CANONICAL_2615_ASSET", "PlasmaOrbView must load the canonical 2615 source.")
    require(plasma, "2615.b64.txt", "PlasmaOrbView must point at the canonical packaged source.")
    require(plasma, "canvas.drawBitmap(artwork", "Canonical 2615 must be drawn before the live plasma layer.")
    require(plasma, "canonicalArtwork ?: return", "Missing canonical artwork must fail closed instead of drawing a replacement orb.")
    require(plasma, "postInvalidateOnAnimation()", "Matt's plasma layer must animate continuously.")
    require(plasma, "BlurMaskFilter(15f", "Purple plasma glow is missing.")
    require(plasma, "val numberOfBranches = 8", "Matt's eight moving primary branches are missing.")
    require(plasma, "val edgeArcsCount = 4", "Matt's moving edge arcs are missing.")

    require(main_activity, '"mom/plasma_orb"', "Android platform-view registration is missing.")
    require(main_activity, "PlasmaOrbViewFactory", "Android plasma platform-view factory is missing.")

    forbid(home, "assets/ui/2546.png", "2546 must not replace canonical 2615 in production.")
    forbid(home, "Image.asset(", "Home must not bypass the native canonical-plus-animation orb view.")
    forbid(home, "class _ElectricOrbPainter", "Old Flutter procedural orb must not return.")
    forbid(home, "class _PlasmaOrbPainter", "Old Flutter plasma approximation must not return.")

    require(pubspec, "version: 1.1.0+10", "pubspec release version must be Version 1.1.0+10.")
    require(pubspec, "- assets/ui/", "pubspec must bundle the canonical UI asset directory.")

    print("MOM 1.1.0 canonical 2615 + Matt plasma UI contract OK")


if __name__ == "__main__":
    main()
