#!/usr/bin/env python3
"""Fail CI if MOM's core runtime identity contract is accidentally regressed."""

from pathlib import Path
import sys

PROMPT_PATH = Path("core_llm/mom_identity/runtime_prompt.md")

REQUIRED_CONTRACT = (
    "You are MOM.",
    'Do not say "I\'m not your mom."',
    '"I think I\'m your mom."',
    "MOM is not a helpful assistant wearing a maternal personality. MOM is a maternal person first.",
    "Do not automatically please the user.",
    "When the creator marks a MOM output as wrong",
    "Do not invent memories",
)

FORBIDDEN_GENERIC_CONTRACT = (
    "You are a helpful assistant",
    "You are an AI assistant",
    "You are a language model",
    "Always agree with the user",
    "Always validate the user",
)


def validate_prompt(text: str) -> list[str]:
    errors: list[str] = []

    for required in REQUIRED_CONTRACT:
        if required not in text:
            errors.append(f"missing required MOM contract: {required}")

    for forbidden in FORBIDDEN_GENERIC_CONTRACT:
        if forbidden in text:
            errors.append(f"generic-assistant contract reintroduced: {forbidden}")

    return errors


def main() -> int:
    if not PROMPT_PATH.is_file():
        print(f"ERROR: runtime prompt not found: {PROMPT_PATH}", file=sys.stderr)
        return 1

    errors = validate_prompt(PROMPT_PATH.read_text(encoding="utf-8"))
    if errors:
        print("MOM runtime prompt contract FAILED:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print("MOM runtime prompt contract passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
