#!/usr/bin/env python3
"""Generate MOM's launcher artwork into a generated Flutter Android scaffold.

The icon is generated with the Python standard library so Android CI never
needs to decode or re-encode a binary asset. The resulting PNGs are simple RGB
PNG files that AAPT2 can compile reliably.
"""

from __future__ import annotations

import binascii
import math
from pathlib import Path
import struct
import sys
import zlib

PURPLE = (168, 85, 247)
LAVENDER = (229, 197, 255)
BLACK = (0, 0, 0)
WHITE = (255, 255, 255)


def _mix(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    t = max(0.0, min(1.0, t))
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def _blend(dst: tuple[int, int, int], src: tuple[int, int, int], alpha: float) -> tuple[int, int, int]:
    return _mix(dst, src, alpha)


def _chunk(kind: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", binascii.crc32(kind + payload) & 0xFFFFFFFF)
    )


def _png_bytes(width: int, height: int, pixels: list[list[tuple[int, int, int]]]) -> bytes:
    raw = bytearray()
    for row in pixels:
        raw.append(0)  # PNG filter: none
        for r, g, b in row:
            raw.extend((r, g, b))
    return (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + _chunk(b"IDAT", zlib.compress(bytes(raw), level=6))
        + _chunk(b"IEND", b"")
    )


def _draw_line(
    pixels: list[list[tuple[int, int, int]]],
    x0: float,
    y0: float,
    x1: float,
    y1: float,
    color: tuple[int, int, int],
    alpha: float,
    width: int,
) -> None:
    size = len(pixels)
    steps = max(1, int(max(abs(x1 - x0), abs(y1 - y0)) * 1.5))
    for step in range(steps + 1):
        t = step / steps
        x = round(x0 + (x1 - x0) * t)
        y = round(y0 + (y1 - y0) * t)
        for oy in range(-width, width + 1):
            for ox in range(-width, width + 1):
                if ox * ox + oy * oy > width * width + 1:
                    continue
                px, py = x + ox, y + oy
                if 0 <= px < size and 0 <= py < size:
                    pixels[py][px] = _blend(pixels[py][px], color, alpha)


def _launcher_png(size: int) -> bytes:
    cx = cy = (size - 1) / 2
    radius = size * 0.31
    glow_radius = size * 0.43
    pixels = [[BLACK for _ in range(size)] for _ in range(size)]

    # Purple atmospheric glow on the true-black square.
    for y in range(size):
        for x in range(size):
            distance = math.hypot(x - cx, y - cy)
            if distance <= glow_radius:
                glow = max(0.0, 1.0 - distance / glow_radius)
                pixels[y][x] = _blend(BLACK, PURPLE, 0.16 * glow * glow)

    # Plasma sphere: white-hot center -> lavender -> purple -> deep violet edge.
    for y in range(size):
        for x in range(size):
            distance = math.hypot(x - cx, y - cy)
            if distance > radius:
                continue
            t = distance / radius
            if t < 0.10:
                color = _mix(WHITE, LAVENDER, t / 0.10)
            elif t < 0.46:
                color = _mix(LAVENDER, PURPLE, (t - 0.10) / 0.36)
            else:
                color = _mix(PURPLE, (23, 0, 38), (t - 0.46) / 0.54)
            pixels[y][x] = color

    # Deterministic branching plasma filaments, echoing the supplied MOM mark.
    branch_width = max(1, round(size / 120))
    for ray in range(24):
        base = math.tau * ray / 24
        points: list[tuple[float, float]] = [(cx, cy)]
        for step in range(1, 8):
            f = step / 8
            wobble = math.sin((ray + 1) * 2.17 + step * 1.91) * 0.10 * f
            angle = base + wobble
            r = radius * f * 0.96
            points.append((cx + math.cos(angle) * r, cy + math.sin(angle) * r))
        for a, b in zip(points, points[1:]):
            _draw_line(pixels, *a, *b, LAVENDER, 0.82, branch_width)

        # Small secondary branch from the middle of every other filament.
        if ray % 2 == 0:
            sx, sy = points[4]
            angle = base + (0.34 if ray % 4 == 0 else -0.34)
            ex = sx + math.cos(angle) * radius * 0.22
            ey = sy + math.sin(angle) * radius * 0.22
            _draw_line(pixels, sx, sy, ex, ey, PURPLE, 0.72, branch_width)

    # Crisp violet rim.
    rim_width = max(1, round(size / 96))
    for degree in range(720):
        angle = math.tau * degree / 720
        for inset in range(rim_width):
            r = radius - inset
            x = round(cx + math.cos(angle) * r)
            y = round(cy + math.sin(angle) * r)
            if 0 <= x < size and 0 <= y < size:
                pixels[y][x] = _blend(pixels[y][x], PURPLE, 0.88)

    return _png_bytes(size, size, pixels)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: apply_mom_android_branding.py <android-project-root>", file=sys.stderr)
        return 2

    project = Path(sys.argv[1]).resolve()
    res = project / "android" / "app" / "src" / "main" / "res"
    if not res.is_dir():
        print(f"android resources missing: {res}", file=sys.stderr)
        return 1

    targets = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, size in targets.items():
        target = res / folder / "ic_launcher.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(_launcher_png(size))

    print(f"Generated MOM launcher icon for {len(targets)} Android densities.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
