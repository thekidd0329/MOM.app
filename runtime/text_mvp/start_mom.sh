#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
MODEL_PATH="${1:-$HOME/MomBrain/models/Meta-Llama-3-8B-Instruct-abliterated-v3_q4.gguf}"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required."
  exit 1
fi

if ! command -v llama >/dev/null 2>&1; then
  echo "llama is not installed. Install llama.cpp, then rerun this command."
  exit 1
fi

if [ ! -s "$MODEL_PATH" ]; then
  echo "Local MOM model is missing. Fetching it now..."
  bash "$APP_DIR/get_model.sh"
fi

if [ ! -s "$MODEL_PATH" ]; then
  echo "Model still not found: $MODEL_PATH"
  exit 1
fi

cleanup() {
  if [ -n "${LLAMA_PID:-}" ]; then
    kill "$LLAMA_PID" 2>/dev/null || true
    wait "$LLAMA_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

llama serve -m "$MODEL_PATH" --host 127.0.0.1 --port 8080 --cors-origins localhost >"$APP_DIR/llama.log" 2>&1 &
LLAMA_PID=$!

READY=0
for _ in $(seq 1 120); do
  if curl -fsS http://127.0.0.1:8080/health >/dev/null 2>&1; then
    READY=1
    break
  fi
  if ! kill -0 "$LLAMA_PID" 2>/dev/null; then
    echo "llama.cpp stopped during startup. Last log lines:"
    tail -40 "$APP_DIR/llama.log" || true
    exit 1
  fi
  sleep 1
done

if [ "$READY" -ne 1 ]; then
  echo "llama.cpp did not become ready. Last log lines:"
  tail -40 "$APP_DIR/llama.log" || true
  exit 1
fi

echo "MOM is up. Open http://127.0.0.1:7331"
cd "$APP_DIR"
python3 app.py
