#!/usr/bin/env python3
"""Prevent MOM's Android release pipeline from fragmenting again."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"
UNIFIED = WORKFLOWS / "mom-native.yml"
PUBSPEC = ROOT / "apps" / "mom_native" / "pubspec.yaml"
MAIN = ROOT / "apps" / "mom_native" / "lib" / "main.dart"

OBSOLETE_AUTOMATIC_WORKFLOWS = (
    "mom-android-apk.yml",
    "mom-1.0.1-emulator-ui.yml",
    "mom-native-check.yml",
    "mom-native-tests.yml",
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def main() -> None:
    workflow = UNIFIED.read_text(encoding="utf-8")
    all_workflows = "\n".join(
        path.read_text(encoding="utf-8")
        for path in sorted(WORKFLOWS.glob("*.yml"))
    )
    pubspec = PUBSPEC.read_text(encoding="utf-8")
    main = MAIN.read_text(encoding="utf-8")

    for filename in OBSOLETE_AUTOMATIC_WORKFLOWS:
        require(not (WORKFLOWS / filename).exists(), f"obsolete build workflow still exists: {filename}")

    require(workflow.count("flutter build apk") == 1, "unified workflow must build exactly one APK")
    require("actions/upload-artifact@v4" in workflow, "APK artifact upload is missing")
    require("actions/download-artifact@v4" in workflow, "downstream jobs must consume the uploaded APK")
    require("run_mom_emulator_ui.py" in workflow, "emulator must test the uploaded APK")
    require("verify_android_apk.py" in workflow, "native APK verification is missing")
    require("release-artifact/" in workflow, "APK and manifest must upload from one flat artifact directory")
    require("android-arm64,android-x64" in workflow, "universal ARM64/x86_64 target is missing")
    require("git push origin" not in all_workflows, "a workflow still writes commits into a source branch")
    require("builds/latest_android.json" not in all_workflows, "build status must be an artifact, not a source commit")

    require("version: 1.1.0+10" in pubspec, "MOM 1.1.0 package identity is missing")
    require("assets/ui/" in pubspec, "MOM's UI assets must remain device-bundled")
    require("assets/runtime_prompt.md" not in pubspec, "server-owned prompt was re-bundled")
    require("assets/knowledge/mom_knowledge.jsonl" not in pubspec, "server-owned knowledge placeholder was re-bundled")
    require(
        "Raw conversations stay on this device." in main,
        "settings must state the raw-conversation privacy boundary",
    )
    require(
        "Keep MOM conversation history available to her cloud memory." not in main,
        "legacy raw-cloud-memory claim returned",
    )

    print("MOM 1.1.0 unified release contract OK")


if __name__ == "__main__":
    main()
