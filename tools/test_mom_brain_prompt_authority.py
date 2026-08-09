from pathlib import Path
import re
import sys

path = Path(
    sys.argv[1] if len(sys.argv) > 1 else "supabase/functions/mom-brain/index.ts"
)
source = path.read_text(encoding="utf-8")

checks = {
    "canonical server prompt exists": "const MOM_CANONICAL_PROMPT" in source,
    "client prompt is explicitly disabled": "client_system_prompt_accepted: false" in source,
    "client system_prompt is only detected/ignored": (
        'Object.prototype.hasOwnProperty.call(body, "system_prompt")' in source
        and "body.system_prompt" not in source
    ),
    "system-role history is excluded": re.search(
        r'\.filter\(\(turn: any\) => \(turn\.role === "user" \|\| turn\.role === "assistant"\)',
        source,
    )
    is not None,
    "system message comes from server composition": (
        '{ role: "system", content: system }' in source
        and "const systemParts = [MOM_CANONICAL_PROMPT]" in source
    ),
    "client knowledge_context cannot become authority": "body.knowledge_context" not in source,
    "prompt integrity metadata is exposed": (
        "runtime_prompt_version: MOM_RUNTIME_VERSION" in source
        and "runtime_prompt_sha256: await sha256(MOM_CANONICAL_PROMPT)" in source
    ),
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")

if failed:
    raise SystemExit("prompt authority regression: " + "; ".join(failed))

print("PASS: MOM brain prompt-authority source contract")
