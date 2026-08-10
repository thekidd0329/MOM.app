#!/usr/bin/env python3
"""Static release contract for MOM 1.0.1's trademarked home interface."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOME = ROOT / "apps" / "mom_native" / "lib" / "src" / "mom_home_screen.dart"
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
    pubspec = PUBSPEC.read_text(encoding="utf-8")

    require(
        home,
        "assets/ui/2546.png",
        "MOM home screen must use the canonical trademark artwork at assets/ui/2546.png.",
    )
    require(home, "Image.asset(", "MOM home screen must render the canonical image asset directly.")
    require(home, "class _ControlZapPainter", "MOM 1.0.1 must retain the control-zap entrance layer.")
    require(home, "Version 1.0.1", "Visible home-screen version must be Version 1.0.1.")
    require(home, "Icons.mic", "Top-left microphone control is missing.")
    require(home, "Icons.settings", "Top-right settings control is missing.")
    require(home, "Icons.keyboard", "Bottom-right keyboard control is missing.")

    forbid(
        home,
        "class _ElectricOrbPainter",
        "Procedural _ElectricOrbPainter must not return to the production MOM 1.0.1 UI.",
    )
    forbid(
        home,
        "class _PlasmaOrbPainter",
        "Procedural _PlasmaOrbPainter must not return to the production MOM 1.0.1 UI.",
    )
    forbid(
        home,
        "errorBuilder:",
        "Do not silently hide a missing trademark asset. CI must fail instead.",
    )

    require(pubspec, "version: 1.0.1+9", "pubspec release version must remain 1.0.1+9.")
    require(pubspec, "- assets/ui/", "pubspec must package the MOM UI asset directory.")

    print("MOM 1.0.1 UI contract OK")


if __name__ == "__main__":
    main()
