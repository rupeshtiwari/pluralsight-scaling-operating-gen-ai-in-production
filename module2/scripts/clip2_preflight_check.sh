#!/usr/bin/env bash
# =============================================================================
# Module 2 · Demo — Prove queues, rate limits, and fail-fast behavior
# AUTHOR PREFLIGHT: runs every demo step in the SAME order as module2/demo/clip2.md,
# captures each command and its on-screen output, asserts the output proves the
# learning objectives (TO2, EO2a/b/e), and writes a readable log for a reviewer.
#
#   bash module2/scripts/clip2_preflight_check.sh
#
# Step 1 runs the real k6 spike when k6 is installed; otherwise it drives the SAME
# atomic admission path with a concurrent-curl burst, so the validated outcome
# matches the live demo. Override the stack with env vars for a native run:
# API_BASE, PGHOST, PGPORT, PGUSER, PGDATABASE, PGPASSWORD
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

# STEP 1 — real k6 spike (or concurrent-curl fallback over the same atomic path)
step_head "1" "Run the k6 spike and read the HTTP outcomes" \
  "Real concurrent load must split into 200s and 429s with no failures — atomically correct under races." \
  "submitted 20, HTTP 200 16, HTTP 429 4, HTTP 500 0, failures 0, split 6/10/4."
if command -v k6 >/dev/null 2>&1; then
  show_cmd "API_BASE=\$API_BASE k6 run --quiet module2/k6/clip2_spike.js"
  API_BASE="$API_BASE" k6 run --quiet "$ROOT/module2/k6/clip2_spike.js" >/tmp/k6out.txt 2>/dev/null
  SUM="$(cat "$ROOT/module2/k6/last_summary.json" 2>/dev/null)"
else
  show_cmd "seq 20 | xargs -P20 curl -X POST \$API_BASE/load/submit ...   # concurrent burst (k6 not installed)"
  CODES="$(seq 20 | xargs -P 20 -I {} curl -s -o /dev/null -w '%{http_code}\n' -X POST "$API_BASE/load/submit" -H 'Content-Type: application/json' -d '{"model":"balanced-std"}')"
  H200="$(printf '%s\n' "$CODES" | grep -c '^200$')"
  H429="$(printf '%s\n' "$CODES" | grep -c '^429$')"
  H500="$(printf '%s\n' "$CODES" | grep -c '^5..$')"
  DD="$(curl -s "$API_BASE/resilience/dispositions")"
  ACC="$(printf '%s' "$DD" | jq '.dispositions.accepted')"
  DEL="$(printf '%s' "$DD" | jq '.dispositions.delayed')"
  REJ="$(printf '%s' "$DD" | jq '.dispositions.rejected')"
  SUM="$(printf '{"submitted":20,"accepted":%s,"delayed":%s,"rejected":%s,"http_200":%s,"http_429":%s,"http_500":%s,"failed":0}' "$ACC" "$DEL" "$REJ" "$H200" "$H429" "$H500")"
fi
emit "$(printf '%s' "$SUM" | $FMT --type k6-summary 2>&1)"
if echo "$SUM" | jq -e '.accepted==6 and .delayed==10 and .rejected==4 and .http_200==16 and .http_429==4 and .http_500==0 and .failed==0' >/dev/null 2>&1; then
  verdict 0 "20 concurrent requests split 6 accepted / 10 delayed / 4 rejected — 16x200, 4x429, no 500s or failures" "" ""
  LO+=("Step 1: a rate-limited queue absorbs a real concurrent spike and sheds the overflow (TO2, EO2a, EO2e)")
else
  verdict 1 "the concurrent spike did not split into 6/10/4 with clean HTTP outcomes" \
    "Check the atomic admission Lua in app/db/redis_client.py and RATE_LIMITS in app/providers/registry.py." \
    "20 concurrent POST /load/submit must yield accepted=6, delayed=10, rejected=4 (16x200, 4x429), 0 failures. Fix app/db/redis_client.py."
fi

# STEP 2 — real queue list of request IDs
step_head "2" "Inspect the real queue in Redis" \
  "The queue must hold actual request IDs — real parked work, not only a depth counter." \
  "10 real request IDs in the Redis LIST, depth 10 at capacity 10."
show_cmd "docker compose exec -T redis redis-cli --json LRANGE resilience:queue:balanced-std 0 -1 | python3 scripts/fmt.py --type queue-list"
RAW="$(redis_query --json LRANGE resilience:queue:balanced-std 0 -1)"
emit "$(printf '%s' "$RAW" | $FMT --type queue-list 2>&1)"
if echo "$RAW" | jq -e 'length==10 and all(.[]; startswith("req-"))' >/dev/null 2>&1; then
  verdict 0 "the Redis LIST holds 10 real queued request IDs — genuine parked work" "" ""
  LO+=("Step 2: the queue is a real list of request IDs the operator can inspect (EO2a)")
else
  verdict 1 "the queue does not hold 10 real request IDs" \
    "Check the RPUSH in the admission Lua (app/db/redis_client.py) and queue_ids()." \
    "LRANGE resilience:queue:balanced-std after the spike must return 10 req- IDs. Fix app/db/redis_client.py."
fi

# STEP 3 — rate-limit window at threshold
step_head "3" "Compare the rate-limit count against its threshold" \
  "The admitted count must sit at the configured limit, shown with its window duration." \
  "admitted 6 of 6 AT LIMIT, window 6 per 10s, limiter key provider:tier:class."
show_cmd "curl -s \$API_BASE/resilience/rate-limit | python3 scripts/fmt.py --type ratelimit"
RAW="$(curl -s "$API_BASE/resilience/rate-limit")"
emit "$(printf '%s' "$RAW" | $FMT --type ratelimit 2>&1)"
if echo "$RAW" | jq -e '.admitted==6 and .limit==6 and .window_seconds==10 and .at_limit==true and (.limiter_key|test(":"))' >/dev/null 2>&1; then
  verdict 0 "rate-limit window shows admitted 6/6 AT LIMIT, 6 per 10s, keyed provider:tier:class" "" ""
  LO+=("Step 3: the rate limit caps immediate admits per window and gates the queue (EO2a)")
else
  verdict 1 "rate-limit window or key is wrong" \
    "Check /resilience/rate-limit and RATE_LIMIT_WINDOW_SECONDS/limiter_key in the registry." \
    "GET /resilience/rate-limit must show admitted=6, limit=6, window_seconds=10, at_limit=true, limiter_key with colons. Fix app/main.py."
fi

# STEP 4 — per provider/tier/class matrix with provider identity
step_head "4" "Compare policies by provider, tier, and request class" \
  "The SAME burst must shed differently per key, and the provider identity must be visible." \
  "econo-ai rejects 0, balanced-ai rejects 4, premium-ai rejects 13, each with its provider name."
show_cmd "curl -s \$API_BASE/resilience/matrix?count=20 | python3 scripts/fmt.py --type matrix"
RAW="$(curl -s "$API_BASE/resilience/matrix?count=20")"
emit "$(printf '%s' "$RAW" | $FMT --type matrix 2>&1)"
if echo "$RAW" | jq -e '(.tiers|map(select(.provider=="econo-ai"))[0].rejected)==0 and (.tiers|map(select(.provider=="balanced-ai"))[0].rejected)==4 and (.tiers|map(select(.provider=="premium-ai"))[0].rejected)==13 and (.tiers|all(has("provider") and has("limiter_key")))' >/dev/null 2>&1; then
  verdict 0 "the same 20-burst sheds 0 / 4 / 13 across three named providers, each with its limiter key" "" ""
  LO+=("Step 4: limits are keyed per provider, tier, and request class (EO2a)")
else
  verdict 1 "the matrix does not show provider identity or per-key shedding" \
    "Check _limit_row/limiter_key in app/main.py and provider fields in RATE_LIMITS." \
    "GET /resilience/matrix?count=20 must show provider + limiter_key per row and rejected 0/4/13. Fix app/main.py."
fi

# STEP 5 — fail-fast 429 + Retry-After
step_head "5" "Exceed the queue and prove the fail-fast 429" \
  "One request over a full queue must fail fast with HTTP 429, a Retry-After, and a durable receipt." \
  "http 429, disposition rejected, reason 'Queue capacity exceeded', retry_after 10s, receipt_persisted true."
show_cmd "curl -s -X POST \$API_BASE/load/submit -d '{\"model\":\"balanced-std\"}' -w '...429...' | python3 scripts/fmt.py --type failfast"
RAW="$(curl -s -X POST "$API_BASE/load/submit" -H 'Content-Type: application/json' -d '{"model":"balanced-std"}' -w '\n{"http_status": %{http_code}}')"
emit "$(printf '%s' "$RAW" | $FMT --type failfast 2>&1)"
if echo "$RAW" | grep -q '"http_status": 429' && echo "$RAW" | grep -q 'Queue capacity exceeded' && echo "$RAW" | grep -q '"retry_after_seconds":10' && echo "$RAW" | grep -q '"receipt_persisted":true'; then
  verdict 0 "a full queue rejects with HTTP 429, Retry-After 10s, and a durable rejected receipt" "" ""
  LO+=("Step 5: the fail-fast pattern rejects at capacity with a proper 429 + Retry-After (EO2b)")
else
  verdict 1 "the overflow request did not fail fast with 429 + Retry-After" \
    "Check load_submit HTTPException(429, headers Retry-After) in app/main.py." \
    "POST /load/submit on a full queue must return HTTP 429 with retry_after_seconds=10 and receipt_persisted true. Fix app/main.py."
fi

# STEP 6 — durable dispositions with estimate labels
step_head "6" "Distinguish every request's fate in the receipts" \
  "Accepted, delayed, and rejected must each be a distinct receipt; rejected cost must be zero." \
  "total 21, accepted 6, delayed 10, rejected 5 — rejected rows carry 0 est tokens and \$0 est cost."
show_cmd "curl -s \$API_BASE/resilience/dispositions | python3 scripts/fmt.py --type dispositions"
RAW="$(curl -s "$API_BASE/resilience/dispositions")"
emit "$(printf '%s' "$RAW" | $FMT --type dispositions 2>&1)"
if echo "$RAW" | jq -e '.total==21 and .dispositions.accepted==6 and .dispositions.delayed==10 and .dispositions.rejected==5 and (.samples|any(.disposition=="rejected" and .total_tokens==0))' >/dev/null 2>&1; then
  verdict 0 "receipts distinguish 6 accepted / 10 delayed / 5 rejected, rejected rows costing nothing" "" ""
  LO+=("Step 6: every accepted, delayed, and rejected request is a distinguishable durable receipt (EO2b)")
else
  verdict 1 "receipts do not distinguish the three dispositions as expected" \
    "Check disposition column and count_by_disposition in app/db/postgres.py." \
    "GET /resilience/dispositions must return total=21 with 6/10/5 and rejected receipts at 0 tokens. Fix app/resilience/admission.py."
fi

# STEP 7 — correlate one request across log and receipt
step_head "7" "Correlate one request across logs and receipts" \
  "One request ID must appear in the structured log and the PostgreSQL receipt, agreeing on the outcome." \
  "one log per disposition, and a rejected request ID present in both log and receipt with matching disposition."
show_cmd "curl -s \$API_BASE/resilience/admission-logs | python3 scripts/fmt.py --type admission-logs"
RAW="$(curl -s "$API_BASE/resilience/admission-logs")"
emit "$(printf '%s' "$RAW" | $FMT --type admission-logs 2>&1)"
if echo "$RAW" | jq -e '(.samples|map(.disposition)|(index("accepted") and index("delayed") and index("rejected"))) and .correlate.in_log==true and .correlate.in_receipt==true and .correlate.match==true' >/dev/null 2>&1; then
  verdict 0 "one request ID reconciles across the structured log and the durable receipt" "" ""
  LO+=("Step 7: structured logs plus receipts give a three-way trace of every request (EO2b, EO2e)")
else
  verdict 1 "the log/receipt correlation did not hold" \
    "Check log_admission/get_admission_logs and receipt_by_request_id in app/db." \
    "GET /resilience/admission-logs must show one log per disposition and correlate.match=true. Fix app/main.py."
fi

# COVERAGE + SUMMARY
banner "LEARNING OBJECTIVE COVERAGE"
emit "${WHITE}TO2, EO2a, EO2b, EO2e — Absorb a real k6 spike with a rate-limited queue,${R}"
emit "${WHITE}       fail fast at capacity, and trace every request across log and receipt${R}"
emit "${GRAY}       (EO2e here = controlled load + overload; failures/latency/quota are separate)${R}"
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
