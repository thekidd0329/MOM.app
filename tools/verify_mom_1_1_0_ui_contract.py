#!/usr/bin/env python3
"""Static contract for MOM's state-reactive production plasma orb."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "apps" / "mom_native"
HOME = APP / "lib" / "src" / "mom_home_screen.dart"
BRIDGE = APP / "lib" / "src" / "native_plasma_orb.dart"
PLASMA = (
    APP
    / "android"
    / "app"
    / "src"
    / "main"
    / "kotlin"
    / "app"
    / "mom"
    / "mom_native"
    / "PlasmaOrbView.kt"
)
MAIN_ACTIVITY = PLASMA.with_name("MainActivity.kt")
PUBSPEC = APP / "pubspec.yaml"
LOGO = APP / "assets" / "photopea_background_remover_1786650252951.png"
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
    bridge = BRIDGE.read_text(encoding="utf-8")
    plasma = PLASMA.read_text(encoding="utf-8")
    main_activity = MAIN_ACTIVITY.read_text(encoding="utf-8")
    pubspec = PUBSPEC.read_text(encoding="utf-8")

    if not LOGO.is_file() or LOGO.stat().st_size == 0:
        fail("MOM approved production orb PNG is missing or empty.")

    require(
        home,
        "NativePlasmaOrb(",
        "MOM home must host the state-reactive plasma orb.",
    )
    require(
        home,
        ASSET_PATH,
        "The approved PNG must remain the non-Android fallback.",
    )
    require(
        home,
        "PlasmaOrbState.listening",
        "Listening state is not connected to the orb.",
    )
    require(
        home,
        "PlasmaOrbState.thinking",
        "Thinking state is not connected to the orb.",
    )
    require(
        home,
        "PlasmaOrbState.talking",
        "Talking state is not connected to the orb.",
    )
    require(
        home,
        "class _ControlZapPainter",
        "MOM must retain the startup control-zap layer.",
    )
    require(
        home,
        "Version 1.1.0",
        "Visible home-screen version must remain the current UI build label.",
    )
    require(home, "Icons.mic", "Top-left microphone control is missing.")
    require(home, "Icons.settings", "Top-right settings control is missing.")
    require(home, "Icons.keyboard", "Bottom-right keyboard control is missing.")
    require(
        home,
        "constraints.maxWidth * 0.64",
        "Orb must remain compact rather than filling the screen.",
    )

    require(bridge, "AndroidView(", "Android plasma platform view is missing.")
    require(bridge, "viewType: 'mom/plasma_orb'", "Orb view type changed.")
    require(
        bridge,
        "invokeMethod<void>('setState'",
        "Flutter must push live MOM state into the native orb.",
    )
    require(
        bridge,
        "creationParamsCodec",
        "Initial orb state must cross the platform-view boundary.",
    )

    require(
        plasma,
        f"flutter_assets/{ASSET_PATH}",
        "Native renderer must draw the approved PNG as its base layer.",
    )
    require(plasma, 'IDLE("idle"', "Idle plasma profile is missing.")
    require(
        plasma,
        'LISTENING("listening"',
        "Listening plasma profile is missing.",
    )
    require(plasma, 'THINKING("thinking"', "Thinking plasma profile is missing.")
    require(plasma, 'TALKING("talking"', "Talking plasma profile is missing.")
    require(
        plasma,
        "postInvalidateDelayed(orbState.frameDelayMs)",
        "Native plasma animation loop is missing.",
    )
    require(
        main_activity,
        '"mom/plasma_orb"',
        "Android plasma platform-view registration is missing.",
    )
    require(
        main_activity,
        "PlasmaOrbViewFactory",
        "Android plasma platform-view factory is missing.",
    )
    require(
        main_activity,
        "flutterEngine.dartExecutor.binaryMessenger",
        "Orb method-channel messenger is missing.",
    )

    require(
        pubspec,
        f"- {ASSET_PATH}",
        "Approved production orb asset must remain declared.",
    )
    require(
        pubspec,
        "version: 1.0.1+10",
        "pubspec release version must remain 1.0.1+10.",
    )

    forbid(
        home,
        "class _ElectricOrbPainter",
        "Old Flutter procedural orb must not return.",
    )
    forbid(
        home,
        "class _PlasmaOrbPainter",
        "Old Flutter plasma approximation must not return.",
    )

    print("MOM state-reactive approved-art plasma UI contract OK")


if __name__ == "__main__":
    main()
