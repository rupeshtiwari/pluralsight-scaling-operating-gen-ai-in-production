#!/usr/bin/env bash
# =============================================================================
# Module 1 · Demo — Payload-Based Routing & Deterministic Overrides
# AUTHOR PREFLIGHT: runs every demo step in the SAME order as module1/demo/clip5.md,
# captures each command and its on-screen output, asserts the output proves the
# learning objectives (EO1c, EO1d), and writes a readable log for a reviewer.
#
#   bash module1/scripts/clip5_preflight_check.sh
#
# Defaults target Docker Compose on macOS; override with env vars for a native
# stack: API_BASE, PGHOST, PGPORT, PGUSER, PGDATABASE, PGPASSWORD
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
LOG="$ROOT/module1/clip5_preflight_log.txt"
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
redis_query() {
  local out
  out="$(docker compose exec -T redis redis-cli "$@" 2>/dev/null)"
  [ -z "$out" ] && out="$(redis-cli "$@" 2>/dev/null)"
  printf '%s' "$out"
}
post() { curl -s -X POST "$API_BASE/route/smart" -H 'Content-Type: application/json' -d @"$1"; }
SQL_RECEIPTS="SELECT row_to_json(r) FROM (SELECT request_id,total_tokens,complexity,selected_model,route_reason,override_class,cost_estimate_usd FROM receipts ORDER BY created_at DESC LIMIT 6) r"

PINK=$'\033[38;2;255;22;117m'; LIME=$'\033[38;2;207;255;110m'
LGRN=$'\033[38;2;64;255;191m'; BLUE=$'\033[38;2;42;236;250m'
GRAY=$'\033[38;2;191;191;191m'; WHITE=$'\033[1;37m'; R=$'\033[0m'

PASS=0; FAIL=0
declare -a LO_EO1c=()
declare -a LO_EO1d=()

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

banner "MODULE 1 · DEMO — PAYLOAD-BASED ROUTING & DETERMINISTIC OVERRIDES  (LO: EO1c, EO1d)"
emit "${GRAY}stack:${R} API=${LGRN}${API_BASE}${R}  PG=${LGRN}${PGHOST}:${PGPORT}/${PGDATABASE}${R}"
emit "${GRAY}resetting to a clean, repeatable state ...${R}"
curl -s -X POST "$API_BASE/admin/reset" >/dev/null 2>&1

# STEP 1 — rules
step_head "1" "Load the routing rules" \
  "Three separate signals — size (evidence), declared complexity (selects tier), overrides (pin tier)." \
  "policy_name payload_smart, task→complexity→tier map, and overrides with direction and risk."
show_cmd "curl -s \$API_BASE/routing/rules | python3 scripts/fmt.py --type rules"
RAW="$(curl -s "$API_BASE/routing/rules")"
emit "$(printf '%s' "$RAW" | $FMT --type rules 2>&1)"
if echo "$RAW" | jq -e '.policy_name=="payload_smart" and (.task_complexity|length>=4) and (.complexity_tiers|length==3) and (.overrides.legal_review.direction=="risk") and (.overrides.bulk_batch.direction=="economy")' >/dev/null 2>&1; then
  verdict 0 "rules expose task→complexity→tier and overrides in both directions" "" ""
  LO_EO1c+=("Step 1: complexity is a declared signal (task_class) mapped to a tier, separate from size")
  LO_EO1d+=("Step 1: override classes declare a direction (economy / risk) and a risk level")
else
  verdict 1 "rules missing complexity map or override directions" \
    "Check TASK_COMPLEXITY / COMPLEXITY_TIERS / OVERRIDE_RULES in app/providers/registry.py and GET /routing/rules." \
    "GET /routing/rules must return payload_smart, a task_complexity map, 3 complexity_tiers, and overrides with direction=economy/risk. Fix app/providers/registry.py."
fi

# STEP 2 — length != premium
step_head "2" "Length alone does not force premium" \
  "A long simple request must route the same as a short simple one." \
  "short-simple and long-simple both econo-mini, complexity simple, sizes short vs long."
show_cmd "{ curl -s -X POST \$API_BASE/route/smart -d @data/payloads/smart_short_simple.json; echo; curl -s ... smart_long_simple.json; } | fmt --type smart-pair"
R1="$(post data/payloads/smart_short_simple.json)"
R2="$(post data/payloads/smart_long_simple.json)"
emit "$(printf '%s\n%s' "$R1" "$R2" | $FMT --type smart-pair 2>&1)"
if echo "$R1" | jq -e '.selected_model=="econo-mini" and .complexity=="simple" and .size=="short"' >/dev/null 2>&1 \
   && echo "$R2" | jq -e '.selected_model=="econo-mini" and .complexity=="simple" and .size=="long"' >/dev/null 2>&1; then
  verdict 0 "long-simple and short-simple both route to econo-mini" "" ""
  LO_EO1c+=("Step 2: length does not escalate the tier — a long simple task stays on econo-mini")
else
  verdict 1 "a simple request escalated on length" \
    "Check task_complexity()/size_label() in app/providers/registry.py — size must not select the tier." \
    "smart_short_simple and smart_long_simple must both return econo-mini/complexity=simple. Fix app/providers/registry.py."
fi

# STEP 3 — complexity, not length
step_head "3" "Complexity, not length, changes the tier" \
  "A short but complex request must route to premium." \
  "short-complex and long-complex both premium-max, complexity complex."
show_cmd "{ curl -s -X POST \$API_BASE/route/smart -d @data/payloads/smart_short_complex.json; echo; curl -s ... smart_long_complex.json; } | fmt --type smart-pair"
R1="$(post data/payloads/smart_short_complex.json)"
R2="$(post data/payloads/smart_long_complex.json)"
emit "$(printf '%s\n%s' "$R1" "$R2" | $FMT --type smart-pair 2>&1)"
if echo "$R1" | jq -e '.selected_model=="premium-max" and .complexity=="complex" and .size=="short"' >/dev/null 2>&1 \
   && echo "$R2" | jq -e '.selected_model=="premium-max" and .complexity=="complex"' >/dev/null 2>&1; then
  verdict 0 "short-complex and long-complex both route to premium-max" "" ""
  LO_EO1c+=("Step 3: a short complex task routes to premium — complexity, not length, drives the tier")
else
  verdict 1 "complexity did not drive the tier" \
    "Check TASK_COMPLEXITY (bug_triage/incident_analysis → complex) in app/providers/registry.py." \
    "smart_short_complex must return premium-max/complexity=complex/size=short. Fix app/providers/registry.py."
fi

# STEP 4 — overrides both directions
step_head "4" "Deterministic overrides — both directions" \
  "One override forces cheaper (bulk economy), one forces stronger (high-risk legal)." \
  "bulk → econo-mini (would_have=premium), legal → premium-max (would_have=econo, risk high)."
show_cmd "{ curl -s -X POST \$API_BASE/route/smart -d @data/payloads/smart_bulk_override.json; echo; curl -s ... smart_legal_override.json; } | fmt --type smart-pair"
RB="$(post data/payloads/smart_bulk_override.json)"
RL="$(post data/payloads/smart_legal_override.json)"
emit "$(printf '%s\n%s' "$RB" "$RL" | $FMT --type smart-pair 2>&1)"
if echo "$RB" | jq -e '.selected_model=="econo-mini" and .route_reason=="override_bulk_batch" and .would_have_selected=="premium-max" and .override_direction=="economy"' >/dev/null 2>&1 \
   && echo "$RL" | jq -e '.selected_model=="premium-max" and .route_reason=="override_legal_review" and .would_have_selected=="econo-mini" and .risk=="high"' >/dev/null 2>&1; then
  verdict 0 "overrides bypass the decision in both directions, with would_have_selected proof" "" ""
  LO_EO1d+=("Step 4: bulk override forces cheaper, high-risk legal override forces stronger — both proven by would_have_selected")
else
  verdict 1 "overrides did not fire in both directions" \
    "Check OVERRIDE_RULES (bulk_batch economy/econo, legal_review risk/premium) and smart_decision() in app/routing/payload.py." \
    "smart_bulk_override → econo-mini/override_bulk_batch/would=premium-max; smart_legal_override → premium-max/override_legal_review/would=econo-mini/risk=high. Fix app/routing/payload.py."
fi

# STEP 5 — Redis counters + PostgreSQL receipts
step_head "5" "Aggregate proof (Redis) + per-request audit (PostgreSQL)" \
  "Redis breaks decisions down by dimension and proves the weighted path was bypassed; receipts are the durable per-request record." \
  "smart:counters payload:simple=2 payload:complex=2 override:*=1 weighted=0; 6 receipts with complexity + route reason."
show_cmd "docker compose exec -T redis redis-cli --json HGETALL smart:counters | fmt --type smart-counters"
RC="$(redis_query --json HGETALL smart:counters)"
emit "$(printf '%s' "$RC" | $FMT --type smart-counters 2>&1)"
show_cmd "docker compose exec -T postgres psql ... LIMIT 6 | fmt --type smart-receipts"
RR="$(pg_query "$SQL_RECEIPTS")"
emit "$(printf '%s' "$RR" | $FMT --type smart-receipts 2>&1)"
COUNTERS_OK=0; RECEIPTS_OK=0
echo "$RC" | jq -e '(.["payload:simple"]|tonumber)==2 and (.["payload:complex"]|tonumber)==2 and (.["override:bulk_batch"]|tonumber)==1 and (.["override:legal_review"]|tonumber)==1 and (.weighted|tonumber)==0' >/dev/null 2>&1 && COUNTERS_OK=1
echo "$RR" | jq -s -e 'length==6 and (all(.[]; .complexity!=null)) and (any(.[]; .override_class=="bulk_batch")) and (any(.[]; .override_class=="legal_review"))' >/dev/null 2>&1 && RECEIPTS_OK=1
if [ "$COUNTERS_OK" = "1" ] && [ "$RECEIPTS_OK" = "1" ]; then
  verdict 0 "Redis dimensions match (weighted=0) and 6 durable receipts carry complexity + override" "" ""
  LO_EO1c+=("Step 5: Redis counts requests routed by complexity; receipts persist tokens + complexity per request")
  LO_EO1d+=("Step 5: Redis shows override picks and weighted=0 — the weighted path was bypassed")
else
  verdict 1 "Redis counters or PostgreSQL receipts did not match" \
    "Check smart_incr/reset_smart in app/db/redis_client.py, the receipts columns in app/db/postgres.py, and the /route/smart counter increment in app/main.py." \
    "After the 6 smart routes, HGETALL smart:counters must show payload:simple=2, payload:complex=2, override:*=1, weighted=0, and receipts must carry complexity + override_class. Fix app/db/*.py and app/main.py."
fi

# STEP 6 — validate all six classes
step_head "6" "Validate every payload class" \
  "All six approved forms (short/long × simple/complex, plus both overrides) must match." \
  "cases 6, all_match true, size and complexity shown per case."
show_cmd "curl -s \$API_BASE/routing/smart-validate | python3 scripts/fmt.py --type smart-validate"
RAW="$(curl -s "$API_BASE/routing/smart-validate")"
emit "$(printf '%s' "$RAW" | $FMT --type smart-validate 2>&1)"
if echo "$RAW" | jq -e '.all_match==true and .total==6 and (.cases|length==6)' >/dev/null 2>&1; then
  verdict 0 "all six canonical payload classes land on their expected tiers" "" ""
  LO_EO1c+=("Step 6: payload routing is deterministic across short/long × simple/complex")
  LO_EO1d+=("Step 6: both override directions validate alongside the payload cases — provable, repeatable")
else
  verdict 1 "smart-validate did not confirm all six cases match" \
    "Check GET /routing/smart-validate and SMART_VALIDATION_CASES in app/providers/registry.py." \
    "GET /routing/smart-validate must return all_match=true over 6 cases. Fix app/main.py routing_smart_validate() and the cases in app/providers/registry.py."
fi

# COVERAGE + SUMMARY
banner "LEARNING OBJECTIVE COVERAGE"
emit "${WHITE}EO1c — Payload-based routing that sends each request to the appropriate${R}"
emit "${WHITE}       tier for its declared complexity (kept separate from size)${R}"
if [ "${#LO_EO1c[@]}" -gt 0 ]; then for e in "${LO_EO1c[@]}"; do emit "  ${LIME}✔${R} ${GRAY}${e}${R}"; done; else emit "  ${PINK}✗ no evidence captured${R}"; fi
blank
emit "${WHITE}EO1d — Contrast weighted / payload / deterministic routing, and apply${R}"
emit "${WHITE}       override rules that intentionally bypass the decision${R}"
if [ "${#LO_EO1d[@]}" -gt 0 ]; then for e in "${LO_EO1d[@]}"; do emit "  ${LIME}✔${R} ${GRAY}${e}${R}"; done; else emit "  ${PINK}✗ no evidence captured${R}"; fi

banner "SUMMARY"
TOTAL=$((PASS+FAIL))
emit "  ${LIME}PASS: ${PASS}${R}   ${PINK}FAIL: ${FAIL}${R}   ${GRAY}of ${TOTAL} steps${R}"
if [ "$FAIL" = "0" ]; then
  emit "  ${LIME}✔ ALL STEPS PASSED — demo aligns with EO1c and EO1d. Ready to record.${R}"
else
  emit "  ${PINK}✗ ${FAIL} step(s) failed — fix above, reset, and re-run.${R}"
fi
blank
emit "  ${GRAY}full readable log written to:${R} ${LGRN}module1/clip5_preflight_log.txt${R}"
exit "$FAIL"
