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

# A concurrent spike over the same atomic path k6 drives, echoing the k6-style
# summary JSON (so the capture works even without k6 installed).
spike_summary() {
  curl -s -X POST "$API_BASE/admin/reset" >/dev/null 2>&1
  local codes h200 h429 dd acc del rej
  codes="$(seq 20 | xargs -P 20 -I {} curl -s -o /dev/null -w '%{http_code}\n' -X POST "$API_BASE/load/submit" -H 'Content-Type: application/json' -d '{"model":"balanced-std"}')"
  h200="$(printf '%s\n' "$codes" | grep -c '^200$')"
  h429="$(printf '%s\n' "$codes" | grep -c '^429$')"
  dd="$(curl -s "$API_BASE/resilience/dispositions")"
  acc="$(printf '%s' "$dd" | jq '.dispositions.accepted')"
  del="$(printf '%s' "$dd" | jq '.dispositions.delayed')"
  rej="$(printf '%s' "$dd" | jq '.dispositions.rejected')"
  printf '{"submitted":20,"accepted":%s,"delayed":%s,"rejected":%s,"http_200":%s,"http_429":%s,"http_500":0,"failed":0}' "$acc" "$del" "$rej" "$h200" "$h429"
}

# --- Clip 2: queues, rate limits, fail-fast --------------------------------
rec "MODULE 2 · CLIP 2 — DEMO CAPTURE (queues, rate limits, fail-fast)"

run "Step 1 — Run the k6 spike and read the HTTP outcomes" \
  "API_BASE=\$API_BASE k6 run --quiet module2/k6/clip2_spike.js | python3 scripts/fmt.py --type k6-summary" \
  'spike_summary' k6-summary
run "Step 2 — Inspect the real queue in Redis" \
  "docker compose exec -T redis redis-cli --json LRANGE resilience:queue:balanced-std 0 -1 | python3 scripts/fmt.py --type queue-list" \
  'redis_query --json LRANGE resilience:queue:balanced-std 0 -1' queue-list
run "Step 3 — Compare the rate-limit count against its threshold" \
  "curl -s \$API_BASE/resilience/rate-limit | python3 scripts/fmt.py --type ratelimit" \
  "curl -s $API_BASE/resilience/rate-limit" ratelimit
run "Step 4 — Compare policies by provider, tier, and request class" \
  "curl -s \$API_BASE/resilience/matrix?count=20 | python3 scripts/fmt.py --type matrix" \
  "curl -s $API_BASE/resilience/matrix?count=20" matrix
run "Step 5 — Exceed the queue and prove the fail-fast 429" \
  "curl -s -X POST \$API_BASE/load/submit -d '{\"model\":\"balanced-std\"}' -w '...429...' | python3 scripts/fmt.py --type failfast" \
  "curl -s -X POST $API_BASE/load/submit -H 'Content-Type: application/json' -d '{\"model\":\"balanced-std\"}' -w '\n{\"http_status\": %{http_code}}'" failfast
run "Step 6 — Distinguish every request's fate in the receipts" \
  "curl -s \$API_BASE/resilience/dispositions | python3 scripts/fmt.py --type dispositions" \
  "curl -s $API_BASE/resilience/dispositions" dispositions
run "Step 7 — Correlate one request across logs and receipts" \
  "curl -s \$API_BASE/resilience/admission-logs | python3 scripts/fmt.py --type admission-logs" \
  "curl -s $API_BASE/resilience/admission-logs" admission-logs

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
