#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path


def clean_text(value):
    return value.strip() if isinstance(value, str) else ""


def normalize_context(value):
    if value is None:
        return []
    if not isinstance(value, list):
        raise ValueError("context must be an array")
    result = []
    for index, turn in enumerate(value):
        if not isinstance(turn, dict):
            raise ValueError(f"context[{index}] must be an object")
        role = clean_text(turn.get("role"))
        content = clean_text(turn.get("content"))
        if role not in {"user", "assistant"}:
            raise ValueError(f"context[{index}].role must be user or assistant")
        if not content:
            raise ValueError(f"context[{index}].content is empty")
        result.append({"role": role, "content": content})
    return result


def normalize_row(row, line_number):
    if not isinstance(row, dict):
        raise ValueError("row must be a JSON object")

    user_message = clean_text(row.get("user_message"))
    ideal_response = clean_text(row.get("ideal_response"))
    if not user_message:
        raise ValueError("missing user_message")
    if not ideal_response:
        raise ValueError("missing ideal_response")

    context = normalize_context(row.get("context"))
    messages = [*context, {"role": "user", "content": user_message}, {"role": "assistant", "content": ideal_response}]

    metadata = {
        "source_line": line_number,
        "id": clean_text(row.get("id")),
        "topic": clean_text(row.get("topic")),
        "emotion": row.get("emotion") if isinstance(row.get("emotion"), list) else [],
        "maternal_intent": clean_text(row.get("maternal_intent")),
        "known_context": row.get("known_context") if isinstance(row.get("known_context"), list) else [],
        "bad_response": clean_text(row.get("bad_response")),
        "failure_reason": clean_text(row.get("failure_reason")),
        "tags": row.get("tags") if isinstance(row.get("tags"), list) else [],
        "notes": clean_text(row.get("notes")),
    }
    metadata = {key: value for key, value in metadata.items() if value not in ("", [], None)}

    return {"messages": messages, "metadata": metadata}


def main():
    parser = argparse.ArgumentParser(description="Validate MOM behavior examples and normalize them into chat SFT JSONL.")
    parser.add_argument("input", type=Path, help="Input JSONL file")
    parser.add_argument("output", type=Path, help="Normalized output JSONL file")
    args = parser.parse_args()

    accepted = []
    rejected = []

    with args.input.open("r", encoding="utf-8") as source:
        for line_number, raw_line in enumerate(source, start=1):
            if not raw_line.strip():
                continue
            try:
                row = json.loads(raw_line)
                accepted.append(normalize_row(row, line_number))
            except Exception as exc:
                rejected.append((line_number, str(exc)))

    if rejected:
        for line_number, reason in rejected:
            print(f"REJECT line {line_number}: {reason}", file=sys.stderr)
        print(f"Rejected {len(rejected)} row(s). No output written.", file=sys.stderr)
        return 1

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as target:
        for row in accepted:
            target.write(json.dumps(row, ensure_ascii=False) + "\n")

    print(f"Accepted {len(accepted)} row(s). Wrote {args.output}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
