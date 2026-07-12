#!/usr/bin/env bash
# =============================================================================
# Module 1 · Clip 5 — Payload-based routing & deterministic overrides
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
SQL_RECEIPTS="SELECT row_to_json(r) FROM (SELECT selected_model,provider_tier,route_reason,cost_estimate_usd,policy_name FROM receipts ORDER BY created_at DESC LIMIT 3) r"

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

banner "MODULE 1 · CLIP 5 — PAYLOAD-BASED ROUTING & DETERMINISTIC OVERRIDES  (LO: EO1c, EO1d)"
emit "${GRAY}stack:${R} API=${LGRN}${API_BASE}${R}  PG=${LGRN}${PGHOST}:${PGPORT}/${PGDATABASE}${R}"
emit "${GRAY}resetting to a clean, repeatable state ...${R}"
curl -s -X POST "$API_BASE/admin/reset" >/dev/null 2>&1

# STEP 1 — rules
step_head "1" "Load the payload-based routing rules" \
  "The tier is decided by payload complexity, with named override classes." \
  "policy_name payload_smart, three complexity buckets, and three override classes."
show_cmd "curl -s \$API_BASE/routing/rules | python3 scripts/fmt.py --type rules"
RAW="$(curl -s "$API_BASE/routing/rules")"
emit "$(printf '%s' "$RAW" | $FMT --type rules 2>&1)"
if echo "$RAW" | jq -e '.policy_name=="payload_smart" and (.complexity_tiers|length==3) and (.overrides|length>=3)' >/dev/null 2>&1; then
  verdict 0 "rule table exposes complexity buckets and override classes" "" ""
  LO_EO1c+=("Step 1: complexity buckets map payload size to the appropriate tier")
  LO_EO1d+=("Step 1: named override classes are declared alongside payload routing")
else
  verdict 1 "rule table missing complexity tiers or override classes" \
    "Check COMPLEXITY_TIERS and OVERRIDE_RULES in app/providers/registry.py and GET /routing/rules." \
    "GET /routing/rules must return policy_name=payload_smart, 3 complexity_tiers, and >=3 overrides. Fix app/providers/registry.py."
fi

# STEP 2 — simple payload
step_head "2" "Route a simple payload to the low-cost tier" \
  "A short request needs no premium model — the content picks econo-mini." \
  "selected_model econo-mini, complexity low, route_reason payload_complexity_low."
show_cmd "curl -s -X POST \$API_BASE/route/smart -d @data/payloads/smart_simple.json | python3 scripts/fmt.py --type smart"
RAW="$(curl -s -X POST "$API_BASE/route/smart" -H 'Content-Type: application/json' -d @data/payloads/smart_simple.json)"
emit "$(printf '%s' "$RAW" | $FMT --type smart 2>&1)"
if echo "$RAW" | jq -e '.selected_model=="econo-mini" and .complexity=="low" and .route_reason=="payload_complexity_low"' >/dev/null 2>&1; then
  verdict 0 "simple payload routed to the low-cost tier by its content" "" ""
  LO_EO1c+=("Step 2: a low-complexity payload self-routes to econo-mini")
else
  verdict 1 "simple payload did not route to the low-cost tier" \
    "Check classify_complexity() thresholds and route_smart() in app/routing/payload.py." \
    "POST /route/smart with data/payloads/smart_simple.json must return econo-mini, complexity=low, payload_complexity_low. Fix app/routing/payload.py."
fi

# STEP 3 — complex payload
step_head "3" "Route a complex payload to the premium tier" \
  "Same endpoint, heavier request — the content pushes it to premium-max." \
  "selected_model premium-max, complexity high, route_reason payload_complexity_high."
show_cmd "curl -s -X POST \$API_BASE/route/smart -d @data/payloads/smart_complex.json | python3 scripts/fmt.py --type smart"
RAW="$(curl -s -X POST "$API_BASE/route/smart" -H 'Content-Type: application/json' -d @data/payloads/smart_complex.json)"
emit "$(printf '%s' "$RAW" | $FMT --type smart 2>&1)"
if echo "$RAW" | jq -e '.selected_model=="premium-max" and .complexity=="high" and .route_reason=="payload_complexity_high"' >/dev/null 2>&1; then
  verdict 0 "complex payload routed to premium through the same endpoint" "" ""
  LO_EO1c+=("Step 3: a high-complexity payload self-routes to premium-max")
else
  verdict 1 "complex payload did not route to the premium tier" \
    "Check the medium_max threshold and COMPLEXITY_TIERS in app/providers/registry.py." \
    "POST /route/smart with data/payloads/smart_complex.json must return premium-max, complexity=high, payload_complexity_high. Fix app/providers/registry.py."
fi

# STEP 4 — override
step_head "4" "Force a tier with a deterministic override" \
  "Some traffic must be pinned — the override wins over what the payload would pick." \
  "selected_model econo-mini, route_reason override_bulk_batch, would_have_selected premium-max."
show_cmd "curl -s -X POST \$API_BASE/route/smart -d @data/payloads/smart_override.json | python3 scripts/fmt.py --type smart"
RAW="$(curl -s -X POST "$API_BASE/route/smart" -H 'Content-Type: application/json' -d @data/payloads/smart_override.json)"
emit "$(printf '%s' "$RAW" | $FMT --type smart 2>&1)"
if echo "$RAW" | jq -e '.selected_model=="econo-mini" and .route_reason=="override_bulk_batch" and .would_have_selected=="premium-max"' >/dev/null 2>&1; then
  verdict 0 "override pinned the tier, bypassing what payload routing would pick" "" ""
  LO_EO1d+=("Step 4: an override deterministically bypasses payload routing (premium→econo-mini)")
else
  verdict 1 "override did not bypass payload routing as expected" \
    "Check OVERRIDE_RULES and smart_decision() in app/routing/payload.py — the same complex prompt with request_class=bulk_batch must be pinned to econo-mini." \
    "POST /route/smart with data/payloads/smart_override.json must return econo-mini, override_bulk_batch, would_have_selected=premium-max. Fix app/routing/payload.py."
fi

# STEP 5 — receipts (psql)
step_head "5" "Record each decision's reason in receipts" \
  "Every routed request must persist its tier, cost, and the reason it was chosen." \
  "three rows, all policy_name payload_smart, including the override reason."
show_cmd "docker compose exec -T postgres psql ... route_reason ... ORDER BY created_at DESC LIMIT 3 | python3 scripts/fmt.py --type receipts"
RAW="$(pg_query "$SQL_RECEIPTS")"
emit "$(printf '%s' "$RAW" | $FMT --type receipts 2>&1)"
if echo "$RAW" | jq -s -e 'length==3 and all(.[]; .policy_name=="payload_smart") and (any(.[]; .route_reason=="override_bulk_batch")) and (any(.[]; .route_reason=="payload_complexity_high"))' >/dev/null 2>&1; then
  verdict 0 "three decisions persisted with their route reasons under payload_smart" "" ""
  LO_EO1c+=("Step 5: each payload decision persists its route reason in receipts")
  LO_EO1d+=("Step 5: the override decision is recorded durably alongside payload decisions")
else
  verdict 1 "receipts do not record the smart decisions and their reasons" \
    "Ensure route_smart() writes policy_name=payload_smart and the correct route_reason for each request." \
    "Querying the last 3 receipts must show policy_name=payload_smart on all, with an override_bulk_batch and a payload_complexity_high reason. Fix app/routing/payload.py and app/db/postgres.py."
fi

# STEP 6 — smart-validate
step_head "6" "Validate that every payload lands where its rules dictate" \
  "The routing logic must be deterministic — same input, same tier, every run." \
  "cases 4, all_match true, each canonical payload matching its expected tier."
show_cmd "curl -s \$API_BASE/routing/smart-validate | python3 scripts/fmt.py --type smart-validate"
RAW="$(curl -s "$API_BASE/routing/smart-validate")"
emit "$(printf '%s' "$RAW" | $FMT --type smart-validate 2>&1)"
if echo "$RAW" | jq -e '.all_match==true and .total==4 and (.cases|length==4)' >/dev/null 2>&1; then
  verdict 0 "all four canonical payloads land on their expected tiers" "" ""
  LO_EO1c+=("Step 6: payload routing is deterministic and testable across complexity buckets")
  LO_EO1d+=("Step 6: the override case validates alongside payload cases — provable, repeatable")
else
  verdict 1 "smart-validate did not confirm all cases match" \
    "Check GET /routing/smart-validate and SMART_VALIDATION_CASES in app/providers/registry.py." \
    "GET /routing/smart-validate must return all_match=true over 4 cases. Fix app/main.py routing_smart_validate() and the cases in app/providers/registry.py."
fi

# COVERAGE + SUMMARY
banner "LEARNING OBJECTIVE COVERAGE"
emit "${WHITE}EO1c — Implement payload-based routing that sends each request to the${R}"
emit "${WHITE}       appropriate model tier for its complexity${R}"
if [ "${#LO_EO1c[@]}" -gt 0 ]; then
  for e in "${LO_EO1c[@]}"; do emit "  ${LIME}✔${R} ${GRAY}${e}${R}"; done
else
  emit "  ${PINK}✗ no evidence captured${R}"
fi
blank
emit "${WHITE}EO1d — Contrast weighted and deterministic routing, and apply override${R}"
emit "${WHITE}       rules that intentionally bypass weighted distribution${R}"
if [ "${#LO_EO1d[@]}" -gt 0 ]; then
  for e in "${LO_EO1d[@]}"; do emit "  ${LIME}✔${R} ${GRAY}${e}${R}"; done
else
  emit "  ${PINK}✗ no evidence captured${R}"
fi

banner "SUMMARY"
TOTAL=$((PASS+FAIL))
emit "  ${LIME}PASS: ${PASS}${R}   ${PINK}FAIL: ${FAIL}${R}   ${GRAY}of ${TOTAL} steps${R}"
if [ "$FAIL" = "0" ]; then
  emit "  ${LIME}✔ ALL STEPS PASSED — demo aligns with EO1c and EO1d. Ready to record.${R}"
else
  emit "  ${PINK}✗ ${FAIL} step(s) failed — fix above, reset, and re-run.${R}"
fi
blank
emit "${WHITE}PROMPT TO FIX THIS CHECK (paste into Claude if any step failed):${R}"
emit "${GRAY}\"Run bash module1/scripts/clip5_preflight_check.sh. For every step marked ✗ FAIL,${R}"
emit "${GRAY} read the HOW TO FIX and PROMPT TO FIX lines, open the named source file, correct${R}"
emit "${GRAY} the app so the step's assertion passes, reset with ./scripts/module1-demo-reset.sh,${R}"
emit "${GRAY} and re-run until PASS: 6, FAIL: 0. Do not change the demo steps or the LOs.\"${R}"
blank
emit "  ${GRAY}full readable log written to:${R} ${LGRN}module1/clip5_preflight_log.txt${R}"
exit "$FAIL"
