#!/usr/bin/env bash
set -euo pipefail

MODEL_PATH="${1:-$HOME/MomBrain/models/Meta-Llama-3-8B-Instruct-abliterated-v3_q4.gguf}"
APP_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! command -v llama >/dev/null 2>&1; then
  echo "llama command not found. Install llama.cpp first."
  exit 1
fi

if [ ! -f "$MODEL_PATH" ]; then
  echo "Model not found: $MODEL_PATH"
  echo "Pass the GGUF path as the first argument."
  exit 1
fi

cleanup() {
  if [ -n "${LLAMA_PID:-}" ]; then kill "$LLAMA_PID" 2>/dev/null || true; fi
}
trap cleanup EXIT INT TERM

llama serve -m "$MODEL_PATH" --host 127.0.0.1 --port 8080 --cors-origins localhost &
LLAMA_PID=$!

for _ in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:8080/health >/dev/null 2>&1; then break; fi
  sleep 1
done

cd "$APP_DIR"
exec python3 app.py
