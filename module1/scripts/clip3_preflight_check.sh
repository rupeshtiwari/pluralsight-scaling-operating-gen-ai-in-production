#!/usr/bin/env bash
# =============================================================================
# Module 1 · Clip 3 — Prove weighted routing across model tiers
# AUTHOR PREFLIGHT: runs every demo step in the SAME order as module1/demo/clip3.md,
# captures each command and its on-screen output, asserts the output proves the
# learning objective (EO1b), and writes a readable log you can hand to a reviewer.
#
#   bash module1/scripts/clip3_preflight_check.sh
#
# Defaults target Docker Compose on macOS; override with env vars for a native
# stack: API_BASE, PGHOST, PGPORT, PGUSER, PGDATABASE, PGPASSWORD
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
LOG="$ROOT/module1/clip3_preflight_log.txt"
: > "$LOG"

API_BASE="${API_BASE:-http://localhost:8000}"
export PGHOST="${PGHOST:-localhost}"; export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-genai}"; export PGDATABASE="${PGDATABASE:-genai}"
export PGPASSWORD="${PGPASSWORD:-genai}"
FMT="python3 $ROOT/scripts/fmt.py"

pg_query() {
  local sql="$1" out
  out="$(docker compose exec -T postgres psql -U "${PGUSER:-genai}" -d "${PGDATABASE:-genai}" -tAc "$sql" 2>/dev/null)"
  [ -z "$out" ] && out="$(psql -tAc "$sql" 2>/dev/null)"
  printf '%s' "$out"
}
# Query Redis inside the container (host redis-cli fallback for native CI).
redis_query() {
  local out
  out="$(docker compose exec -T redis redis-cli "$@" 2>/dev/null)"
  [ -z "$out" ] && out="$(redis-cli "$@" 2>/dev/null)"
  printf '%s' "$out"
}
SQL_RECEIPTS="SELECT row_to_json(r) FROM (SELECT DISTINCT ON (selected_model) selected_model,provider_tier,cost_estimate_usd,policy_name FROM receipts ORDER BY selected_model, created_at DESC) r"

PINK=$'\033[38;2;255;22;117m'; LIME=$'\033[38;2;207;255;110m'
LGRN=$'\033[38;2;64;255;191m'; BLUE=$'\033[38;2;42;236;250m'
GRAY=$'\033[38;2;191;191;191m'; WHITE=$'\033[1;37m'; R=$'\033[0m'

PASS=0; FAIL=0
declare -a LO_EO1b=()

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

banner "MODULE 1 · CLIP 3 — WEIGHTED ROUTING ACROSS MODEL TIERS  (LO: EO1b)"
emit "${GRAY}stack:${R} API=${LGRN}${API_BASE}${R}  PG=${LGRN}${PGHOST}:${PGPORT}/${PGDATABASE}${R}"
emit "${GRAY}resetting to a clean, repeatable state ...${R}"
curl -s -X POST "$API_BASE/admin/reset" >/dev/null 2>&1

# STEP 1 — policy
step_head "1" "Load the weighted routing policy" \
  "Weights are chosen by cost and latency target — the design rationale is visible." \
  "policy_name weighted, and per tier: weight, latency target, and cost estimate (50/30/20)."
show_cmd "curl -s \$API_BASE/routing/policy | python3 scripts/fmt.py --type policy"
RAW="$(curl -s "$API_BASE/routing/policy")"
emit "$(printf '%s' "$RAW" | $FMT --type policy 2>&1)"
if echo "$RAW" | jq -e '.policy_name=="weighted" and (.weights|to_entries|map(.value)|add==100) and (.tiers|length==3) and (.tiers|all(has("latency_target_ms") and has("cost_estimate_usd")))' >/dev/null 2>&1; then
  verdict 0 "weighted policy shows weight, latency target, and cost per tier (weights sum to 100)" "" ""
  LO_EO1b+=("Step 1: per-tier weights are set against cost and latency targets (50/30/20)")
else
  verdict 1 "policy is missing weights, cost, or latency targets" \
    "Check WEIGHTED_WEIGHTS in app/providers/registry.py and GET /routing/policy in app/main.py (each tier needs latency_target_ms and cost_estimate_usd)." \
    "GET /routing/policy must return policy_name=weighted, weights summing to 100, and a tiers[] with latency_target_ms and cost_estimate_usd. Fix app/main.py routing_policy()."
fi

# STEP 2 — batch
step_head "2" "Run a controlled traffic batch" \
  "A fixed batch makes the distribution easy to reason about and repeatable." \
  "policy_name weighted, route_reason weighted_distribution, requests routed 20."
show_cmd "curl -s -X POST \$API_BASE/route/batch -d '{\"count\":20}' | python3 scripts/fmt.py --type batch"
RAW="$(curl -s -X POST "$API_BASE/route/batch" -H 'Content-Type: application/json' -d '{"count":20}')"
emit "$(printf '%s' "$RAW" | $FMT --type batch 2>&1)"
if echo "$RAW" | jq -e '.count==20 and .policy_name=="weighted" and .route_reason=="weighted_distribution"' >/dev/null 2>&1; then
  verdict 0 "20 requests routed under the weighted policy" "" ""
  LO_EO1b+=("Step 2: one endpoint routes a controlled batch under the weighted policy")
else
  verdict 1 "batch did not route 20 under the weighted policy" \
    "Check POST /route/batch and route_weighted() in app/routing/weighted.py." \
    "POST /route/batch with count=20 must return count=20, policy_name=weighted, route_reason=weighted_distribution. Fix app/main.py route_batch()."
fi

# STEP 3 — samples
step_head "3" "Inspect the individual routed decisions" \
  "The same endpoint must select different tiers, request by request." \
  "a table of requests where econo-mini, balanced-std, and premium-max all appear."
show_cmd "curl -s \$API_BASE/routing/last-batch?limit=6 | python3 scripts/fmt.py --type samples"
RAW="$(curl -s "$API_BASE/routing/last-batch?limit=6")"
emit "$(printf '%s' "$RAW" | $FMT --type samples 2>&1)"
if echo "$RAW" | jq -e '(.samples|length>=3) and ((.samples|map(.selected_model)|unique|length)>=2)' >/dev/null 2>&1; then
  verdict 0 "samples show the same endpoint selecting multiple tiers" "" ""
  LO_EO1b+=("Step 3: per-request decisions span multiple tiers under one policy")
else
  verdict 1 "samples do not show tier variety" \
    "Check the even-spread weighted_sequence() in app/providers/registry.py." \
    "GET /routing/last-batch must return samples spanning at least two tiers. Fix weighted_sequence() so the pick order interleaves tiers."
fi

# STEP 4 — Redis counters (direct datastore read)
step_head "4" "Read the routing counters straight from Redis" \
  "Proof from the datastore itself — a direct HGETALL, not the application view." \
  "total 20, and econo-mini 10, balanced-std 6, premium-max 4 (exactly 50/30/20)."
show_cmd "docker compose exec -T redis redis-cli --json HGETALL routing:counters | python3 scripts/fmt.py --type redis-counters"
RAW="$(redis_query --json HGETALL routing:counters)"
emit "$(printf '%s' "$RAW" | $FMT --type redis-counters 2>&1)"
if echo "$RAW" | jq -e '(.["econo-mini"]|tonumber)==10 and (.["balanced-std"]|tonumber)==6 and (.["premium-max"]|tonumber)==4' >/dev/null 2>&1; then
  verdict 0 "Redis HGETALL shows 10/6/4 across the three tiers" "" ""
  LO_EO1b+=("Step 4: the Redis datastore itself holds the 50/30/20 spread (direct HGETALL)")
else
  verdict 1 "Redis counters do not match the weighted distribution" \
    "Check hincrby routing:counters in app/db/redis_client.py and the batch loop." \
    "redis-cli HGETALL routing:counters after a 20-request batch must be econo-mini=10, balanced-std=6, premium-max=4. Fix app/db/redis_client.py."
fi

# STEP 5 — receipts (psql)
step_head "5" "Connect each model choice to cost and policy" \
  "Receipts prove each choice's cost and that the policy is uniform." \
  "one row per tier: cost differs by tier, policy_name is weighted on every row."
show_cmd "docker compose exec -T postgres psql ... DISTINCT ON (selected_model) ... | python3 scripts/fmt.py --type receipts"
RAW="$(pg_query "$SQL_RECEIPTS")"
emit "$(printf '%s' "$RAW" | $FMT --type receipts 2>&1)"
if echo "$RAW" | jq -s -e 'length==3 and all(.[]; .policy_name=="weighted") and ((map(.selected_model)|unique|length)==3)' >/dev/null 2>&1; then
  verdict 0 "three tiers persisted, each tied to its cost under the weighted policy" "" ""
  LO_EO1b+=("Step 5: receipts connect each tier's cost to the weighted policy")
else
  verdict 1 "receipts do not connect all three tiers to the weighted policy" \
    "Ensure route_weighted() writes policy_name=weighted and the batch persisted all tiers." \
    "Querying receipts must return 3 distinct tiers, each with policy_name=weighted. Fix app/routing/weighted.py and app/db/postgres.py."
fi

# STEP 6 — validate
step_head "6" "Confirm the distribution matches the configured weights" \
  "The observed split must equal the configured weights for every tier." \
  "all_match true, with observed==expected for econo-mini, balanced-std, premium-max."
show_cmd "curl -s \$API_BASE/routing/validate | python3 scripts/fmt.py --type validate"
RAW="$(curl -s "$API_BASE/routing/validate")"
emit "$(printf '%s' "$RAW" | $FMT --type validate 2>&1)"
if echo "$RAW" | jq -e '.all_match==true and (.tiers|length==3)' >/dev/null 2>&1; then
  verdict 0 "observed distribution equals the configured weights on every tier" "" ""
  LO_EO1b+=("Step 6: observed picks equal the configured weights — provable, repeatable balancing")
else
  verdict 1 "observed distribution does not match the configured weights" \
    "Check GET /routing/validate in app/main.py and the counters it compares." \
    "GET /routing/validate must return all_match=true after a clean 20-request batch. Fix app/main.py routing_validate()."
fi

# COVERAGE + SUMMARY
banner "LEARNING OBJECTIVE COVERAGE"
emit "${WHITE}EO1b — Implement weighted load balancing across multiple AI models to${R}"
emit "${WHITE}       distribute requests according to cost and latency targets${R}"
if [ "${#LO_EO1b[@]}" -gt 0 ]; then
  for e in "${LO_EO1b[@]}"; do emit "  ${LIME}✔${R} ${GRAY}${e}${R}"; done
else
  emit "  ${PINK}✗ no evidence captured${R}"
fi

banner "SUMMARY"
TOTAL=$((PASS+FAIL))
emit "  ${LIME}PASS: ${PASS}${R}   ${PINK}FAIL: ${FAIL}${R}   ${GRAY}of ${TOTAL} steps${R}"
if [ "$FAIL" = "0" ]; then
  emit "  ${LIME}✔ ALL STEPS PASSED — demo aligns with EO1b. Ready to record.${R}"
else
  emit "  ${PINK}✗ ${FAIL} step(s) failed — fix above, reset, and re-run.${R}"
fi
blank
emit "${WHITE}PROMPT TO FIX THIS CHECK (paste into your AI coding assistant if any step failed):${R}"
emit "${GRAY}\"Run bash module1/scripts/clip3_preflight_check.sh. For every step marked ✗ FAIL,${R}"
emit "${GRAY} read the HOW TO FIX and PROMPT TO FIX lines, open the named source file, correct${R}"
emit "${GRAY} the app so the step's assertion passes, reset with ./scripts/module1-demo-reset.sh,${R}"
emit "${GRAY} and re-run until PASS: 6, FAIL: 0. Do not change the demo steps or the LO.\"${R}"
blank
emit "  ${GRAY}full readable log written to:${R} ${LGRN}module1/clip3_preflight_log.txt${R}"
exit "$FAIL"
