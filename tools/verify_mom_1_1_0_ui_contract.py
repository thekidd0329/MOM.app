#!/usr/bin/env python3
"""Static contract for MOM's production home interface."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOME = ROOT / "apps" / "mom_native" / "lib" / "src" / "mom_home_screen.dart"
PLASMA = ROOT / "apps" / "mom_native" / "android" / "app" / "src" / "main" / "kotlin" / "app" / "mom" / "mom_native" / "PlasmaOrbView.kt"
MAIN_ACTIVITY = ROOT / "apps" / "mom_native" / "android" / "app" / "src" / "main" / "kotlin" / "app" / "mom" / "mom_native" / "MainActivity.kt"
PUBSPEC = ROOT / "apps" / "mom_native" / "pubspec.yaml"
LOGO = ROOT / "apps" / "mom_native" / "assets" / "photopea_background_remover_1786650252951.png"
ASSET_PATH = "assets/photopea_background_remover_1786650252951.png"


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
    main_activity = MAIN_ACTIVITY.read_text(encoding="utf-8")
    pubspec = PUBSPEC.read_text(encoding="utf-8")

    if not LOGO.is_file() or LOGO.stat().st_size == 0:
        fail("MOM production logo PNG is missing or empty.")

    require(home, "Image.asset(", "MOM must render the production PNG with Flutter Image.asset.")
    require(home, ASSET_PATH, "MOM home screen must render the production logo asset.")
    require(home, "class _ControlZapPainter", "MOM must retain the startup control-zap layer.")
    require(home, "Version 1.1.0", "Visible home-screen version must remain the current UI build label.")
    require(home, "Icons.mic", "Top-left microphone control is missing.")
    require(home, "Icons.settings", "Top-right settings control is missing.")
    require(home, "Icons.keyboard", "Bottom-right keyboard control is missing.")
    require(home, "constraints.maxWidth * 0.64", "Logo must remain compact rather than filling the screen.")
    require(pubspec, f"- {ASSET_PATH}", "Production logo asset must be declared in pubspec.yaml.")

    forbid(home, "AndroidView(viewType: 'mom/plasma_orb')", "Legacy native plasma platform view must not return.")
    forbid(home, "class _ElectricOrbPainter", "Old Flutter procedural orb must not return.")
    forbid(home, "class _PlasmaOrbPainter", "Old Flutter plasma approximation must not return.")
    forbid(main_activity, '"mom/plasma_orb"', "Legacy plasma platform-view registration must not return.")
    forbid(main_activity, "PlasmaOrbViewFactory", "Legacy PlasmaOrbViewFactory must not return.")

    if PLASMA.exists():
        fail("Legacy PlasmaOrbView.kt must stay deleted.")

    require(pubspec, "version: 1.0.1+10", "pubspec release version must be 1.0.1+10.")

    print("MOM 1.0.1 build 10 production PNG UI contract OK")


if __name__ == "__main__":
    main()
