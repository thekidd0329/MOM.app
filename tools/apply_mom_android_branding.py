#!/usr/bin/env python3
"""Apply MOM launcher branding to a generated Flutter Android scaffold."""

from __future__ import annotations

import base64
from pathlib import Path
import shutil
import sys


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: apply_mom_android_branding.py <android-project-root>", file=sys.stderr)
        return 2

    project = Path(sys.argv[1]).resolve()
    encoded = Path(__file__).resolve().parents[1] / "apps" / "mom_native" / "assets" / "mom_launcher_icon.png.b64"
    if not encoded.is_file():
        print(f"launcher asset missing: {encoded}", file=sys.stderr)
        return 1

    png = base64.b64decode(encoded.read_text(encoding="ascii"))
    res = project / "android" / "app" / "src" / "main" / "res"
    if not res.is_dir():
        print(f"android resources missing: {res}", file=sys.stderr)
        return 1

    targets = [
        res / "mipmap-mdpi" / "ic_launcher.png",
        res / "mipmap-hdpi" / "ic_launcher.png",
        res / "mipmap-xhdpi" / "ic_launcher.png",
        res / "mipmap-xxhdpi" / "ic_launcher.png",
        res / "mipmap-xxxhdpi" / "ic_launcher.png",
    ]
    for target in targets:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(png)

    print(f"Applied MOM launcher icon to {len(targets)} Android densities.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
