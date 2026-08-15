#!/usr/bin/env python3
"""Verify MOM's Android APK and runtime manifest contract.

Usage:
    python3 tools/verify_android_apk.py <apk> <staged-jni-dir> [manifest]

The staged JNI directory is expected to contain the lib*.so files copied into
android/app/src/main/jniLibs/<abi> before the Flutter release build. The ABI is
derived from the staged directory name, so the same verifier can prove ARM64
and x86_64 contents in MOM's universal APK. MOM's required network/microphone
declarations and speech-recognition discovery query are verified before the APK
is accepted. If no manifest path is supplied, it is derived from the staged JNI
location.
"""

from __future__ import annotations

import sys
from pathlib import Path
from zipfile import BadZipFile, ZipFile

_REQUIRED_MANIFEST_DECLARATIONS = (
    "android.permission.INTERNET",
    "android.permission.RECORD_AUDIO",
    "android.speech.RecognitionService",
)

_REQUIRED_CRISP_NATIVE_LIBRARIES = (
    "libcrispasr.so",
    "libomp.so",
)


def verify_manifest(manifest: Path) -> tuple[str, ...]:
    if not manifest.is_file() or manifest.stat().st_size == 0:
        raise ValueError(f"Android manifest missing or empty: {manifest}")

    text = manifest.read_text(encoding="utf-8")
    missing = [
        declaration
        for declaration in _REQUIRED_MANIFEST_DECLARATIONS
        if declaration not in text
    ]
    if missing:
        raise ValueError(
            "Android manifest missing MOM runtime declarations: "
            + ", ".join(missing)
        )
    return _REQUIRED_MANIFEST_DECLARATIONS


def verify(apk: Path, staged_dir: Path) -> list[str]:
    if not apk.is_file() or apk.stat().st_size == 0:
        raise ValueError(f"APK missing or empty: {apk}")
    if not staged_dir.is_dir():
        raise ValueError(f"staged JNI directory missing: {staged_dir}")

    expected = sorted(path.name for path in staged_dir.glob("lib*.so"))
    if not expected:
        raise ValueError(f"no staged native libraries found in: {staged_dir}")
    missing_crisp_libraries = [
        library
        for library in _REQUIRED_CRISP_NATIVE_LIBRARIES
        if library not in expected
    ]
    if missing_crisp_libraries:
        raise ValueError(
            "staged CrispASR runtime libraries missing before APK verification: "
            + ", ".join(missing_crisp_libraries)
        )

    abi = staged_dir.name
    if abi not in {"arm64-v8a", "x86_64"}:
        raise ValueError(f"unsupported staged Android ABI: {abi}")

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
        if f"lib/{abi}/{name}" not in packaged
    ]
    if missing:
        raise ValueError(
            "APK missing staged native libraries: " + ", ".join(missing)
        )

    return expected


def main(argv: list[str]) -> int:
    if len(argv) not in (3, 4):
        print(
            "usage: verify_android_apk.py <apk> <staged-jni-dir> [manifest]",
            file=sys.stderr,
        )
        return 2

    apk = Path(argv[1]).expanduser().resolve()
    staged_dir = Path(argv[2]).expanduser().resolve()
    manifest = (
        Path(argv[3]).expanduser().resolve()
        if len(argv) == 4
        else staged_dir.parent.parent / "AndroidManifest.xml"
    )

    try:
        expected = verify(apk, staged_dir)
        declarations = verify_manifest(manifest)
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"MOM APK verification failed: {exc}", file=sys.stderr)
        return 1

    print(
        f"MOM APK verified: {apk} contains all {len(expected)} staged "
        f"{staged_dir.name} native libraries and all {len(declarations)} required "
        "manifest declarations"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
