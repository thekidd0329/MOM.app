#!/usr/bin/env python3
"""Build the read-only repository knowledge bundle consumed by native MOM clients.

This deliberately excludes large/binary/generated/private-runtime paths. The bundle
contains project-authored text/code reference material, not model weights, .env files,
local transcripts, caches, or Git internals.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "apps" / "mom_native" / "assets" / "knowledge" / "mom_knowledge.jsonl"
PROMPT_SRC = ROOT / "core_llm" / "mom_identity" / "runtime_prompt.md"
PROMPT_OUT = ROOT / "apps" / "mom_native" / "assets" / "runtime_prompt.md"

EXTENSIONS = {
    ".md", ".txt", ".json", ".yaml", ".yml", ".toml", ".sql", ".py", ".dart", ".js", ".ts", ".html", ".css"
}
EXCLUDED_DIRS = {
    ".git", ".venv", "venv", "node_modules", "build", ".dart_tool", ".idea", ".vscode", "models", "__pycache__"
}
EXCLUDED_NAMES = {".env", ".env.local", "conversations.jsonl", "mom_knowledge.jsonl"}
MAX_FILE_BYTES = 160_000


def include(path: Path) -> bool:
    rel = path.relative_to(ROOT)
    if any(part in EXCLUDED_DIRS for part in rel.parts):
        return False
    if path.name in EXCLUDED_NAMES or path.name.startswith(".env."):
        return False
    if path.suffix.lower() not in EXTENSIONS:
        return False
    try:
        return path.stat().st_size <= MAX_FILE_BYTES
    except OSError:
        return False


def main() -> int:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    rows: list[dict[str, str]] = []
    for path in sorted(ROOT.rglob("*")):
        if not path.is_file() or not include(path):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        if not text.strip():
            continue
        rows.append({"path": path.relative_to(ROOT).as_posix(), "text": text})

    with OUT.open("w", encoding="utf-8") as fh:
        for row in rows:
            fh.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")

    if PROMPT_SRC.exists():
        PROMPT_OUT.parent.mkdir(parents=True, exist_ok=True)
        PROMPT_OUT.write_text(PROMPT_SRC.read_text(encoding="utf-8"), encoding="utf-8")

    print(f"MOM knowledge: {len(rows)} files -> {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
