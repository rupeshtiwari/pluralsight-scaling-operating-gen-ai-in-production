#!/usr/bin/env bash
# Tear down the Module 1 stack and tmux session.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SESSION="genai-m1"
BLUE=$'\033[38;2;0;163;255m'; LIME=$'\033[38;2;2;224;136m'; R=$'\033[0m'

tmux kill-session -t "$SESSION" 2>/dev/null && echo "${BLUE}tmux session closed${R}" || true
cd "$ROOT"
echo "${BLUE}Stopping Docker Compose stack ...${R}"
docker compose down -v
echo "${LIME}✔ stack stopped${R}"
