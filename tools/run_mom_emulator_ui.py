#!/usr/bin/env python3
"""Drive MOM's real APK through onboarding and verify the live home UI."""

from __future__ import annotations

import os
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

PACKAGE = "app.mom.mom_native"
ACTIVITY = f"{PACKAGE}/.MainActivity"
BOUNDS = re.compile(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]")


def run(args: list[str], *, check: bool = True, text: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(args, check=check, capture_output=True, text=text)


def adb(*args: str, check: bool = True, text: bool = True) -> subprocess.CompletedProcess:
    return run(["adb", *args], check=check, text=text)


def wait_for_android(timeout: float = 120) -> None:
    adb("wait-for-device")
    deadline = time.monotonic() + timeout
    last_state = ""
    while time.monotonic() < deadline:
        boot = adb("shell", "getprop", "sys.boot_completed", check=False)
        package_manager = adb("shell", "pm", "path", "android", check=False)
        temp_storage = adb(
            "shell",
            "sh",
            "-c",
            "touch /data/local/tmp/mom-ready && rm /data/local/tmp/mom-ready",
            check=False,
        )
        last_state = (
            f"boot={boot.stdout.strip()!r}, "
            f"package_manager={package_manager.returncode}, "
            f"temp_storage={temp_storage.returncode}"
        )
        if (
            boot.stdout.strip() == "1"
            and package_manager.returncode == 0
            and temp_storage.returncode == 0
        ):
            return
        time.sleep(2)
    raise RuntimeError(f"Android never became test-ready: {last_state}")


def dump_ui(evidence: Path, name: str) -> ET.Element:
    remote = "/data/local/tmp/mom-window.xml"
    adb("shell", "rm", "-f", remote, check=False)
    adb("shell", "uiautomator", "dump", remote, check=False)
    result = adb("exec-out", "cat", remote, check=False)
    if result.returncode != 0 or not result.stdout.strip():
        raise RuntimeError("Android UI hierarchy was empty")
    path = evidence / name
    path.write_text(result.stdout, encoding="utf-8")
    return ET.fromstring(result.stdout)


def label(node: ET.Element) -> str:
    return " ".join(
        (
            node.attrib.get("text", ""),
            node.attrib.get("content-desc", ""),
            node.attrib.get("hint", ""),
        )
    ).strip()


def find_node(root: ET.Element, needle: str, *, class_suffix: str | None = None) -> ET.Element | None:
    wanted = needle.casefold()
    for node in root.iter("node"):
        if class_suffix and not node.attrib.get("class", "").endswith(class_suffix):
            continue
        if wanted in label(node).casefold():
            return node
    return None


def find_class(root: ET.Element, class_suffix: str) -> ET.Element | None:
    for node in root.iter("node"):
        if node.attrib.get("class", "").endswith(class_suffix):
            return node
    return None


def wait_for_node(
    evidence: Path,
    needle: str,
    *,
    timeout: float = 45,
    class_suffix: str | None = None,
) -> ET.Element:
    deadline = time.monotonic() + timeout
    last_labels = ""
    while time.monotonic() < deadline:
        try:
            root = dump_ui(evidence, "mom-current.xml")
            node = find_node(root, needle, class_suffix=class_suffix)
            if node is not None:
                return node
            last_labels = " | ".join(filter(None, (label(item) for item in root.iter("node"))))
        except (ET.ParseError, RuntimeError):
            pass
        time.sleep(1)
    raise RuntimeError(f"Timed out waiting for UI label {needle!r}. Last UI: {last_labels[-1200:]}")


def center(node: ET.Element) -> tuple[int, int]:
    match = BOUNDS.fullmatch(node.attrib.get("bounds", ""))
    if match is None:
        raise RuntimeError(f"UI node has no usable bounds: {node.attrib}")
    x1, y1, x2, y2 = map(int, match.groups())
    return (x1 + x2) // 2, (y1 + y2) // 2


def tap_node(node: ET.Element) -> None:
    x, y = center(node)
    adb("shell", "input", "tap", str(x), str(y))


def tap_text(evidence: Path, needle: str, *, timeout: float = 45) -> None:
    tap_node(wait_for_node(evidence, needle, timeout=timeout))
    time.sleep(0.8)


def screenshot(evidence: Path, name: str) -> None:
    result = adb("exec-out", "screencap", "-p", text=False)
    if result.returncode != 0 or not result.stdout:
        raise RuntimeError(f"Failed to capture {name}")
    (evidence / name).write_bytes(result.stdout)


def home_is_visible(evidence: Path) -> bool:
    try:
        root = dump_ui(evidence, "mom-current.xml")
    except (ET.ParseError, RuntimeError):
        return False
    labels = " ".join(label(node) for node in root.iter("node")).casefold()
    return all(value in labels for value in ("settings", "text mom", "version 1.1.0"))


def complete_onboarding(evidence: Path) -> None:
    tap_text(evidence, "Swearing is fine")
    tap_text(evidence, "somewhere safe")
    tap_text(evidence, "Skip intro")
    tap_text(evidence, "A balance of both")

    deadline = time.monotonic() + 30
    editor: ET.Element | None = None
    while time.monotonic() < deadline and editor is None:
        root = dump_ui(evidence, "mom-current.xml")
        editor = find_class(root, "EditText")
        if editor is None:
            time.sleep(1)
    if editor is None:
        raise RuntimeError("Name field did not appear")
    tap_node(editor)
    adb("shell", "input", "text", "UI_Test")
    tap_text(evidence, "Meet MOM")

    for _ in range(8):
        if home_is_visible(evidence):
            return
        root = dump_ui(evidence, "mom-current.xml")
        start_now = find_node(root, "Start using MOM now")
        if start_now is not None:
            tap_node(start_now)
            time.sleep(1)
            if home_is_visible(evidence):
                return
        choice = find_node(root, "That sounds like me")
        if choice is None:
            time.sleep(1)
            continue
        tap_node(choice)
        time.sleep(1)

    if not home_is_visible(evidence):
        raise RuntimeError("MOM onboarding did not reach the home screen")


def resolve_apk(path: Path) -> Path:
    if path.is_file() and path.suffix == ".apk":
        return path
    matches = sorted(path.rglob("*.apk"))
    if len(matches) != 1:
        raise RuntimeError(f"Expected one APK in {path}, found {len(matches)}")
    return matches[0]


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: run_mom_emulator_ui.py <apk-or-directory> <evidence-directory>", file=sys.stderr)
        return 2

    apk = resolve_apk(Path(sys.argv[1]).resolve())
    evidence = Path(sys.argv[2]).resolve()
    evidence.mkdir(parents=True, exist_ok=True)

    try:
        wait_for_android()
        adb("install", "-r", str(apk))
        adb("shell", "pm", "grant", PACKAGE, "android.permission.RECORD_AUDIO", check=False)
        adb("shell", "am", "force-stop", PACKAGE, check=False)
        launch = adb("shell", "am", "start", "-W", "-n", ACTIVITY, check=False)
        launch_output = launch.stdout + launch.stderr
        (evidence / "mom-ui-start.txt").write_text(launch_output, encoding="utf-8")
        if launch.returncode != 0 or "Status: ok" not in launch_output:
            raise RuntimeError(f"MOM MainActivity did not launch cleanly: {launch_output.strip()}")

        wait_for_node(evidence, "Swearing is fine", timeout=60)
        complete_onboarding(evidence)
        wait_for_node(evidence, "Version 1.1.0", timeout=45)
        wait_for_node(evidence, "Settings", timeout=15)
        wait_for_node(evidence, "Text MOM", timeout=15)

        root = dump_ui(evidence, "mom-home.xml")
        orb = find_node(root, "Animated MOM plasma orb")
        if orb is None:
            raise RuntimeError("Live plasma orb semantics are missing")
        screenshot(evidence, "mom-home-live-plasma.png")

        tap_text(evidence, "Settings")
        wait_for_node(evidence, "MOM settings", timeout=20)
        dump_ui(evidence, "mom-settings.xml")
        screenshot(evidence, "mom-settings.png")
        print(f"MOM emulator UI verified against {apk.name}")
        return 0
    except Exception as error:
        print(f"MOM emulator UI verification failed: {error}", file=sys.stderr)
        try:
            dump_ui(evidence, "mom-failure.xml")
            screenshot(evidence, "mom-failure.png")
        except Exception:
            pass
        return 1
    finally:
        logs = adb("logcat", "-d", "-t", "800", check=False)
        (evidence / "mom-logcat.txt").write_text(logs.stdout + logs.stderr, encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
