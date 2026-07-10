#!/usr/bin/env bash
# Capture the Module 1 demo exactly as it runs, command + output in sequence,
# to a plain-text transcript you can hand to a reviewer. No assertions here —
# this is the raw "what appears on screen" record. For pass/fail + LO coverage
# use preflight_check.sh instead.
#
#   bash module1/scripts/capture_demo_output.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
OUT="$ROOT/module1/demo_capture.txt"
: > "$OUT"

API_BASE="${API_BASE:-http://localhost:8000}"
export PGHOST="${PGHOST:-localhost}"; export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-genai}"; export PGDATABASE="${PGDATABASE:-genai}"
export PGPASSWORD="${PGPASSWORD:-genai}"
FMT="python3 $ROOT/scripts/fmt.py"

# Query Postgres inside the Docker container (host psql fallback for native CI).
pg_query() {
  local sql="$1" out
  out="$(docker compose exec -T postgres psql -U "${PGUSER:-genai}" -d "${PGDATABASE:-genai}" -tAc "$sql" 2>/dev/null)"
  [ -z "$out" ] && out="$(psql -tAc "$sql" 2>/dev/null)"
  printf '%s' "$out"
}
SQL_RECEIPT="SELECT row_to_json(r) FROM (SELECT selected_model,provider_tier,provider_status,prompt_tokens,completion_tokens,total_tokens,cost_estimate_usd,quality_score,policy_name,request_id FROM receipts ORDER BY created_at DESC LIMIT 1) r"

strip() { sed -E 's/\x1b\[[0-9;]*m//g'; }
rec() { printf '%s\n' "$*"; printf '%s\n' "$*" | strip >> "$OUT"; }
run() { # label  raw-command-string  fmt-type   (fetch expression via eval)
  rec ""
  rec "### $1"
  rec "\$ $2"
  rec ""
  local data; data="$(eval "$3" 2>&1)"
  local pretty; pretty="$(printf '%s' "$data" | $FMT --type "$4" 2>&1)"
  printf '%s\n' "$pretty"
  printf '%s\n' "$pretty" | strip >> "$OUT"
}

rec "MODULE 1 · CLIP 2 — DEMO CAPTURE (commands + on-screen output)"

run "Step 1 — Stack readiness" \
  "curl -s \$API_BASE/health | python3 scripts/fmt.py --type health" \
  "curl -s $API_BASE/health" health
run "Step 2 — Provider adapter configuration" \
  "curl -s \$API_BASE/providers | python3 scripts/fmt.py --type providers" \
  "curl -s $API_BASE/providers" providers
run "Step 3 — Deterministic local simulation" \
  "curl -s \$API_BASE/providers/balanced-std/probe | python3 scripts/fmt.py --type probe" \
  "curl -s $API_BASE/providers/balanced-std/probe" probe
run "Step 4 — Active provider condition matrix" \
  "curl -s \$API_BASE/providers/conditions | python3 scripts/fmt.py --type conditions" \
  "curl -s $API_BASE/providers/conditions" conditions
run "Step 5 — Baseline request" \
  "curl -s -X POST \$API_BASE/route -d @data/payloads/baseline_request.json | python3 scripts/fmt.py --type route" \
  "curl -s -X POST $API_BASE/route -H 'Content-Type: application/json' -d @data/payloads/baseline_request.json" route
run "Step 6 — PostgreSQL receipt" \
  "docker compose exec -T postgres psql -U genai -d genai -tAc 'SELECT row_to_json(r) ... FROM receipts ORDER BY created_at DESC LIMIT 1' | python3 scripts/fmt.py --type receipt" \
  'pg_query "$SQL_RECEIPT"' receipt

rec ""
rec "transcript written to: module1/demo_capture.txt"
