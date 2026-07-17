#!/usr/bin/env bash
# =============================================================================
# Module 3 · Demo — Validate model updates against quality baselines
# AUTHOR PREFLIGHT: runs every demo step in the SAME order as module3/demo/clip3.md,
# captures each command and its on-screen output, asserts the output proves the
# learning objective (EO4b), and writes a readable log.
#
#   bash module3/scripts/clip3_preflight_check.sh
#
# Defaults target Docker Compose on macOS; override with env vars for a native
# stack: API_BASE, PYTEST (the command that runs pytest, default "python3 -m pytest")
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
LOG="$ROOT/module3/clip3_preflight_log.txt"
: > "$LOG"

API_BASE="${API_BASE:-http://localhost:8000}"
PYTEST="${PYTEST:-python3 -m pytest}"
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

banner "MODULE 3 · DEMO — VALIDATE MODEL UPDATES AGAINST QUALITY BASELINES  (LO: EO4b)"
emit "${GRAY}stack:${R} API=${LGRN}${API_BASE}${R}"
emit "${GRAY}evaluating candidates against the baseline gate ...${R}"
curl -s -X POST "$API_BASE/admin/reset" >/dev/null 2>&1
curl -s -X POST "$API_BASE/lifecycle/validation/run" >/dev/null 2>&1

# STEP 1 — run the real Pytest baseline gate
step_head "1" "Run the baseline gate (Pytest)" \
  "The gate must be a real automated test, not a claim — run the Pytest baseline suite." \
  "the Pytest suite passes, and the gate marks one candidate eligible and one blocked."
show_cmd "$PYTEST tests/baseline -q  &&  curl -s \$API_BASE/lifecycle/validation/gate | python3 scripts/fmt.py --type validation-gate"
PYOUT="$($PYTEST tests/baseline -q 2>&1)"; PYRC=$?
emit "${GRAY}${PYOUT}${R}"
RAW="$(curl -s "$API_BASE/lifecycle/validation/gate")"
emit "$(printf '%s' "$RAW" | $FMT --type validation-gate 2>&1)"
if [ "$PYRC" = "0" ] && echo "$RAW" | jq -e '.checks==10 and .gate_enforced==true and ([.candidates[].eligible]|(index(true) and index(false)))' >/dev/null 2>&1; then
  verdict 0 "the Pytest baseline suite passes and the gate marks one candidate eligible, one blocked" "" ""
  LO+=("Step 1: a real Pytest baseline gate enforces the promotion criteria (EO4b)")
else
  verdict 1 "the Pytest gate did not pass or the gate summary is wrong (pytest rc=$PYRC)" \
    "Run '$PYTEST tests/baseline -q' and check app/lifecycle/validation.py." \
    "pytest tests/baseline must pass and GET /lifecycle/validation/gate must show checks=10, gate_enforced true, one eligible + one blocked candidate. Fix app/lifecycle/validation.py or tests/baseline."
fi

# STEP 2 — baseline thresholds
step_head "2" "Inspect the baseline thresholds" \
  "The baseline must cover quality, latency, cost, failure rate, and contract compliance." \
  "five dimensions, each with its objective (a min floor or a max ceiling)."
show_cmd "curl -s \$API_BASE/lifecycle/validation/baseline | python3 scripts/fmt.py --type validation-baseline"
RAW="$(curl -s "$API_BASE/lifecycle/validation/baseline")"
emit "$(printf '%s' "$RAW" | $FMT --type validation-baseline 2>&1)"
if echo "$RAW" | jq -e '(.rows|length==5) and ([.rows[].dimension]|(index("quality_score") and index("latency_p95_ms") and index("cost_per_1k_usd") and index("failure_rate_pct") and index("contract_compliance_pct")))' >/dev/null 2>&1; then
  verdict 0 "the baseline covers quality, latency, cost, failure rate, and contract compliance" "" ""
  LO+=("Step 2: the baseline spans quality and performance dimensions (EO4b)")
else
  verdict 1 "the baseline dimensions are wrong" \
    "Check BASELINE in app/lifecycle/validation.py." \
    "GET /lifecycle/validation/baseline must list 5 dimensions: quality_score, latency_p95_ms, cost_per_1k_usd, failure_rate_pct, contract_compliance_pct. Fix app/lifecycle/validation.py."
fi

# STEP 3 — passing candidate
step_head "3" "Validate the passing candidate" \
  "A candidate within every threshold must be eligible for promotion." \
  "every dimension passes; the candidate is eligible."
show_cmd "curl -s \$API_BASE/lifecycle/validation/pass | python3 scripts/fmt.py --type validation-candidate"
RAW="$(curl -s "$API_BASE/lifecycle/validation/pass")"
emit "$(printf '%s' "$RAW" | $FMT --type validation-candidate 2>&1)"
if echo "$RAW" | jq -e '.eligible==true and (.breaches|length==0) and (.rows|all(.status=="pass"))' >/dev/null 2>&1; then
  verdict 0 "the passing candidate clears every baseline dimension and is eligible" "" ""
  LO+=("Step 3: a candidate within thresholds is eligible for promotion (EO4b)")
else
  verdict 1 "the passing candidate was not eligible" \
    "Check the passing candidate metrics in app/lifecycle/validation.py." \
    "GET /lifecycle/validation/pass must show eligible true, no breaches, all rows pass. Fix app/lifecycle/validation.py."
fi

# STEP 4 — failing candidate
step_head "4" "Validate the failing candidate" \
  "A candidate that drifts on any dimension must be blocked, with the breaches named." \
  "quality, latency, failure rate, and contract breach; the candidate is blocked."
show_cmd "curl -s \$API_BASE/lifecycle/validation/fail | python3 scripts/fmt.py --type validation-candidate"
RAW="$(curl -s "$API_BASE/lifecycle/validation/fail")"
emit "$(printf '%s' "$RAW" | $FMT --type validation-candidate 2>&1)"
if echo "$RAW" | jq -e '.eligible==false and ([.breaches[]]|(index("quality_score") and index("latency_p95_ms") and index("failure_rate_pct") and index("contract_compliance_pct")))' >/dev/null 2>&1; then
  verdict 0 "the failing candidate is blocked on quality, latency, failure rate, and contract drift" "" ""
  LO+=("Step 4: a candidate that breaches any dimension is blocked (EO4b)")
else
  verdict 1 "the failing candidate was not blocked as expected" \
    "Check the failing candidate metrics in app/lifecycle/validation.py." \
    "GET /lifecycle/validation/fail must show eligible false with breaches quality_score, latency_p95_ms, failure_rate_pct, contract_compliance_pct. Fix app/lifecycle/validation.py."
fi

# STEP 5 — release decision
step_head "5" "Record the release decision" \
  "The decision must promote the passing candidate, block the failing one, and make neither the default." \
  "promote for the passing candidate, blocked for the failing one; becomes_default false for both."
show_cmd "curl -s \$API_BASE/lifecycle/validation/decision | python3 scripts/fmt.py --type validation-decision"
RAW="$(curl -s "$API_BASE/lifecycle/validation/decision")"
emit "$(printf '%s' "$RAW" | $FMT --type validation-decision 2>&1)"
if echo "$RAW" | jq -e '(.decisions|length==2) and (.decisions|all(.becomes_default==false)) and (.decisions[]|select(.candidate=="econo-fast@2026-07").decision=="blocked") and (.decisions[]|select(.candidate=="balanced-std@2026-07").eligible==true)' >/dev/null 2>&1; then
  verdict 0 "the passing candidate is promoted (behind a canary), the failing one blocked; neither is default yet" "" ""
  LO+=("Step 5: a candidate cannot become the default without passing the baseline (EO4b)")
else
  verdict 1 "the release decision is wrong" \
    "Check the decisions block in app/lifecycle/validation.py." \
    "GET /lifecycle/validation/decision must show 2 decisions, both becomes_default false, failing candidate blocked, passing candidate eligible. Fix app/lifecycle/validation.py."
fi

# STEP 6 — reconcile
step_head "6" "Reconcile the release state" \
  "The default must stay on the approved model, with only baseline-passing candidates eligible." \
  "disposition CONFIRMED: default unchanged, eligible and blocked candidates listed, gate enforced."
show_cmd "curl -s \$API_BASE/lifecycle/validation/reconcile | python3 scripts/fmt.py --type validation-reconcile"
RAW="$(curl -s "$API_BASE/lifecycle/validation/reconcile")"
emit "$(printf '%s' "$RAW" | $FMT --type validation-reconcile 2>&1)"
if echo "$RAW" | jq -e '.disposition=="CONFIRMED" and .default_unchanged==true and .gate_enforced==true and ([.eligible_candidates[]]|index("balanced-std@2026-07")) and ([.blocked_candidates[]]|index("econo-fast@2026-07"))' >/dev/null 2>&1; then
  verdict 0 "the default stays on the approved model; only the baseline-passing candidate is eligible" "" ""
  LO+=("Step 6: the release state reconciles with the gate enforced (EO4b)")
else
  verdict 1 "the release state did not reconcile" \
    "Check the reconcile block in app/lifecycle/validation.py." \
    "GET /lifecycle/validation/reconcile must return disposition CONFIRMED, default_unchanged true, gate_enforced true, eligible/blocked lists correct. Fix app/lifecycle/validation.py."
fi

# COVERAGE + SUMMARY
banner "LEARNING OBJECTIVE COVERAGE"
emit "${WHITE}EO4b — Gate every candidate model against a quality/performance baseline${R}"
emit "${WHITE}       (quality, latency, cost, failure rate, contract) with a real Pytest${R}"
emit "${WHITE}       suite, so no candidate becomes the default without passing.${R}"
if [ "${#LO[@]}" -gt 0 ]; then for e in "${LO[@]}"; do emit "  ${LIME}✔${R} ${GRAY}${e}${R}"; done; else emit "  ${PINK}✗ no evidence captured${R}"; fi

banner "SUMMARY"
TOTAL=$((PASS+FAIL))
emit "  ${LIME}PASS: ${PASS}${R}   ${PINK}FAIL: ${FAIL}${R}   ${GRAY}of ${TOTAL} steps${R}"
if [ "$FAIL" = "0" ]; then
  emit "  ${LIME}✔ ALL STEPS PASSED — demo aligns with EO4b. Ready to record.${R}"
else
  emit "  ${PINK}✗ ${FAIL} step(s) failed — fix above, reset, and re-run.${R}"
fi
blank
emit "  ${GRAY}full readable log written to:${R} ${LGRN}module3/clip3_preflight_log.txt${R}"
exit "$FAIL"
