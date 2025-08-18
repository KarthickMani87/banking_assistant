#!/usr/bin/env sh
set -e

echo "Starting ollama server…"
ollama serve &

# wait for API
until curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; do
  echo "Waiting for ollama…"
  sleep 1
done

MODEL="${MODEL_NAME:-qwen2.5:3b-instruct}"
echo "Ensuring model present: $MODEL"
if ! curl -sf http://localhost:11434/api/tags | grep -q "\"name\":\"$MODEL\""; then
  echo "Pulling $MODEL…"
  ollama pull "$MODEL"
fi

wait

