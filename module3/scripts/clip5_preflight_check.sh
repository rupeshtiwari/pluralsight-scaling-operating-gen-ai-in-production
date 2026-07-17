#!/usr/bin/env bash
# =============================================================================
# Module 3 · Demo — Prove canary promotion, hold, and rollback decisions
# AUTHOR PREFLIGHT: runs every demo step in the SAME order as module3/demo/clip5.md,
# captures each command and its on-screen output, asserts the output proves the
# learning objective (EO4c), and writes a readable log.
#
#   bash module3/scripts/clip5_preflight_check.sh
#
# Defaults target Docker Compose on macOS; override with env vars for a native
# stack: API_BASE
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
LOG="$ROOT/module3/clip5_preflight_log.txt"
: > "$LOG"

API_BASE="${API_BASE:-http://localhost:8000}"
FMT="python3 $ROOT/scripts/fmt.py"

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

banner "MODULE 3 · DEMO — CANARY PROMOTION, HOLD, AND ROLLBACK  (LO: EO4c)"
emit "${GRAY}stack:${R} API=${LGRN}${API_BASE}${R}"
emit "${GRAY}starting the canary and evaluating promotion / rollback ...${R}"
curl -s -X POST "$API_BASE/admin/reset" >/dev/null 2>&1
curl -s -X POST "$API_BASE/lifecycle/canary/run" >/dev/null 2>&1

# STEP 1 — start the canary
step_head "1" "Start the canary" \
  "The canary must shift only 10% of eligible traffic, bounding the blast radius." \
  "50 eligible split 45 production / 5 canary; blast radius bounded true."
show_cmd "curl -s -X POST \$API_BASE/lifecycle/canary/run >/dev/null; curl -s \$API_BASE/lifecycle/canary/start | python3 scripts/fmt.py --type canary-start"
RAW="$(curl -s "$API_BASE/lifecycle/canary/start")"
emit "$(printf '%s' "$RAW" | $FMT --type canary-start 2>&1)"
if echo "$RAW" | jq -e '.canary_pct==10 and .canary_requests==5 and .production_requests==45 and .blast_radius_bounded==true and (.eligible_requests==(.canary_requests+.production_requests))' >/dev/null 2>&1; then
  verdict 0 "the canary takes 10% of eligible traffic (5 of 50), the rest stays on approved — blast radius bounded" "" ""
  LO+=("Step 1: a canary with a controlled 10% blast radius (EO4c)")
else
  verdict 1 "the canary split is wrong" \
    "Check CANARY_PCT / ELIGIBLE_REQUESTS and the start block in app/lifecycle/canary.py." \
    "GET /lifecycle/canary/start must show canary_pct 10, canary_requests 5, production_requests 45, blast_radius_bounded true. Fix app/lifecycle/canary.py."
fi

# STEP 2 — watch the signals
step_head "2" "Watch the canary signals" \
  "The canary must be watched on quality, latency, cost, error rate, and contract compliance." \
  "five signals, each with the canary value beside the approved release value."
show_cmd "curl -s \$API_BASE/lifecycle/canary/watch | python3 scripts/fmt.py --type canary-watch"
RAW="$(curl -s "$API_BASE/lifecycle/canary/watch")"
emit "$(printf '%s' "$RAW" | $FMT --type canary-watch 2>&1)"
if echo "$RAW" | jq -e '(.signals|length==5) and ([.signals[].signal]|(index("quality_score") and index("latency_p95_ms") and index("cost_per_1k_usd") and index("error_rate_pct") and index("contract_compliance_pct"))) and (.signals|all(has("canary") and has("approved")))' >/dev/null 2>&1; then
  verdict 0 "the canary is watched on all five signals, each against the approved release" "" ""
  LO+=("Step 2: the canary is watched on quality, latency, cost, error, and contract (EO4c)")
else
  verdict 1 "the canary watch signals are wrong" \
    "Check the watch block in app/lifecycle/canary.py." \
    "GET /lifecycle/canary/watch must show 5 signals (quality, latency, cost, error, contract) each with canary + approved. Fix app/lifecycle/canary.py."
fi

# STEP 3 — promotion criteria + bounded exposure
step_head "3" "Check the promotion criteria" \
  "Promotion needs every signal within threshold AND a receipt trail proving bounded exposure." \
  "all five signals pass; exposure bounded; eligible to promote true."
show_cmd "curl -s \$API_BASE/lifecycle/canary/criteria | python3 scripts/fmt.py --type canary-criteria"
RAW="$(curl -s "$API_BASE/lifecycle/canary/criteria")"
emit "$(printf '%s' "$RAW" | $FMT --type canary-criteria 2>&1)"
if echo "$RAW" | jq -e '.criteria_met==true and .exposure_bounded==true and .eligible_to_promote==true and (.rows|all(.status=="pass"))' >/dev/null 2>&1; then
  verdict 0 "every signal is within threshold and the receipt trail proves bounded exposure — eligible to promote" "" ""
  LO+=("Step 3: promotion needs criteria met AND provably bounded exposure (EO4c)")
else
  verdict 1 "the promotion criteria did not pass" \
    "Check the criteria block and CANARY_HEALTHY in app/lifecycle/canary.py." \
    "GET /lifecycle/canary/criteria must show criteria_met true, exposure_bounded true, eligible_to_promote true, all rows pass. Fix app/lifecycle/canary.py."
fi

# STEP 4 — promote decision
step_head "4" "Promote the healthy canary" \
  "A healthy canary must be promoted on a staged ramp, each stage still watched." \
  "decision PROMOTE with a 10 -> 25 -> 50 -> 100% ramp plan."
show_cmd "curl -s \$API_BASE/lifecycle/canary/promote | python3 scripts/fmt.py --type canary-promote"
RAW="$(curl -s "$API_BASE/lifecycle/canary/promote")"
emit "$(printf '%s' "$RAW" | $FMT --type canary-promote 2>&1)"
if echo "$RAW" | jq -e '.decision=="PROMOTE" and .criteria_met==true and .exposure_bounded==true and (.ramp_plan_pct|length>=2)' >/dev/null 2>&1; then
  verdict 0 "the healthy canary is promoted on a staged, watched ramp" "" ""
  LO+=("Step 4: a passing canary is promoted with a defined ramp (EO4c)")
else
  verdict 1 "the promote decision is wrong" \
    "Check the promote block in app/lifecycle/canary.py." \
    "GET /lifecycle/canary/promote must show decision PROMOTE, criteria_met true, exposure_bounded true, a ramp plan. Fix app/lifecycle/canary.py."
fi

# STEP 5 — hold / rollback decision
step_head "5" "Hold and roll back the degraded canary" \
  "A breached signal must roll the canary back and return production to the approved release." \
  "decision ROLLBACK, signals breached, active release rel-2026.06, canary exposure 0 after."
show_cmd "curl -s \$API_BASE/lifecycle/canary/rollback | python3 scripts/fmt.py --type canary-rollback"
RAW="$(curl -s "$API_BASE/lifecycle/canary/rollback")"
emit "$(printf '%s' "$RAW" | $FMT --type canary-rollback 2>&1)"
if echo "$RAW" | jq -e '.decision=="ROLLBACK" and .active_release_after=="rel-2026.06" and .canary_exposure_after_pct==0 and .affected_pct==10 and ([.breaches[]]|(index("quality_score") and index("latency_p95_ms") and index("error_rate_pct") and index("contract_compliance_pct")))' >/dev/null 2>&1; then
  verdict 0 "a breached signal rolls the canary back; production returns to approved, only the 10% slice was exposed" "" ""
  LO+=("Step 5: a breach holds/rolls back the canary, returning production to approved (EO4c)")
else
  verdict 1 "the rollback decision is wrong" \
    "Check the rollback block and CANARY_DEGRADED in app/lifecycle/canary.py." \
    "GET /lifecycle/canary/rollback must show decision ROLLBACK, active_release_after rel-2026.06, canary_exposure_after_pct 0, affected_pct 10, breaches on quality/latency/error/contract. Fix app/lifecycle/canary.py."
fi

# STEP 6 — reconcile after rollback
step_head "6" "Reconcile after rollback" \
  "Production must be provably on the approved release with zero canary exposure and a bounded blast radius." \
  "disposition CONFIRMED: active matches approved, canary exposure 0, blast radius <= 10%."
show_cmd "curl -s \$API_BASE/lifecycle/canary/reconcile | python3 scripts/fmt.py --type canary-reconcile"
RAW="$(curl -s "$API_BASE/lifecycle/canary/reconcile")"
emit "$(printf '%s' "$RAW" | $FMT --type canary-reconcile 2>&1)"
if echo "$RAW" | jq -e '.disposition=="CONFIRMED" and .active_matches_approved==true and .canary_exposure_pct==0 and .blast_radius_bounded==true and (.active_release=="rel-2026.06")' >/dev/null 2>&1; then
  verdict 0 "production is provably on the approved release, canary exposure zero, blast radius bounded throughout" "" ""
  LO+=("Step 6: production returns to the approved release after rollback, provably (EO4c)")
else
  verdict 1 "the reconcile did not confirm the approved state" \
    "Check the reconcile block in app/lifecycle/canary.py." \
    "GET /lifecycle/canary/reconcile must return disposition CONFIRMED, active_matches_approved true, canary_exposure_pct 0, blast_radius_bounded true, active_release rel-2026.06. Fix app/lifecycle/canary.py."
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
emit "  ${GRAY}full readable log written to:${R} ${LGRN}module3/clip5_preflight_log.txt${R}"
exit "$FAIL"
