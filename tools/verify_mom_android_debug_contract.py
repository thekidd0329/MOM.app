#!/usr/bin/env python3
"""Keep MOM's GitHub Android pipeline fast, debug-only, ARM64-only, and artifact-only."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"
UNIFIED = WORKFLOWS / "mom-native.yml"
PUBSPEC = ROOT / "apps" / "mom_native" / "pubspec.yaml"
MAIN = ROOT / "apps" / "mom_native" / "lib" / "main.dart"
ANDROID_PREP = ROOT / "tools" / "ensure_android_manifest.py"
APK_VERIFY = ROOT / "tools" / "verify_android_apk.py"

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
    main_source = MAIN.read_text(encoding="utf-8")
    android_prep = ANDROID_PREP.read_text(encoding="utf-8")
    apk_verify = APK_VERIFY.read_text(encoding="utf-8")

    for filename in OBSOLETE_AUTOMATIC_WORKFLOWS:
        require(
            not (WORKFLOWS / filename).exists(),
            f"obsolete build workflow still exists: {filename}",
        )

    require(
        workflow.count("flutter build apk") == 1,
        "fast workflow must build exactly one APK",
    )
    require(
        "flutter build apk --debug --target-platform android-arm64" in workflow,
        "GitHub CI must build one ARM64 debug APK",
    )
    require("arm64-v8a" in workflow, "ARM64 native library staging is missing")
    require("app-debug.apk" in workflow, "debug APK output path is missing")
    require("--release" not in workflow, "GitHub CI must not build a release APK")
    require(
        "actions/upload-artifact@v4" in workflow,
        "debug APK artifact upload is missing",
    )
    require(
        "verify_android_apk.py" in workflow,
        "basic ARM64 APK verification is missing",
    )
    require(
        "libomp.so" in workflow,
        "CrispASR OpenMP runtime staging is missing",
    )
    require(
        "application-debuggable" in workflow,
        "CI must prove the packaged APK is debuggable",
    )
    require("Android Debug" in workflow, "debug signing verification is missing")
    require("apksigner" in workflow, "apksigner verification is missing")
    require("flutter analyze --no-fatal-infos" in workflow, "static analysis is missing")
    require(
        "ensure_android_manifest.py" in workflow,
        "generated Android workspace hardening is not wired into CI",
    )
    require(
        "_APPROVED_ORB_MEMBER" in apk_verify,
        "APK verification no longer checks the approved orb asset",
    )
    require(
        "packaged MOM orb artwork differs from the approved source" in apk_verify,
        "APK verification no longer proves the packaged orb bytes",
    )

    slow_or_obsolete = (
        "android-x64",
        "x86_64",
        "ReactiveCircus/android-emulator-runner",
        "run_mom_emulator_ui.py",
        "actions/download-artifact@v4",
        "/dev/kvm",
        "disable-animations: true",
        "flutter test",
        "verify_live_mom_runtime_config.py",
        "Complete onboarding and verify home/settings UI",
        "Upload emulator evidence",
    )
    for marker in slow_or_obsolete:
        require(
            marker not in workflow,
            f"slow or obsolete debug-CI step returned: {marker}",
        )

    require(
        workflow.count("runs-on: ubuntu-latest") == 1,
        "fast Android CI must stay a single runner job",
    )
    require(
        workflow.count("actions/checkout@v4") == 1,
        "fast Android CI must not duplicate checkout/setup across jobs",
    )

    forbidden_release_material = (
        "MOM_ANDROID_KEYSTORE",
        "MOM_ANDROID_CERT_SHA256",
        "Sign with the permanent MOM release key",
        "gh release create",
        "contents: write",
        "\n  publish:",
        "secrets.",
    )
    for marker in forbidden_release_material:
        require(
            marker not in workflow,
            f"GitHub Android CI still contains release/publishing material: {marker}",
        )

    require(
        "gh release create" not in all_workflows,
        "a GitHub Actions workflow still publishes a GitHub release",
    )
    require(
        "git push origin" not in all_workflows,
        "a workflow still writes commits into a source branch",
    )
    require(
        "builds/latest_android.json" not in all_workflows,
        "build status must be an artifact, not a source commit",
    )

    require(
        "GRADLE_FILENAMES = (\"build.gradle\", \"build.gradle.kts\")" in android_prep,
        "Android workspace prep must cover Groovy and Kotlin Gradle files",
    )
    require(
        'if "signingConfig" in line:' in android_prep,
        "Android workspace prep must strip release signing configuration",
    )
    require(
        "check_debug_gradle" in android_prep,
        "Android workspace prep must verify release signing stays removed",
    )
    require(
        "debugShowCheckedModeBanner: false," in android_prep
        and "debugShowCheckedModeBanner: true," in android_prep,
        "Android workspace prep must force the debug banner on",
    )
    require(
        "MOM debug console logging active" in android_prep,
        "Android workspace prep must enable console logging in the debug app",
    )
    require(
        "check_debug_main" in android_prep,
        "Android workspace prep must verify the generated debug main.dart",
    )

    require(
        "debugShowCheckedModeBanner: true," in main_source,
        "tracked main.dart must keep the Flutter debug banner visible",
    )
    require(
        "debugShowCheckedModeBanner: false," not in main_source,
        "tracked main.dart must not hide the Flutter debug banner",
    )
    require(
        "debugPrint('MOM debug console logging active');" in main_source,
        "tracked main.dart must keep debug console logging active",
    )

    require(
        "version: 1.0.1+10" in pubspec,
        "MOM 1.0.1 build 10 package identity is missing",
    )
    require("assets/ui/" in pubspec, "MOM's UI assets must remain device-bundled")
    require(
        "assets/runtime_prompt.md" not in pubspec,
        "server-owned prompt was re-bundled",
    )
    require(
        "assets/knowledge/mom_knowledge.jsonl" not in pubspec,
        "server-owned knowledge placeholder was re-bundled",
    )
    require(
        "Raw conversations stay on this device." in main_source,
        "settings must state the raw-conversation privacy boundary",
    )
    require(
        "Keep MOM conversation history available to her cloud memory."
        not in main_source,
        "legacy raw-cloud-memory claim returned",
    )

    print("MOM fast ARM64 debug-only CI contract OK")


if __name__ == "__main__":
    main()
