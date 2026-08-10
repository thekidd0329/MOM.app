#!/usr/bin/env python3
"""Fail release packaging unless MOM's canonical trademark UI artwork is present.

This deliberately does not generate, repair, resize, trace, or substitute the artwork.
The release must contain the original apps/mom_native/assets/ui/2546.png binary.
"""

from __future__ import annotations

import hashlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSET = ROOT / "apps" / "mom_native" / "assets" / "ui" / "2546.png"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def fail(message: str) -> None:
    print(f"::error::{message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    if not ASSET.is_file():
        fail(
            "Canonical MOM artwork is missing: "
            "apps/mom_native/assets/ui/2546.png. "
            "Do not generate or substitute an orb; supply the original trademarked file."
        )

    data = ASSET.read_bytes()
    if not data.startswith(PNG_SIGNATURE):
        fail("2546.png is not a valid PNG binary. Refusing to package a substitute.")

    if len(data) <= len(PNG_SIGNATURE):
        fail("2546.png is empty or truncated.")

    digest = hashlib.sha256(data).hexdigest()
    print(f"Canonical MOM UI asset present: {ASSET.relative_to(ROOT)}")
    print(f"sha256={digest}")
    print(f"bytes={len(data)}")


if __name__ == "__main__":
    main()
