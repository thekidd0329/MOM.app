#!/usr/bin/env python3
"""Static release contract for MOM's live plasma home interface."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOME = ROOT / "apps" / "mom_native" / "lib" / "src" / "mom_home_screen.dart"
PLASMA = ROOT / "apps" / "mom_native" / "android" / "app" / "src" / "main" / "kotlin" / "app" / "mom" / "mom_native" / "PlasmaOrbView.kt"
MAIN_ACTIVITY = ROOT / "apps" / "mom_native" / "android" / "app" / "src" / "main" / "kotlin" / "app" / "mom" / "mom_native" / "MainActivity.kt"
PUBSPEC = ROOT / "apps" / "mom_native" / "pubspec.yaml"


def fail(message: str) -> None:
    print(f"::error::{message}", file=sys.stderr)
    raise SystemExit(1)


def require(text: str, needle: str, message: str) -> None:
    if needle not in text:
        fail(message)


def forbid(text: str, needle: str, message: str) -> None:
    if needle in text:
        fail(message)


def main() -> None:
    home = HOME.read_text(encoding="utf-8")
    plasma = PLASMA.read_text(encoding="utf-8")
    main_activity = MAIN_ACTIVITY.read_text(encoding="utf-8")
    pubspec = PUBSPEC.read_text(encoding="utf-8")

    require(home, "AndroidView(viewType: 'mom/plasma_orb')", "MOM must host the live native plasma orb on Android.")
    require(home, "class _ControlZapPainter", "MOM must retain the startup control-zap layer.")
    require(home, "Version 1.1.0", "Visible home-screen version must remain the current UI build label.")
    require(home, "Icons.mic", "Top-left microphone control is missing.")
    require(home, "Icons.settings", "Top-right settings control is missing.")
    require(home, "Icons.keyboard", "Bottom-right keyboard control is missing.")
    require(home, "constraints.maxWidth * 0.64", "Orb must remain compact rather than filling the screen.")

    require(plasma, "class PlasmaOrbView", "Native PlasmaOrbView is missing.")
    require(plasma, "postInvalidateOnAnimation()", "Native plasma orb must animate continuously.")
    require(plasma, "BlurMaskFilter(15f", "Purple plasma glow is missing.")
    require(plasma, "val numberOfBranches = 8", "Eight primary plasma branches are missing.")
    require(plasma, "val edgeArcsCount = 4", "Moving edge arcs are missing.")

    require(main_activity, '"mom/plasma_orb"', "Android platform-view registration is missing.")
    require(main_activity, "PlasmaOrbViewFactory", "Android plasma platform-view factory is missing.")

    forbid(home, "assets/ui/2546.png", "Static 2546 artwork must not replace the live production orb.")
    forbid(home, "Image.asset(", "Production orb must be live, not a static image widget.")
    forbid(home, "class _ElectricOrbPainter", "Old Flutter procedural orb must not return.")
    forbid(home, "class _PlasmaOrbPainter", "Old Flutter plasma approximation must not return.")

    require(pubspec, "version: 1.0.1+10", "pubspec release version must be 1.0.1+10.")

    print("MOM 1.0.1 build 10 live plasma UI contract OK")


if __name__ == "__main__":
    main()
