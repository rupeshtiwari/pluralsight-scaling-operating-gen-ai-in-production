#!/usr/bin/env bash
# Bring the Module 3 demo to a clean, repeatable state:
#   - truncate PostgreSQL receipts
#   - reset every provider condition back to healthy
#   - clear routing / resilience state
# The lifecycle state (prompt versions, validation, canary, readiness) is
# deterministic and rebuilt each time a clip's /run endpoint is called, so a
# reset plus the clip's first step always reproduces the same demo.
# Safe to run any number of times.
set -uo pipefail
API_BASE="${API_BASE:-http://localhost:8000}"
PINK=$'\033[38;2;255;22;117m'; LIME=$'\033[38;2;207;255;110m'
LGRN=$'\033[38;2;64;255;191m'; R=$'\033[0m'

resp="$(curl -s -X POST "$API_BASE/admin/reset")"
if echo "$resp" | grep -q '"status": *"reset"'; then
  echo "${LIME}✔ demo reset${R} — ${LGRN}${resp}${R}"
else
  echo "${PINK}✗ reset failed${R} — is the stack up? (bash module3/scripts/demo_up.sh)"
  echo "  response: ${resp:-<empty>}"
  exit 1
fi
