#!/usr/bin/env python3
"""Stage the Android shared-library closure required by one or more roots.

CrispASR's Android build tree can contain shared libraries produced by targets
that are not dependencies of libcrispasr.so. Copying every lib*.so into
jniLibs makes APK verification treat those unrelated build products as runtime
requirements. This tool follows ELF DT_NEEDED entries instead and stages only
the build-local dependency closure rooted at the requested libraries.

Usage:
    python3 tools/stage_android_runtime_libs.py BUILD_ROOT DEST ROOT [ROOT ...]
"""

from __future__ import annotations

import hashlib
import re
import shutil
import subprocess
import sys
from collections import deque
from pathlib import Path

_NEEDED = re.compile(r"\(NEEDED\).*Shared library: \[(.+?)\]")


def _digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def _index(build_root: Path) -> dict[str, Path]:
    candidates: dict[str, list[Path]] = {}
    for path in build_root.rglob("lib*.so"):
        if path.is_file():
            candidates.setdefault(path.name, []).append(path)

    resolved: dict[str, Path] = {}
    for name, paths in candidates.items():
        paths = sorted(paths, key=lambda p: (len(p.parts), str(p)))
        if len(paths) > 1:
            hashes = {_digest(path) for path in paths}
            if len(hashes) > 1:
                joined = ", ".join(str(path) for path in paths)
                raise ValueError(
                    f"ambiguous Android runtime library {name}: {joined}"
                )
        resolved[name] = paths[0]
    return resolved


def _needed(path: Path) -> tuple[str, ...]:
    try:
        result = subprocess.run(
            ["readelf", "-d", str(path)],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except FileNotFoundError as exc:
        raise ValueError("readelf is required to stage Android runtime libraries") from exc
    except subprocess.CalledProcessError as exc:
        raise ValueError(
            f"readelf failed for {path}: {exc.stderr.strip()}"
        ) from exc

    return tuple(match.group(1) for match in _NEEDED.finditer(result.stdout))


def stage(build_root: Path, destination: Path, roots: list[str]) -> list[Path]:
    if not build_root.is_dir():
        raise ValueError(f"Android native build root does not exist: {build_root}")
    if not roots:
        raise ValueError("at least one root runtime library is required")

    libraries = _index(build_root)
    if not libraries:
        raise ValueError(f"no shared libraries found under: {build_root}")

    missing_roots = [root for root in roots if root not in libraries]
    if missing_roots:
        raise ValueError(
            "root runtime libraries missing: " + ", ".join(missing_roots)
        )

    queue: deque[str] = deque(roots)
    selected: dict[str, Path] = {}
    external: set[str] = set()

    while queue:
        name = queue.popleft()
        if name in selected:
            continue
        path = libraries[name]
        selected[name] = path
        for dependency in _needed(path):
            if dependency in libraries:
                if dependency not in selected:
                    queue.append(dependency)
            else:
                external.add(dependency)

    destination.mkdir(parents=True, exist_ok=True)
    for stale in destination.glob("lib*.so"):
        stale.unlink()

    staged: list[Path] = []
    for name in sorted(selected):
        output = destination / name
        shutil.copy2(selected[name], output)
        staged.append(output)

    print("Android build-local runtime closure:")
    for path in staged:
        print(f"  {path.name}")
    if external:
        print("External/system DT_NEEDED libraries (not staged from CrispASR build):")
        for name in sorted(external):
            print(f"  {name}")
    print(f"Staged {len(staged)} runtime libraries into {destination}")
    return staged


def main(argv: list[str]) -> int:
    if len(argv) < 4:
        print(
            "usage: stage_android_runtime_libs.py BUILD_ROOT DEST ROOT [ROOT ...]",
            file=sys.stderr,
        )
        return 2

    try:
        staged = stage(
            Path(argv[1]).expanduser().resolve(),
            Path(argv[2]).expanduser().resolve(),
            argv[3:],
        )
    except (OSError, ValueError) as exc:
        print(f"Android runtime staging failed: {exc}", file=sys.stderr)
        return 1

    return 0 if staged else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
