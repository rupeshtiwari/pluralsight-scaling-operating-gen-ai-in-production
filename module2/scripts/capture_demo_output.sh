#!/usr/bin/env bash
# Capture the Module 2 demos exactly as they run, command + output in sequence,
# to a plain-text transcript you can hand to a reviewer. No assertions here —
# this is the raw "what appears on screen" record. For pass/fail + LO coverage
# use clip2_preflight_check.sh / clip3_preflight_check.sh instead.
#
#   bash module2/scripts/capture_demo_output.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
OUT="$ROOT/module2/demo_capture.txt"
: > "$OUT"

API_BASE="${API_BASE:-http://localhost:8000}"
export PGHOST="${PGHOST:-localhost}"; export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-genai}"; export PGDATABASE="${PGDATABASE:-genai}"
export PGPASSWORD="${PGPASSWORD:-genai}"
FMT="python3 $ROOT/scripts/fmt.py"

# Read a Redis hash inside the Docker container (native redis-cli fallback for CI).
redis_query() {
  local out
  out="$(docker compose exec -T redis redis-cli "$@" 2>/dev/null)"
  [ -z "$out" ] && out="$(redis-cli "$@" 2>/dev/null)"
  printf '%s' "$out"
}

strip() { sed -E 's/\x1b\[[0-9;]*m//g'; }
rec() { printf '%s\n' "$*"; printf '%s\n' "$*" | strip >> "$OUT"; }
run() { # label  displayed-command  fetch-expression  fmt-type
  rec ""
  rec "### $1"
  rec "\$ $2"
  rec ""
  local data; data="$(eval "$3" 2>&1)"
  local pretty; pretty="$(printf '%s' "$data" | $FMT --type "$4" 2>&1)"
  printf '%s\n' "$pretty"
  printf '%s\n' "$pretty" | strip >> "$OUT"
}

# --- Clip 2: queues, rate limits, fail-fast --------------------------------
rec "MODULE 2 · CLIP 2 — DEMO CAPTURE (queues, rate limits, fail-fast)"
curl -s -X POST "$API_BASE/admin/reset" >/dev/null 2>&1

run "Step 1 — Run a controlled traffic spike" \
  "curl -s -X POST \$API_BASE/load/spike -d '{\"model\":\"balanced-std\",\"count\":20}' | python3 scripts/fmt.py --type spike" \
  "curl -s -X POST $API_BASE/load/spike -H 'Content-Type: application/json' -d '{\"model\":\"balanced-std\",\"count\":20}'" spike
run "Step 2 — Read the queue backlog straight from Redis" \
  "docker compose exec -T redis redis-cli --json HGETALL resilience:queue | python3 scripts/fmt.py --type queue" \
  'redis_query --json HGETALL resilience:queue' queue
run "Step 3 — Compare the rate-limit count against its threshold" \
  "docker compose exec -T redis redis-cli --json HGETALL resilience:ratelimit | python3 scripts/fmt.py --type ratelimit" \
  'redis_query --json HGETALL resilience:ratelimit' ratelimit
run "Step 4 — Trigger rate-limit decisions by provider, tier, and class" \
  "curl -s \$API_BASE/resilience/matrix?count=20 | python3 scripts/fmt.py --type matrix" \
  "curl -s $API_BASE/resilience/matrix?count=20" matrix
run "Step 5 — Exceed the queue and prove the fail-fast 429" \
  "curl -s -X POST \$API_BASE/load/submit -d '{\"model\":\"balanced-std\"}' -w '...429...' | python3 scripts/fmt.py --type failfast" \
  "curl -s -X POST $API_BASE/load/submit -H 'Content-Type: application/json' -d '{\"model\":\"balanced-std\"}' -w '\n{\"http_status\": %{http_code}}'" failfast
run "Step 6 — Distinguish every request's fate in the receipts" \
  "curl -s \$API_BASE/resilience/dispositions | python3 scripts/fmt.py --type dispositions" \
  "curl -s $API_BASE/resilience/dispositions" dispositions

# --- Clip 3: circuit breaker fallback + retry backoff ----------------------
rec ""
rec "MODULE 2 · CLIP 3 — DEMO CAPTURE (circuit breaker fallback + retry backoff)"
curl -s -X POST "$API_BASE/admin/reset" >/dev/null 2>&1

run "Step 1 — Load the circuit-breaker configuration" \
  "curl -s \$API_BASE/resilience/circuit-config | python3 scripts/fmt.py --type circuit-config" \
  "curl -s $API_BASE/resilience/circuit-config" circuit-config
curl -s -X POST "$API_BASE/resilience/drill" >/dev/null 2>&1
run "Step 2 — Walk the circuit through its states" \
  "curl -s -X POST \$API_BASE/resilience/drill >/dev/null; curl -s \$API_BASE/resilience/circuit | python3 scripts/fmt.py --type circuit" \
  "curl -s $API_BASE/resilience/circuit" circuit
run "Step 3 — Prove fallback routing keeps the caller whole" \
  "curl -s \$API_BASE/resilience/fallback | python3 scripts/fmt.py --type fallback" \
  "curl -s $API_BASE/resilience/fallback" fallback
run "Step 4 — Inspect retry backoff and prove no storm" \
  "curl -s \$API_BASE/resilience/retry-log | python3 scripts/fmt.py --type retry-log" \
  "curl -s $API_BASE/resilience/retry-log" retry-log
run "Step 5 — Reconcile caller response, receipt, and retry log" \
  "curl -s \$API_BASE/resilience/failover-reconcile | python3 scripts/fmt.py --type failover-reconcile" \
  "curl -s $API_BASE/resilience/failover-reconcile" failover-reconcile

rec ""
rec "transcript written to: module2/demo_capture.txt"
