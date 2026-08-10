#!/usr/bin/env python3
"""Ensure MOM's generated AndroidManifest.xml has required runtime declarations.

Usage:
    python3 tools/ensure_android_manifest.py <manifest>
    python3 tools/ensure_android_manifest.py --check <manifest>
"""

from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID_NS = "http://schemas.android.com/apk/res/android"
ANDROID_NAME = f"{{{ANDROID_NS}}}name"
REQUIRED_PERMISSIONS = (
    "android.permission.INTERNET",
    "android.permission.RECORD_AUDIO",
)
RECOGNITION_SERVICE = "android.speech.RecognitionService"

ET.register_namespace("android", ANDROID_NS)


def _load(path: Path) -> ET.ElementTree:
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError(f"Android manifest missing or empty: {path}")
    try:
        return ET.parse(path)
    except ET.ParseError as exc:
        raise ValueError(f"invalid Android manifest XML: {path}: {exc}") from exc


def _has_recognition_query(root: ET.Element) -> bool:
    return any(
        action.attrib.get(ANDROID_NAME) == RECOGNITION_SERVICE
        for queries in root.findall("queries")
        for intent in queries.findall("intent")
        for action in intent.findall("action")
    )


def missing_declarations(root: ET.Element) -> list[str]:
    permissions = {
        element.attrib.get(ANDROID_NAME)
        for element in root.findall("uses-permission")
    }
    missing = [name for name in REQUIRED_PERMISSIONS if name not in permissions]
    if not _has_recognition_query(root):
        missing.append(RECOGNITION_SERVICE)
    return missing


def ensure(path: Path) -> None:
    tree = _load(path)
    root = tree.getroot()

    permissions = {
        element.attrib.get(ANDROID_NAME)
        for element in root.findall("uses-permission")
    }
    for name in REQUIRED_PERMISSIONS:
        if name not in permissions:
            ET.SubElement(root, "uses-permission", {ANDROID_NAME: name})

    if not _has_recognition_query(root):
        queries = root.find("queries")
        if queries is None:
            queries = ET.SubElement(root, "queries")
        intent = ET.SubElement(queries, "intent")
        ET.SubElement(intent, "action", {ANDROID_NAME: RECOGNITION_SERVICE})

    tree.write(path, encoding="utf-8", xml_declaration=True)


def check(path: Path) -> None:
    tree = _load(path)
    missing = missing_declarations(tree.getroot())
    if missing:
        raise ValueError(
            "Android manifest missing MOM runtime declarations: "
            + ", ".join(missing)
        )


def main(argv: list[str]) -> int:
    check_only = len(argv) == 3 and argv[1] == "--check"
    if not check_only and len(argv) != 2:
        print(
            "usage: ensure_android_manifest.py [--check] <manifest>",
            file=sys.stderr,
        )
        return 2

    path = Path(argv[-1]).expanduser().resolve()
    try:
        if check_only:
            check(path)
            print(f"Android manifest verified: {path}")
        else:
            ensure(path)
            check(path)
            print(f"Android manifest ensured and verified: {path}")
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"MOM Android manifest update failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
