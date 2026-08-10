#!/usr/bin/env bash
# =============================================================================
# Module 3 · Demo — Prove canary promotion, hold, and rollback decisions
# AUTHOR PREFLIGHT: runs every demo step in the SAME order as module3/demo/m3-demo5-canary-promotion-rollback.md,
# captures each command and its on-screen output, asserts the output proves the
# learning objective (EO4c), and writes a readable log.
#
#   bash module3/scripts/m3-demo5-canary-promotion-rollback.preflight.sh
#
# Defaults target Docker Compose on macOS; override with env vars for a native
# stack: API_BASE
#
# TRANSPORT SAFETY: this script fails LOUDLY and distinctly when the service is
# unreachable — it never lets a down stack masquerade as a content/logic failure.
# A precondition asserts API_BASE is set and /health is 200 before Step 1, and
# every read is status-gated (HTTP 200) before it is parsed.
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
LOG="$ROOT/preflight-logs/m3-demo5-canary-promotion-rollback.log"
: > "$LOG"

API_BASE="${API_BASE:-http://localhost:8000}"
FMT="python3 $ROOT/scripts/fmt.py"

PINK=$'\033[38;2;255;22;117m'; LIME=$'\033[38;2;2;224;136m'
LGRN=$'\033[38;2;235;239;245m'; BLUE=$'\033[38;2;0;163;255m'
GRAY=$'\033[38;2;88;95;162m'; WHITE=$'\033[1;37m'; R=$'\033[0m'

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

# --- transport gates: never let a down service look like a logic failure ------
# Hard precondition — API_BASE must be set and /health must be 200 before Step 1.
require_stack() {
  if [ -z "${API_BASE:-}" ]; then
    emit "${PINK}✗ PRECONDITION FAILED — API_BASE is empty.${R}"
    emit "${GRAY}  Set it (or use the default http://localhost:8000) and re-run.${R}"
    exit 2
  fi
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' "$API_BASE/health" 2>/dev/null)
  if [ "$code" != "200" ]; then
    emit "${PINK}✗ PRECONDITION FAILED — GET ${API_BASE}/health returned HTTP ${code:-000}.${R}"
    emit "${GRAY}  The service is not reachable. This is a TRANSPORT problem, not a logic bug —${R}"
    emit "${GRAY}  do NOT edit app/lifecycle/canary.py. Start the stack, then re-run:${R}"
    emit "${LGRN}    bash module3/scripts/demo_up.sh${R}"
    exit 2
  fi
  emit "${GRAY}precondition:${R} ${LGRN}${API_BASE}/health${R} ${GRAY}= 200 ✓${R}"
}

# GET a path with a status gate. On 200: sets GET_BODY, returns 0.
# Otherwise: leaves GET_BODY empty and returns 1 (caller emits a TRANSPORT verdict).
GET_BODY=""
get_json() {  # $1 = path
  local resp code
  resp=$(curl -s -w $'\n%{http_code}' "$API_BASE$1" 2>/dev/null)
  code=${resp##*$'\n'}
  GET_BODY=${resp%$'\n'*}
  [ "$code" = "200" ] || { GET_BODY=""; return 1; }
  return 0
}

# Emit a TRANSPORT failure verdict — points at the stack, never at canary.py.
transport_fail() {  # $1 = path(s) that failed
  verdict 1 "TRANSPORT — could not read $1 with HTTP 200 (service down or route missing)" \
    "Confirm the stack is up: curl \$API_BASE/health must be 200 and curl \$API_BASE/openapi.json must list /lifecycle/canary/*." \
    "Bring up FastAPI/Redis/Postgres (bash module3/scripts/demo_up.sh) and re-run. This is a service/transport failure — do NOT edit app/lifecycle/canary.py."
}

banner "MODULE 3 · DEMO — CANARY PROMOTION, HOLD, AND ROLLBACK  (LO: EO4c)"
emit "${GRAY}stack:${R} API=${LGRN}${API_BASE}${R}"
require_stack
emit "${GRAY}starting the canary and evaluating promotion / rollback ...${R}"
curl -s -X POST "$API_BASE/admin/reset" >/dev/null 2>&1
SEED_CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API_BASE/lifecycle/canary/run" 2>/dev/null)
if [ "$SEED_CODE" != "200" ]; then
  emit "${PINK}✗ SEEDING FAILED — POST ${API_BASE}/lifecycle/canary/run returned HTTP ${SEED_CODE:-000}.${R}"
  emit "${GRAY}  No lifecycle state was built, so every downstream read would be empty. This is a${R}"
  emit "${GRAY}  routing/transport failure, not a logic bug — do NOT edit app/lifecycle/canary.py.${R}"
  exit 2
fi

# STEP 1 — start the canary AND watch the signals
step_head "1" "Start the canary and watch its signals" \
  "The canary must shift only 10% of eligible traffic, bounding the blast radius, and be watched on quality, latency, cost, error rate, and contract compliance." \
  "50 eligible split 45 production / 5 canary with blast radius bounded true, then five signals each with the canary value beside the approved release value."
show_cmd "curl -s -X POST \$API_BASE/lifecycle/canary/run >/dev/null; curl -s \$API_BASE/lifecycle/canary/start | python3 scripts/fmt.py --type canary-start"
get_json "/lifecycle/canary/start" && RAW_START="$GET_BODY" || RAW_START=""
[ -n "$RAW_START" ] && emit "$(printf '%s' "$RAW_START" | $FMT --type canary-start 2>&1)"
show_cmd "curl -s \$API_BASE/lifecycle/canary/watch | python3 scripts/fmt.py --type canary-watch"
get_json "/lifecycle/canary/watch" && RAW_WATCH="$GET_BODY" || RAW_WATCH=""
[ -n "$RAW_WATCH" ] && emit "$(printf '%s' "$RAW_WATCH" | $FMT --type canary-watch 2>&1)"
if [ -z "$RAW_START" ] || [ -z "$RAW_WATCH" ]; then
  transport_fail "/lifecycle/canary/start or /watch"
else
  A_OK=1; B_OK=1
  echo "$RAW_START" | jq -e '.canary_pct==10 and .canary_requests==5 and .production_requests==45 and .blast_radius_bounded==true and (.eligible_requests==(.canary_requests+.production_requests))' >/dev/null 2>&1 || A_OK=0
  echo "$RAW_WATCH" | jq -e '(.signals|length==5) and ([.signals[].signal]|(index("quality_score") and index("latency_p95_ms") and index("cost_per_1k_usd") and index("error_rate_pct") and index("contract_compliance_pct"))) and (.signals|all(has("canary") and has("approved")))' >/dev/null 2>&1 || B_OK=0
  if [ "$A_OK" = "1" ] && [ "$B_OK" = "1" ]; then
    verdict 0 "the canary takes 10% of eligible traffic (5 of 50), the rest stays on approved — blast radius bounded — and it is watched on all five signals against the approved release" "" ""
    LO+=("Step 1: a canary with a controlled 10% blast radius (EO4c)")
    LO+=("Step 1: the canary is watched on quality, latency, cost, error, and contract (EO4c)")
  else
    verdict 1 "the canary split or watch signals are wrong" \
      "Check CANARY_PCT / ELIGIBLE_REQUESTS and the start block, and the watch block, in app/lifecycle/canary.py." \
      "GET /lifecycle/canary/start must show canary_pct 10, canary_requests 5, production_requests 45, blast_radius_bounded true; GET /lifecycle/canary/watch must show 5 signals (quality, latency, cost, error, contract) each with canary + approved. Fix app/lifecycle/canary.py."
  fi
fi

# STEP 2 — promotion criteria + bounded exposure
step_head "2" "Check the promotion criteria" \
  "Promotion needs every signal within threshold AND a receipt trail proving bounded exposure." \
  "all five signals pass; exposure bounded; eligible to promote true."
show_cmd "curl -s \$API_BASE/lifecycle/canary/criteria | python3 scripts/fmt.py --type canary-criteria"
get_json "/lifecycle/canary/criteria" && RAW="$GET_BODY" || RAW=""
if [ -z "$RAW" ]; then
  transport_fail "/lifecycle/canary/criteria"
else
  emit "$(printf '%s' "$RAW" | $FMT --type canary-criteria 2>&1)"
  if echo "$RAW" | jq -e '.criteria_met==true and .exposure_bounded==true and .eligible_to_promote==true and (.rows|all(.status=="pass"))' >/dev/null 2>&1; then
    verdict 0 "every signal is within threshold and the receipt trail proves bounded exposure — eligible to promote" "" ""
    LO+=("Step 2: promotion needs criteria met AND provably bounded exposure (EO4c)")
  else
    verdict 1 "the promotion criteria did not pass" \
      "Check the criteria block and CANARY_HEALTHY in app/lifecycle/canary.py." \
      "GET /lifecycle/canary/criteria must show criteria_met true, exposure_bounded true, eligible_to_promote true, all rows pass. Fix app/lifecycle/canary.py."
  fi
fi

# STEP 3 — promote decision AND hold / rollback decision
step_head "3" "Promote the healthy canary and roll back the degraded one" \
  "A healthy canary must be promoted on a staged ramp, each stage still watched, and a breached signal must roll the canary back and return production to the approved release." \
  "decision PROMOTE with a 10 -> 25 -> 50 -> 100% ramp plan, then decision ROLLBACK with signals breached, active release rel-2026.06, canary exposure 0 after."
show_cmd "curl -s \$API_BASE/lifecycle/canary/promote | python3 scripts/fmt.py --type canary-promote"
get_json "/lifecycle/canary/promote" && RAW_PROMOTE="$GET_BODY" || RAW_PROMOTE=""
[ -n "$RAW_PROMOTE" ] && emit "$(printf '%s' "$RAW_PROMOTE" | $FMT --type canary-promote 2>&1)"
show_cmd "curl -s \$API_BASE/lifecycle/canary/rollback | python3 scripts/fmt.py --type canary-rollback"
get_json "/lifecycle/canary/rollback" && RAW_ROLLBACK="$GET_BODY" || RAW_ROLLBACK=""
[ -n "$RAW_ROLLBACK" ] && emit "$(printf '%s' "$RAW_ROLLBACK" | $FMT --type canary-rollback 2>&1)"
if [ -z "$RAW_PROMOTE" ] || [ -z "$RAW_ROLLBACK" ]; then
  transport_fail "/lifecycle/canary/promote or /rollback"
else
  A_OK=1; B_OK=1
  echo "$RAW_PROMOTE" | jq -e '.decision=="PROMOTE" and .criteria_met==true and .exposure_bounded==true and (.ramp_plan_pct|length>=2)' >/dev/null 2>&1 || A_OK=0
  echo "$RAW_ROLLBACK" | jq -e '.decision=="ROLLBACK" and .active_release_after=="rel-2026.06" and .canary_exposure_after_pct==0 and .affected_pct==10 and ([.breaches[]]|(index("quality_score") and index("latency_p95_ms") and index("error_rate_pct") and index("contract_compliance_pct")))' >/dev/null 2>&1 || B_OK=0
  if [ "$A_OK" = "1" ] && [ "$B_OK" = "1" ]; then
    verdict 0 "the healthy canary is promoted on a staged, watched ramp, and a breached signal rolls the canary back; production returns to approved, only the 10% slice was exposed" "" ""
    LO+=("Step 3: a passing canary is promoted with a defined ramp (EO4c)")
    LO+=("Step 3: a breach holds/rolls back the canary, returning production to approved (EO4c)")
  else
    verdict 1 "the promote decision or the rollback decision is wrong" \
      "Check the promote block, and the rollback block and CANARY_DEGRADED, in app/lifecycle/canary.py." \
      "GET /lifecycle/canary/promote must show decision PROMOTE, criteria_met true, exposure_bounded true, a ramp plan; GET /lifecycle/canary/rollback must show decision ROLLBACK, active_release_after rel-2026.06, canary_exposure_after_pct 0, affected_pct 10, breaches on quality/latency/error/contract. Fix app/lifecycle/canary.py."
  fi
fi

# STEP 4 — reconcile after rollback
step_head "4" "Reconcile after rollback" \
  "Production must be provably on the approved release with zero canary exposure and a bounded blast radius." \
  "disposition CONFIRMED: active matches approved, canary exposure 0, blast radius <= 10%."
show_cmd "curl -s \$API_BASE/lifecycle/canary/reconcile | python3 scripts/fmt.py --type canary-reconcile"
get_json "/lifecycle/canary/reconcile" && RAW="$GET_BODY" || RAW=""
if [ -z "$RAW" ]; then
  transport_fail "/lifecycle/canary/reconcile"
else
  emit "$(printf '%s' "$RAW" | $FMT --type canary-reconcile 2>&1)"
  if echo "$RAW" | jq -e '.disposition=="CONFIRMED" and .active_matches_approved==true and .canary_exposure_pct==0 and .blast_radius_bounded==true and (.active_release=="rel-2026.06")' >/dev/null 2>&1; then
    verdict 0 "production is provably on the approved release, canary exposure zero, blast radius bounded throughout" "" ""
    LO+=("Step 4: production returns to the approved release after rollback, provably (EO4c)")
  else
    verdict 1 "the reconcile did not confirm the approved state" \
      "Check the reconcile block in app/lifecycle/canary.py." \
      "GET /lifecycle/canary/reconcile must return disposition CONFIRMED, active_matches_approved true, canary_exposure_pct 0, blast_radius_bounded true, active_release rel-2026.06. Fix app/lifecycle/canary.py."
  fi
fi

# COVERAGE + SUMMARY
banner "LEARNING OBJECTIVE COVERAGE"
emit "${WHITE}EO4c — Shift 10% of traffic to a canary with a bounded blast radius,${R}"
emit "${WHITE}       promote only when criteria pass and exposure is provably bounded,${R}"
emit "${WHITE}       and hold / roll back to the approved release on any breach.${R}"
if [ "${#LO[@]}" -gt 0 ]; then for e in "${LO[@]}"; do emit "  ${LIME}✔${R} ${GRAY}${e}${R}"; done; else emit "  ${PINK}✗ no evidence captured${R}"; fi

banner "SUMMARY"
TOTAL=$((PASS+FAIL))
emit "  ${LIME}PASS: ${PASS}${R}   ${PINK}FAIL: ${FAIL}${R}   ${GRAY}of ${TOTAL} steps${R}"
if [ "$FAIL" = "0" ]; then
  emit "  ${LIME}✔ ALL STEPS PASSED — demo aligns with EO4c. Ready to record.${R}"
else
  emit "  ${PINK}✗ ${FAIL} step(s) failed — fix above, reset, and re-run.${R}"
fi
blank
emit "  ${GRAY}full readable log written to:${R} ${LGRN}preflight-logs/m3-demo5-canary-promotion-rollback.log${R}"
exit "$FAIL"
