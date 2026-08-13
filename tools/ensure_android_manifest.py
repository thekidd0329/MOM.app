#!/usr/bin/env python3
"""Ensure MOM's generated Android workspace stays debug-safe."""

from __future__ import annotations

import re
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
GRADLE_FILENAMES = ("build.gradle", "build.gradle.kts")
RELEASE_BLOCK_START = re.compile(
    r"^\s*(?:release|getByName\(\s*[\"']release[\"']\s*\))\s*\{"
)
DEBUG_LOG_LINE = "debugPrint('MOM debug console logging active');"

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


def ensure_manifest(path: Path) -> None:
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


def check_manifest(path: Path) -> None:
    tree = _load(path)
    missing = missing_declarations(tree.getroot())
    if missing:
        raise ValueError(
            "Android manifest missing MOM runtime declarations: "
            + ", ".join(missing)
        )


def _gradle_files_for_manifest(manifest: Path) -> list[Path]:
    app_dir = manifest.parents[2]
    return [app_dir / name for name in GRADLE_FILENAMES if (app_dir / name).is_file()]


def _rewrite_release_block(text: str) -> tuple[str, int]:
    lines = text.splitlines(keepends=True)
    output: list[str] = []
    in_release = False
    depth = 0
    removed = 0
    for line in lines:
        if not in_release and RELEASE_BLOCK_START.search(line):
            in_release = True
            depth = line.count("{") - line.count("}")
            output.append(line)
            if depth <= 0:
                in_release = False
            continue
        if in_release:
            if "signingConfig" in line:
                removed += 1
            else:
                output.append(line)
            depth += line.count("{") - line.count("}")
            if depth <= 0:
                in_release = False
            continue
        output.append(line)
    return "".join(output), removed


def _release_signing_lines(text: str) -> list[str]:
    lines = text.splitlines()
    found: list[str] = []
    in_release = False
    depth = 0
    for line in lines:
        if not in_release and RELEASE_BLOCK_START.search(line):
            in_release = True
            depth = line.count("{") - line.count("}")
            if depth <= 0:
                in_release = False
            continue
        if in_release:
            if "signingConfig" in line:
                found.append(line.strip())
            depth += line.count("{") - line.count("}")
            if depth <= 0:
                in_release = False
    return found


def ensure_debug_gradle(manifest: Path) -> int:
    removed_total = 0
    for gradle in _gradle_files_for_manifest(manifest):
        original = gradle.read_text(encoding="utf-8")
        updated, removed = _rewrite_release_block(original)
        if updated != original:
            gradle.write_text(updated, encoding="utf-8")
        removed_total += removed
    return removed_total


def check_debug_gradle(manifest: Path) -> None:
    for gradle in _gradle_files_for_manifest(manifest):
        signing = _release_signing_lines(gradle.read_text(encoding="utf-8"))
        if signing:
            raise ValueError(
                f"release signing configuration remains in {gradle}: "
                + ", ".join(signing)
            )


def _generated_main_for_manifest(manifest: Path) -> Path:
    build_root = manifest.parents[4]
    return build_root / "lib" / "main.dart"


def ensure_debug_main(manifest: Path) -> None:
    main = _generated_main_for_manifest(manifest)
    if not main.is_file():
        raise ValueError(f"generated Flutter main.dart is missing: {main}")
    text = main.read_text(encoding="utf-8")
    text = text.replace(
        "debugShowCheckedModeBanner: false,",
        "debugShowCheckedModeBanner: true,",
    )
    if DEBUG_LOG_LINE not in text:
        anchor = "  WidgetsFlutterBinding.ensureInitialized();\n"
        if anchor not in text:
            raise ValueError("could not find Flutter startup anchor for debug logging")
        text = text.replace(anchor, anchor + f"  {DEBUG_LOG_LINE}\n", 1)
    main.write_text(text, encoding="utf-8")


def check_debug_main(manifest: Path) -> None:
    main = _generated_main_for_manifest(manifest)
    text = main.read_text(encoding="utf-8")
    if "debugShowCheckedModeBanner: false" in text:
        raise ValueError("generated main.dart still hides the debug banner")
    if "debugShowCheckedModeBanner: true" not in text:
        raise ValueError("generated main.dart does not explicitly show the debug banner")
    if DEBUG_LOG_LINE not in text:
        raise ValueError("generated main.dart does not enable debug console logging")


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
            check_manifest(path)
            check_debug_gradle(path)
            check_debug_main(path)
            print(f"Android debug workspace verified: {path}")
        else:
            ensure_manifest(path)
            removed = ensure_debug_gradle(path)
            ensure_debug_main(path)
            check_manifest(path)
            check_debug_gradle(path)
            check_debug_main(path)
            print(
                f"Android debug workspace ensured and verified: {path}; "
                f"removed {removed} release signing configuration line(s)"
            )
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"MOM Android workspace update failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
