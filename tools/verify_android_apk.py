#!/usr/bin/env python3
"""Verify MOM's Android APK contains the staged arm64 native speech libraries.

Usage:
    python3 tools/verify_android_apk.py <apk> <staged-jni-dir>

The staged JNI directory is expected to contain the lib*.so files copied into
android/app/src/main/jniLibs/arm64-v8a before the Flutter release build.
"""

from __future__ import annotations

import sys
from pathlib import Path
from zipfile import BadZipFile, ZipFile


def verify(apk: Path, staged_dir: Path) -> list[str]:
    if not apk.is_file() or apk.stat().st_size == 0:
        raise ValueError(f"APK missing or empty: {apk}")
    if not staged_dir.is_dir():
        raise ValueError(f"staged JNI directory missing: {staged_dir}")

    expected = sorted(path.name for path in staged_dir.glob("lib*.so"))
    if not expected:
        raise ValueError(f"no staged native libraries found in: {staged_dir}")
    if "libcrispasr.so" not in expected:
        raise ValueError("staged CrispASR library missing before APK verification")

    try:
        with ZipFile(apk) as archive:
            packaged = set(archive.namelist())
            bad_member = archive.testzip()
    except BadZipFile as exc:
        raise ValueError(f"invalid APK zip: {apk}") from exc

    if bad_member is not None:
        raise ValueError(f"APK contains a corrupt member: {bad_member}")

    missing = [
        name
        for name in expected
        if f"lib/arm64-v8a/{name}" not in packaged
    ]
    if missing:
        raise ValueError(
            "APK missing staged native libraries: " + ", ".join(missing)
        )

    return expected


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(
            "usage: verify_android_apk.py <apk> <staged-jni-dir>",
            file=sys.stderr,
        )
        return 2

    apk = Path(argv[1]).expanduser().resolve()
    staged_dir = Path(argv[2]).expanduser().resolve()

    try:
        expected = verify(apk, staged_dir)
    except ValueError as exc:
        print(f"MOM APK verification failed: {exc}", file=sys.stderr)
        return 1

    print(
        f"MOM APK verified: {apk} contains all {len(expected)} staged "
        "arm64 native libraries"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
