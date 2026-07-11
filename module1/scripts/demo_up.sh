#!/usr/bin/env bash
# Start the Module 1 stack and open a tmux window ready to run the demo.
#
#   - builds and starts FastAPI, Redis, PostgreSQL via Docker Compose
#   - waits until /health reports healthy
#   - resets to a clean state
#   - drops you into a tmux session with the repo root as the working dir
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
API_BASE="${API_BASE:-http://localhost:8000}"
SESSION="genai-m1"
LIME=$'\033[38;2;207;255;110m'; PINK=$'\033[38;2;255;22;117m'
BLUE=$'\033[38;2;42;236;250m'; R=$'\033[0m'

cd "$ROOT"

# Make sure the environment is ready first — this auto-starts Docker Desktop if
# it is installed but not open, and stops with clear fix steps otherwise.
if ! bash "$ROOT/scripts/ensure-ready.sh"; then
  echo "${PINK}✗ environment not ready — fix the items above and re-run.${R}"
  exit 1
fi

echo "${BLUE}Starting stack via Docker Compose ...${R}"
docker compose up -d --build

echo "${BLUE}Waiting for /health to report healthy ...${R}"
for i in $(seq 1 40); do
  if curl -s "$API_BASE/health" | grep -q '"status": *"healthy"'; then
    echo "${LIME}✔ stack healthy${R}"
    break
  fi
  sleep 2
  if [ "$i" = "40" ]; then
    echo "${PINK}✗ stack did not become healthy in time${R}"; exit 1
  fi
done

bash "$ROOT/scripts/module1-demo-reset.sh" || true

if command -v tmux >/dev/null 2>&1; then
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  tmux new-session -d -s "$SESSION" -c "$ROOT"
  echo "${LIME}✔ tmux session '${SESSION}' ready${R} — attach with: ${BLUE}tmux attach -t ${SESSION}${R}"
else
  echo "${BLUE}tmux not found — run the demo steps from ${ROOT} directly.${R}"
fi
