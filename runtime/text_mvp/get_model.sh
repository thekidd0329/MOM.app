#!/usr/bin/env bash
set -euo pipefail

MODEL_DIR="${MOM_MODEL_DIR:-$HOME/MomBrain/models}"
MODEL_FILE="Meta-Llama-3-8B-Instruct-abliterated-v3_q4.gguf"
MODEL_URL="https://huggingface.co/failspy/Meta-Llama-3-8B-Instruct-abliterated-v3-GGUF/resolve/main/${MODEL_FILE}?download=true"

mkdir -p "$MODEL_DIR"
cd "$MODEL_DIR"

if [ -s "$MODEL_FILE" ]; then
  echo "Already present: $MODEL_DIR/$MODEL_FILE"
  exit 0
fi

echo "Downloading MOM test brain to $MODEL_DIR/$MODEL_FILE"
curl -L --fail --retry 5 --retry-delay 2 -C - -o "$MODEL_FILE" "$MODEL_URL"
echo "Ready: $MODEL_DIR/$MODEL_FILE"
