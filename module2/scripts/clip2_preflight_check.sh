#!/usr/bin/env bash
# =============================================================================
# Module 2 · Demo — Prove queues, rate limits, and fail-fast behavior
# AUTHOR PREFLIGHT: runs every demo step in the SAME order as module2/demo/clip2.md,
# captures each command and its on-screen output, asserts the output proves the
# learning objectives (TO2, EO2a/b/e), and writes a readable log for a reviewer.
#
#   bash module2/scripts/clip2_preflight_check.sh
#
# Defaults target Docker Compose on macOS; override with env vars for a native
# stack: API_BASE, PGHOST, PGPORT, PGUSER, PGDATABASE, PGPASSWORD
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
LOG="$ROOT/module2/clip2_preflight_log.txt"
: > "$LOG"

API_BASE="${API_BASE:-http://localhost:8000}"
export PGHOST="${PGHOST:-localhost}"; export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-genai}"; export PGDATABASE="${PGDATABASE:-genai}"
export PGPASSWORD="${PGPASSWORD:-genai}"
FMT="python3 $ROOT/scripts/fmt.py"

redis_query() {
  local out
  out="$(docker compose exec -T redis redis-cli "$@" 2>/dev/null)"
  [ -z "$out" ] && out="$(redis-cli "$@" 2>/dev/null)"
  printf '%s' "$out"
}

PINK=$'\033[38;2;255;22;117m'; LIME=$'\033[38;2;207;255;110m'
LGRN=$'\033[38;2;64;255;191m'; BLUE=$'\033[38;2;42;236;250m'
GRAY=$'\033[38;2;191;191;191m'; WHITE=$'\033[1;37m'; R=$'\033[0m'

PASS=0; FAIL=0
declare -a LO=()

emit() { printf '%s\n' "$1"; printf '%s\n' "$1" | sed -E 's/\x1b\[[0-9;]*m//g' >> "$LOG"; }
blank(){ emit ""; }
banner() { emit "${WHITE}================================================================================${R}"; emit "${WHITE} $1${R}"; emit "${WHITE}================================================================================${R}"; }
step_head() {
  blank
  emit "${WHITE}┌── STEP $1 ─────────────────────────────────────────────────────────────────${R}"
  emit "${WHITE}│ $2${R}"
  emit "${BLUE}│ WHY WE RUN THIS:${R} ${GRAY}$3${R}"
  emit "${LIME}│ WHAT THE LEARNER SEES:${R} ${GRAY}$4${R}"
  emit "${WHITE}└────────────────────────────────────────────────────────────────────────────${R}"
}
show_cmd() { emit "${BLUE}\$ $1${R}"; blank; }
verdict() {
  if [ "$1" = "0" ]; then PASS=$((PASS+1)); emit "  ${LIME}✔ PASS${R} — $2"
  else FAIL=$((FAIL+1)); emit "  ${PINK}✗ FAIL${R} — $2"; emit "  ${PINK}HOW TO FIX:${R} ${GRAY}$3${R}"; emit "  ${PINK}PROMPT TO FIX:${R} ${LGRN}$4${R}"; fi
  blank
}

banner "MODULE 2 · DEMO — QUEUES, RATE LIMITS, AND FAIL-FAST  (LO: TO2, EO2a, EO2b, EO2e)"
emit "${GRAY}stack:${R} API=${LGRN}${API_BASE}${R}  PG=${LGRN}${PGHOST}:${PGPORT}/${PGDATABASE}${R}"
emit "${GRAY}resetting to a clean, repeatable state ...${R}"
curl -s -X POST "$API_BASE/admin/reset" >/dev/null 2>&1

# STEP 1 — controlled spike: accepted / delayed / rejected
step_head "1" "Run a controlled traffic spike" \
  "A burst must split three ways — admitted now, queued, or shed — deterministically." \
  "submitted 20, then accepted 6, delayed 10, rejected 4, and the queue FULL at 10/10."
show_cmd "curl -s -X POST \$API_BASE/load/spike -d '{\"model\":\"balanced-std\",\"count\":20}' | python3 scripts/fmt.py --type spike"
RAW="$(curl -s -X POST "$API_BASE/load/spike" -H 'Content-Type: application/json' -d '{"model":"balanced-std","count":20}')"
emit "$(printf '%s' "$RAW" | $FMT --type spike 2>&1)"
if echo "$RAW" | jq -e '.submitted==20 and .accepted==6 and .delayed==10 and .rejected==4 and .queue_full==true' >/dev/null 2>&1; then
  verdict 0 "spike of 20 split deterministically into 6 accepted / 10 delayed / 4 rejected, queue full" "" ""
  LO+=("Step 1: a request queue with a configurable rate limit absorbs a spike and sheds the overflow (TO2, EO2a, EO2b)")
else
  verdict 1 "spike did not split into the expected 6/10/4" \
    "Check RATE_LIMITS and classify_arrival in app/providers/registry.py and run_spike in app/resilience/admission.py." \
    "POST /load/spike {model:balanced-std,count:20} must return accepted=6, delayed=10, rejected=4, queue_full=true. Fix app/resilience/admission.py."
fi

# STEP 2 — queue depth from Redis
step_head "2" "Read the queue backlog straight from Redis" \
  "The datastore's live queue depth must prove the backlog rose above zero under load." \
  "balanced-std depth 10, peak 10, capacity 10 — the queue is FULL."
show_cmd "docker compose exec -T redis redis-cli --json HGETALL resilience:queue | python3 scripts/fmt.py --type queue"
RAW="$(redis_query --json HGETALL resilience:queue)"
emit "$(printf '%s' "$RAW" | $FMT --type queue 2>&1)"
if echo "$RAW" | jq -e '(.["balanced-std:depth"]|tonumber)==10 and (.["balanced-std:capacity"]|tonumber)==10' >/dev/null 2>&1; then
  verdict 0 "Redis resilience:queue shows depth 10 at capacity 10 — the backlog is real" "" ""
  LO+=("Step 2: the queue backlog is observable live in the datastore (EO2a, EO2e)")
else
  verdict 1 "Redis queue depth does not match the spike backlog" \
    "Check set_queue in app/db/redis_client.py and the depth update in run_spike." \
    "HGETALL resilience:queue after the spike must show balanced-std:depth=10 and balanced-std:capacity=10. Fix app/db/redis_client.py."
fi

# STEP 3 — rate-limit window at threshold
step_head "3" "Compare the rate-limit count against its threshold" \
  "The admitted count must sit exactly at the configured limit — the accept-now boundary." \
  "balanced-std admitted 6, limit 6 — AT LIMIT."
show_cmd "docker compose exec -T redis redis-cli --json HGETALL resilience:ratelimit | python3 scripts/fmt.py --type ratelimit"
RAW="$(redis_query --json HGETALL resilience:ratelimit)"
emit "$(printf '%s' "$RAW" | $FMT --type ratelimit 2>&1)"
if echo "$RAW" | jq -e '(.["balanced-std:admitted"]|tonumber)==6 and (.["balanced-std:limit"]|tonumber)==6' >/dev/null 2>&1; then
  verdict 0 "Redis resilience:ratelimit shows admitted 6 at limit 6 — the window is at threshold" "" ""
  LO+=("Step 3: the configurable rate limit caps immediate admits and gates the queue (EO2a)")
else
  verdict 1 "rate-limit window does not sit at the configured threshold" \
    "Check set_ratelimit in app/db/redis_client.py and admitted=min(count,rate_limit) in run_spike." \
    "HGETALL resilience:ratelimit after the spike must show balanced-std:admitted=6 and balanced-std:limit=6. Fix app/resilience/admission.py."
fi

# STEP 4 — per provider/tier/class decision matrix
step_head "4" "Trigger rate-limit decisions by provider, tier, and class" \
  "The SAME burst must shed at a different point on each tier — limits are per provider/tier/class." \
  "econo-mini rejects 0, balanced-std rejects 4, premium-max rejects 13 for a burst of 20."
show_cmd "curl -s \$API_BASE/resilience/matrix?count=20 | python3 scripts/fmt.py --type matrix"
RAW="$(curl -s "$API_BASE/resilience/matrix?count=20")"
emit "$(printf '%s' "$RAW" | $FMT --type matrix 2>&1)"
if echo "$RAW" | jq -e '(.tiers|map(select(.model=="econo-mini"))[0].rejected)==0 and (.tiers|map(select(.model=="balanced-std"))[0].rejected)==4 and (.tiers|map(select(.model=="premium-max"))[0].rejected)==13' >/dev/null 2>&1; then
  verdict 0 "the same 20-burst sheds 0 / 4 / 13 across shared / dedicated / reserved tiers" "" ""
  LO+=("Step 4: rate limits are configured per provider, tier, and request class (EO2a, EO2e)")
else
  verdict 1 "the decision matrix does not shed differently per tier" \
    "Check RATE_LIMITS per tier in app/providers/registry.py and resilience_matrix in app/main.py." \
    "GET /resilience/matrix?count=20 must show econo-mini rejected=0, balanced-std rejected=4, premium-max rejected=13. Fix app/main.py."
fi

# STEP 5 — fail-fast 429 on a full queue
step_head "5" "Exceed the queue and prove the fail-fast 429" \
  "One request over a full queue must fail fast with HTTP 429 and a durable rejected receipt." \
  "http status 429, disposition rejected, reason 'Queue capacity exceeded', receipt_persisted true."
show_cmd "curl -s -X POST \$API_BASE/load/submit -d '{\"model\":\"balanced-std\"}' -w '...429...' | python3 scripts/fmt.py --type failfast"
RAW="$(curl -s -X POST "$API_BASE/load/submit" -H 'Content-Type: application/json' -d '{"model":"balanced-std"}' -w '\n{"http_status": %{http_code}}')"
emit "$(printf '%s' "$RAW" | $FMT --type failfast 2>&1)"
if echo "$RAW" | grep -q '"http_status": 429' && echo "$RAW" | grep -q 'Queue capacity exceeded' && echo "$RAW" | grep -q '"receipt_persisted":true'; then
  verdict 0 "a full queue rejects the next request with HTTP 429 and persists a rejected receipt" "" ""
  LO+=("Step 5: the fail-fast pattern rejects at capacity with a proper 429 response (EO2b, EO2e)")
else
  verdict 1 "the overflow request did not fail fast with a 429" \
    "Check submit_one in app/resilience/admission.py and the HTTPException(429) in load_submit (app/main.py)." \
    "POST /load/submit on a full queue must return HTTP 429 with 'Queue capacity exceeded' and receipt_persisted true. Fix app/main.py load_submit()."
fi

# STEP 6 — durable dispositions in PostgreSQL
step_head "6" "Distinguish every request's fate in the receipts" \
  "Accepted, delayed, and rejected must each be a distinct, durable PostgreSQL receipt." \
  "total 21, accepted 6, delayed 10, rejected 5 — rejected rows carry 0 tokens and \$0 cost."
show_cmd "curl -s \$API_BASE/resilience/dispositions | python3 scripts/fmt.py --type dispositions"
RAW="$(curl -s "$API_BASE/resilience/dispositions")"
emit "$(printf '%s' "$RAW" | $FMT --type dispositions 2>&1)"
if echo "$RAW" | jq -e '.total==21 and .dispositions.accepted==6 and .dispositions.delayed==10 and .dispositions.rejected==5 and (.samples|any(.disposition=="rejected" and .total_tokens==0))' >/dev/null 2>&1; then
  verdict 0 "receipts distinguish 6 accepted / 10 delayed / 5 rejected, rejected rows costing nothing" "" ""
  LO+=("Step 6: every accepted, delayed, and rejected request is a distinguishable durable receipt (EO2b, EO2e)")
else
  verdict 1 "receipts do not distinguish the three dispositions as expected" \
    "Check disposition/request_class columns and count_by_disposition in app/db/postgres.py and _receipt in admission.py." \
    "GET /resilience/dispositions must return total=21 with accepted=6, delayed=10, rejected=5 and rejected receipts at 0 tokens. Fix app/resilience/admission.py."
fi

# COVERAGE + SUMMARY
banner "LEARNING OBJECTIVE COVERAGE"
emit "${WHITE}TO2, EO2a, EO2b, EO2e — Absorb a spike with a rate-limited queue, fail${R}"
emit "${WHITE}       fast at capacity, and prove every request's fate in the receipts${R}"
if [ "${#LO[@]}" -gt 0 ]; then for e in "${LO[@]}"; do emit "  ${LIME}✔${R} ${GRAY}${e}${R}"; done; else emit "  ${PINK}✗ no evidence captured${R}"; fi

banner "SUMMARY"
TOTAL=$((PASS+FAIL))
emit "  ${LIME}PASS: ${PASS}${R}   ${PINK}FAIL: ${FAIL}${R}   ${GRAY}of ${TOTAL} steps${R}"
if [ "$FAIL" = "0" ]; then
  emit "  ${LIME}✔ ALL STEPS PASSED — demo aligns with TO2 and EO2a/b/e. Ready to record.${R}"
else
  emit "  ${PINK}✗ ${FAIL} step(s) failed — fix above, reset, and re-run.${R}"
fi
blank
emit "  ${GRAY}full readable log written to:${R} ${LGRN}module2/clip2_preflight_log.txt${R}"
exit "$FAIL"
