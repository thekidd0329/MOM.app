#!/usr/bin/env python3
"""Static contract for MOM's state-reactive production plasma orb."""

from __future__ import annotations

import hashlib
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "apps" / "mom_native"
HOME = APP / "lib" / "src" / "mom_home_screen.dart"
BRIDGE = APP / "lib" / "src" / "native_plasma_orb.dart"
MAIN = APP / "lib" / "main.dart"
VOICE_STATE = APP / "lib" / "src" / "voice_state.dart"
PLASMA = (
    APP
    / "android"
    / "app"
    / "src"
    / "main"
    / "kotlin"
    / "app"
    / "mom"
    / "mom_native"
    / "PlasmaOrbView.kt"
)
MAIN_ACTIVITY = PLASMA.with_name("MainActivity.kt")
PUBSPEC = APP / "pubspec.yaml"
LOGO = APP / "assets" / "photopea_background_remover_1786650252951.png"
ASSET_PATH = "assets/photopea_background_remover_1786650252951.png"
APPROVED_ORB_SHA256 = (
    "56fb6d6a5c2b92811a35f1b0d53562d9b5877981a35f8e2ee4d9875a08eace95"
)
APPROVED_ORB_SIZE = (1254, 1254)
ORB_VIEW_TYPE = "mom/plasma_orb"
ORB_STATES = ("idle", "listening", "thinking", "talking", "error")

_NATIVE_PROFILE = re.compile(
    r'^\s*([A-Z]+)\("([a-z]+)",\s*'
    r"(\d+),\s*(\d+),\s*([\d.]+)f,\s*([\d.]+)f,\s*"
    r"([\d.]+)f,\s*(\d+)L\),?$",
    re.MULTILINE,
)


def fail(message: str) -> None:
    print(f"::error::{message}", file=sys.stderr)
    raise SystemExit(1)


def require(text: str, needle: str, message: str) -> None:
    if needle not in text:
        fail(message)


def forbid(text: str, needle: str, message: str) -> None:
    if needle in text:
        fail(message)


def require_order(text: str, before: str, after: str, message: str) -> None:
    before_index = text.find(before)
    after_index = text.find(after)
    if before_index < 0 or after_index < 0 or before_index >= after_index:
        fail(message)


def verify_approved_artwork() -> None:
    if not LOGO.is_file() or LOGO.stat().st_size == 0:
        fail("MOM approved production orb PNG is missing or empty.")

    artwork = LOGO.read_bytes()
    if len(artwork) < 24:
        fail("MOM approved production orb PNG is truncated.")
    if artwork[:8] != b"\x89PNG\r\n\x1a\n" or artwork[12:16] != b"IHDR":
        fail("MOM approved production orb asset is not a valid PNG.")

    dimensions = struct.unpack(">II", artwork[16:24])
    if dimensions != APPROVED_ORB_SIZE:
        fail(
            "MOM approved production orb dimensions changed: "
            f"expected {APPROVED_ORB_SIZE}, got {dimensions}."
        )

    digest = hashlib.sha256(artwork).hexdigest()
    if digest != APPROVED_ORB_SHA256:
        fail(
            "MOM approved purple orb artwork changed without updating the "
            "visual contract."
        )


def dart_orb_states(bridge: str) -> tuple[str, ...]:
    match = re.search(r"enum\s+PlasmaOrbState\s*\{([^}]*)\}", bridge, re.DOTALL)
    if match is None:
        fail("Flutter plasma-orb state enum is missing.")
    return tuple(
        state.strip()
        for state in match.group(1).split(",")
        if state.strip()
    )


def native_orb_profiles(
    plasma: str,
) -> dict[str, tuple[int, int, float, float, float, int]]:
    profiles: dict[str, tuple[int, int, float, float, float, int]] = {}
    enum_names: list[str] = []
    for match in _NATIVE_PROFILE.finditer(plasma):
        enum_name, wire_name = match.group(1), match.group(2)
        enum_names.append(enum_name)
        profiles[wire_name] = (
            int(match.group(3)),
            int(match.group(4)),
            float(match.group(5)),
            float(match.group(6)),
            float(match.group(7)),
            int(match.group(8)),
        )

    expected_enum_names = [state.upper() for state in ORB_STATES]
    if enum_names != expected_enum_names or tuple(profiles) != ORB_STATES:
        fail(
            "Native orb profiles must exactly match Flutter wire states: "
            + ", ".join(ORB_STATES)
        )
    if len(set(profiles.values())) != len(ORB_STATES):
        fail("Every native orb state must have a distinct animation profile.")

    active_states = ("idle", "listening", "thinking", "talking")
    branches = [profiles[state][0] for state in active_states]
    frame_delays = [profiles[state][5] for state in active_states]
    if branches != sorted(branches) or len(set(branches)) != len(branches):
        fail("Orb branch intensity must increase from idle through talking.")
    if frame_delays != sorted(frame_delays, reverse=True) or len(
        set(frame_delays)
    ) != len(frame_delays):
        fail("Orb frame delay must decrease from idle through talking.")
    return profiles


def main() -> None:
    home = HOME.read_text(encoding="utf-8")
    bridge = BRIDGE.read_text(encoding="utf-8")
    main_source = MAIN.read_text(encoding="utf-8")
    voice_state = VOICE_STATE.read_text(encoding="utf-8")
    plasma = PLASMA.read_text(encoding="utf-8")
    main_activity = MAIN_ACTIVITY.read_text(encoding="utf-8")
    pubspec = PUBSPEC.read_text(encoding="utf-8")

    verify_approved_artwork()

    require(
        home,
        "NativePlasmaOrb(",
        "MOM home must host the state-reactive plasma orb.",
    )
    require(
        home,
        ASSET_PATH,
        "The approved PNG must remain the non-Android fallback.",
    )
    for state in ORB_STATES:
        require(
            home,
            f"PlasmaOrbState.{state}",
            f"{state.title()} state is not connected to the orb.",
        )
    require(
        home,
        "normalized.contains('speak')",
        "Speaking status mapping is missing.",
    )
    require(
        home,
        "normalized.contains('talk')",
        "Talking status mapping is missing.",
    )
    require(
        home,
        "normalized.contains('error')",
        "Error status mapping is missing.",
    )
    require(
        home,
        "normalized.contains('offline')",
        "Offline status mapping is missing.",
    )
    require(
        home,
        "normalized.contains('unavailable')",
        "Unavailable status mapping is missing.",
    )
    require_order(
        home,
        "if (widget.listening)",
        "final normalized = widget.status.toLowerCase()",
        "Listening must remain the highest-priority orb state.",
    )
    require_order(
        home,
        "PlasmaOrbState.talking",
        "if (widget.busy) return PlasmaOrbState.thinking",
        "Speaking must map to talking before the generic busy state.",
    )
    require(
        home,
        "class _ControlZapPainter",
        "MOM must retain the startup control-zap layer.",
    )
    require(
        home,
        "Version 1.1.0",
        "Visible home-screen version must remain the current UI build label.",
    )
    require(home, "Icons.mic", "Top-left microphone control is missing.")
    require(home, "Icons.settings", "Top-right settings control is missing.")
    require(home, "Icons.keyboard", "Bottom-right keyboard control is missing.")
    require(
        home,
        "constraints.maxWidth * 0.64",
        "Orb must remain compact rather than filling the screen.",
    )

    require(
        main_source,
        "bool get _busy => _voiceState.blocksInput;",
        "MOM busy state is no longer sourced from the voice state machine.",
    )
    require(
        main_source,
        "bool get _listening => _voiceState.listening;",
        "MOM listening state is no longer sourced from the voice state machine.",
    )
    require(
        main_source,
        "busy: _busy,",
        "Home screen no longer receives busy state.",
    )
    require(
        main_source,
        "listening: _listening,",
        "Home screen no longer receives listening state.",
    )
    require(
        main_source,
        "status: _status,",
        "Home screen no longer receives voice status.",
    )
    require(
        voice_state,
        "MomVoiceState.speaking => 'Speaking...'",
        "Speaking state no longer supplies the talking wire signal.",
    )
    require(
        main_source,
        "status: 'Voice error · text still works'",
        "Voice failures no longer supply the error wire signal.",
    )

    if dart_orb_states(bridge) != ORB_STATES:
        fail("Flutter orb states must exactly match the native wire contract.")
    require(
        bridge,
        "String get wireName => name;",
        "Flutter orb enum names no longer define the native wire values.",
    )
    require(bridge, "AndroidView(", "Android plasma platform view is missing.")
    require(
        bridge,
        f"viewType: '{ORB_VIEW_TYPE}'",
        "Orb view type changed.",
    )
    require(
        bridge,
        f"MethodChannel('{ORB_VIEW_TYPE}/$id')",
        "Flutter orb method-channel route changed.",
    )
    require(
        bridge,
        "defaultTargetPlatform != TargetPlatform.android",
        "Non-Android orb fallback guard is missing.",
    )
    require(bridge, "return widget.fallback;", "Static orb fallback is missing.")
    require(
        bridge,
        "invokeMethod<void>('setState'",
        "Flutter must push live MOM state into the native orb.",
    )
    require(
        bridge,
        "'state': widget.state.wireName",
        "Flutter no longer sends the selected orb wire state.",
    )
    if bridge.count("'state': widget.state.wireName") != 2:
        fail("Orb state must be sent both at Android view creation and live update.")
    require(
        bridge,
        "creationParams: <String, Object>",
        "Android view creation no longer includes initial orb state parameters.",
    )
    require(
        bridge,
        "creationParamsCodec",
        "Initial orb state must cross the platform-view boundary.",
    )
    require(
        bridge,
        "oldWidget.state != widget.state",
        "Live orb state changes no longer trigger a native update.",
    )
    require(
        bridge,
        "onPlatformViewCreated: _onPlatformViewCreated",
        "Flutter no longer attaches its live-state method channel.",
    )

    native_orb_profiles(plasma)
    require(
        plasma,
        f"flutter_assets/{ASSET_PATH}",
        "Native renderer must draw the approved PNG as its base layer.",
    )
    require(
        plasma,
        "approvedArtwork ?: return",
        "Native renderer must fail closed if approved artwork cannot load.",
    )
    require(
        plasma,
        "val side = min(width, height).toFloat()",
        "Native orb must remain square inside its platform view.",
    )
    require(
        plasma,
        "canvas.drawBitmap(artwork, null, artworkRect, artworkPaint)",
        "Native renderer no longer draws the approved artwork.",
    )
    require(
        plasma,
        "repeat(orbState.branches)",
        "Branch animation loop is missing.",
    )
    require(
        plasma,
        "repeat(orbState.edgeArcs)",
        "Edge-arc animation loop is missing.",
    )
    require_order(
        plasma,
        "canvas.drawBitmap(artwork, null, artworkRect, artworkPaint)",
        "repeat(orbState.branches)",
        "Approved artwork must be drawn before live plasma overlays.",
    )
    require(
        plasma,
        "if (running) postInvalidateDelayed(orbState.frameDelayMs)",
        "Native plasma animation loop is missing.",
    )
    require(
        plasma,
        "override fun onAttachedToWindow()",
        "Orb animation no longer starts with its Android view lifecycle.",
    )
    require(
        plasma,
        "override fun onDetachedFromWindow()",
        "Orb animation no longer stops with its Android view lifecycle.",
    )
    require(plasma, "fun dispose()", "Orb renderer cleanup hook is missing.")
    require(
        plasma,
        "?: OrbState.IDLE",
        "Unknown wire states must safely fall back to idle.",
    )
    require(
        main_activity,
        "registry.registerViewFactory(",
        "Android plasma view factory is not registered with Flutter.",
    )
    require(
        main_activity,
        f'"{ORB_VIEW_TYPE}"',
        "Android plasma platform-view registration is missing.",
    )
    require_order(
        main_activity,
        "registry.registerViewFactory(",
        f'"{ORB_VIEW_TYPE}"',
        "Android orb view type is not part of platform-view registration.",
    )
    require_order(
        main_activity,
        f'"{ORB_VIEW_TYPE}"',
        "PlasmaOrbViewFactory(flutterEngine.dartExecutor.binaryMessenger)",
        "Android orb registration no longer constructs its view factory.",
    )
    require(
        main_activity,
        "PlasmaOrbViewFactory",
        "Android plasma platform-view factory is missing.",
    )
    require(
        main_activity,
        "flutterEngine.dartExecutor.binaryMessenger",
        "Orb method-channel messenger is missing.",
    )
    require(
        main_activity,
        f'MethodChannel(messenger, "{ORB_VIEW_TYPE}/$viewId")',
        "Android orb method-channel route does not match Flutter.",
    )
    require(
        main_activity,
        'get("state") as? String',
        "Android orb no longer reads its initial Flutter state.",
    )
    require(
        main_activity,
        "setOrbState(initialState)",
        "Android orb no longer applies its initial Flutter state.",
    )
    require(
        main_activity,
        'call.argument<String>("state")',
        "Android orb no longer reads live Flutter state updates.",
    )
    require(
        main_activity,
        '"setState" -> {',
        "Android orb no longer handles Flutter live-state calls.",
    )
    require(
        main_activity,
        "channel.setMethodCallHandler(null)",
        "Android orb method channel is not released on disposal.",
    )
    require(
        main_activity,
        "orb.dispose()",
        "Android orb renderer is not released on disposal.",
    )

    require(
        pubspec,
        f"- {ASSET_PATH}",
        "Approved production orb asset must remain declared.",
    )
    require(
        pubspec,
        "version: 1.0.1+10",
        "pubspec release version must remain 1.0.1+10.",
    )

    forbid(
        home,
        "class _ElectricOrbPainter",
        "Old Flutter procedural orb must not return.",
    )
    forbid(
        home,
        "class _PlasmaOrbPainter",
        "Old Flutter plasma approximation must not return.",
    )

    print("MOM state-reactive approved-art plasma UI contract OK")


if __name__ == "__main__":
    main()
