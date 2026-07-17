#!/usr/bin/env bash
# =============================================================================
# Module 3 · Demo — Run readiness audit and finalize operational runbook proof
# AUTHOR PREFLIGHT: runs every demo step in the SAME order as module3/demo/clip6.md,
# captures each command and its on-screen output, asserts the output proves the
# learning objectives (EO4d, TO5, EO5a-d), and writes a readable log.
#
#   bash module3/scripts/clip6_preflight_check.sh
#
# Defaults target Docker Compose on macOS; override with env vars for a native
# stack: API_BASE
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
LOG="$ROOT/module3/clip6_preflight_log.txt"
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

banner "MODULE 3 · DEMO — READINESS AUDIT AND OPERATIONAL RUNBOOK  (LO: EO4d, TO5, EO5a-d)"
emit "${GRAY}stack:${R} API=${LGRN}${API_BASE}${R}"
emit "${GRAY}building the readiness audit, runbook, and maturity decision ...${R}"
curl -s -X POST "$API_BASE/admin/reset" >/dev/null 2>&1
curl -s -X POST "$API_BASE/lifecycle/readiness/run" >/dev/null 2>&1

# STEP 1 — deprecation migration
step_head "1" "Migrate off the deprecated model" \
  "A deprecated model must route through a replacement adapter with compatibility receipts and no disruption." \
  "deprecated -> replacement, four compatibility checks pass, disposition MIGRATED."
show_cmd "curl -s -X POST \$API_BASE/lifecycle/readiness/run >/dev/null; curl -s \$API_BASE/lifecycle/readiness/deprecation | python3 scripts/fmt.py --type readiness-deprecation"
RAW="$(curl -s "$API_BASE/lifecycle/readiness/deprecation")"
emit "$(printf '%s' "$RAW" | $FMT --type readiness-deprecation 2>&1)"
if echo "$RAW" | jq -e '.disposition=="MIGRATED" and .disruption=="none" and (.compatibility|length>=3) and (.compatibility|all(.status=="pass")) and has("replacement_model")' >/dev/null 2>&1; then
  verdict 0 "deprecated traffic routes to the replacement with compatibility receipts and zero disruption" "" ""
  LO+=("Step 1: manage an upstream deprecation with minimal disruption (EO4d)")
else
  verdict 1 "the deprecation migration is wrong" \
    "Check the deprecation block in app/lifecycle/readiness.py." \
    "GET /lifecycle/readiness/deprecation must show disposition MIGRATED, disruption none, all compatibility checks pass, a replacement_model. Fix app/lifecycle/readiness.py."
fi

# STEP 2 — readiness audit
step_head "2" "Run the production readiness audit" \
  "The audit must score scalability, observability, security, cost efficiency, and reliability." \
  "five dimensions scored; four ready, security a gap; overall 17/20."
show_cmd "curl -s \$API_BASE/lifecycle/readiness/audit | python3 scripts/fmt.py --type readiness-audit"
RAW="$(curl -s "$API_BASE/lifecycle/readiness/audit")"
emit "$(printf '%s' "$RAW" | $FMT --type readiness-audit 2>&1)"
if echo "$RAW" | jq -e '(.rows|length==5) and ([.rows[].dimension]|(index("scalability") and index("observability") and index("security") and index("cost_efficiency") and index("reliability"))) and ([.gaps[]]|index("security"))' >/dev/null 2>&1; then
  verdict 0 "the audit scores all five readiness dimensions and names the open gap (security)" "" ""
  LO+=("Step 2: evaluate architecture against readiness criteria (EO5a)")
else
  verdict 1 "the readiness audit is wrong" \
    "Check the audit block in app/lifecycle/readiness.py." \
    "GET /lifecycle/readiness/audit must score scalability, observability, security, cost_efficiency, reliability, with security a gap. Fix app/lifecycle/readiness.py."
fi

# STEP 3 — deployment decision
step_head "3" "Choose the deployment pattern" \
  "The audit must lead to a deployment decision that fits the workload's latency and throughput." \
  "containers recommended for steady 10 RPS where cold start is unacceptable, with reasons."
show_cmd "curl -s \$API_BASE/lifecycle/readiness/decision | python3 scripts/fmt.py --type readiness-decision"
RAW="$(curl -s "$API_BASE/lifecycle/readiness/decision")"
emit "$(printf '%s' "$RAW" | $FMT --type readiness-decision 2>&1)"
if echo "$RAW" | jq -e '.recommended_pattern=="containers" and (.reasons|length>=3) and (.workload|test("RPS"))' >/dev/null 2>&1; then
  verdict 0 "the workload profile leads to containers, with cold-start and cost reasons stated" "" ""
  LO+=("Step 3: the readiness audit drives a deployment decision (EO5a, EO5b)")
else
  verdict 1 "the deployment decision is wrong" \
    "Check the decision block in app/lifecycle/readiness.py." \
    "GET /lifecycle/readiness/decision must recommend containers with a workload profile and >=3 reasons. Fix app/lifecycle/readiness.py."
fi

# STEP 4 — pattern comparison
step_head "4" "Compare the deployment patterns" \
  "Serverless, containers, and dedicated GPU must be compared on latency, throughput, warm start, ownership." \
  "three patterns compared; containers chosen, serverless and dedicated GPU ruled out."
show_cmd "curl -s \$API_BASE/lifecycle/readiness/patterns | python3 scripts/fmt.py --type readiness-patterns"
RAW="$(curl -s "$API_BASE/lifecycle/readiness/patterns")"
emit "$(printf '%s' "$RAW" | $FMT --type readiness-patterns 2>&1)"
if echo "$RAW" | jq -e '.chosen=="containers" and (.rows|length==3) and ([.rows[].pattern]|(index("serverless") and index("containers") and index("dedicated_gpu"))) and (.rows|all(has("latency") and has("throughput") and has("warm_start") and has("ownership")))' >/dev/null 2>&1; then
  verdict 0 "all three patterns are compared on the deciding factors; containers is the right-sized choice" "" ""
  LO+=("Step 4: select a cloud-native deployment pattern by latency/throughput (EO5b)")
else
  verdict 1 "the pattern comparison is wrong" \
    "Check the patterns block in app/lifecycle/readiness.py." \
    "GET /lifecycle/readiness/patterns must compare serverless, containers, dedicated_gpu on latency/throughput/warm_start/ownership with containers chosen. Fix app/lifecycle/readiness.py."
fi

# STEP 5 — operational runbook
step_head "5" "Inspect the operational runbook" \
  "The runbook must cover deploy, monitoring thresholds, incident response, rollback, and capacity." \
  "five sections, each with concrete content wired to a real control."
show_cmd "curl -s \$API_BASE/lifecycle/readiness/runbook | python3 scripts/fmt.py --type readiness-runbook"
RAW="$(curl -s "$API_BASE/lifecycle/readiness/runbook")"
emit "$(printf '%s' "$RAW" | $FMT --type readiness-runbook 2>&1)"
if echo "$RAW" | jq -e '.complete==true and (.sections|length==5) and ([.sections[].section]|(index("deploy") and index("monitoring") and index("incident_response") and index("rollback") and index("capacity")))' >/dev/null 2>&1; then
  verdict 0 "the runbook covers deploy, monitoring, incident response, rollback, and capacity" "" ""
  LO+=("Step 5: construct an operational runbook (EO5c)")
else
  verdict 1 "the runbook is incomplete" \
    "Check the runbook block in app/lifecycle/readiness.py." \
    "GET /lifecycle/readiness/runbook must return 5 sections: deploy, monitoring, incident_response, rollback, capacity, complete true. Fix app/lifecycle/readiness.py."
fi

# STEP 6 — maturity decision
step_head "6" "Decide the operational maturity" \
  "The system must be placed on the maturity ladder with evidence and the gaps to the next level." \
  "current managed_production, with evidence and the gaps to scale-ready."
show_cmd "curl -s \$API_BASE/lifecycle/readiness/maturity | python3 scripts/fmt.py --type readiness-maturity"
RAW="$(curl -s "$API_BASE/lifecycle/readiness/maturity")"
emit "$(printf '%s' "$RAW" | $FMT --type readiness-maturity 2>&1)"
if echo "$RAW" | jq -e '.current=="managed_production" and .disposition=="MANAGED_PRODUCTION" and ([.levels[]]|(index("prototype") and index("managed_production") and index("scale_ready"))) and (.gap_to_next|length>=1)' >/dev/null 2>&1; then
  verdict 0 "the system is placed at managed production on evidence, with the gaps to scale-ready named" "" ""
  LO+=("Step 6: identify the operational maturity progression from prototype to scale (EO5d, TO5)")
else
  verdict 1 "the maturity decision is wrong" \
    "Check the maturity block in app/lifecycle/readiness.py." \
    "GET /lifecycle/readiness/maturity must show current managed_production, disposition MANAGED_PRODUCTION, the three levels, and gaps to scale-ready. Fix app/lifecycle/readiness.py."
fi

# COVERAGE + SUMMARY
banner "LEARNING OBJECTIVE COVERAGE"
emit "${WHITE}EO4d, TO5, EO5a-d — Migrate off a deprecated model, audit readiness across${R}"
emit "${WHITE}       five dimensions, choose a deployment pattern, finalize the operational${R}"
emit "${WHITE}       runbook, and decide the operational maturity on the evidence.${R}"
if [ "${#LO[@]}" -gt 0 ]; then for e in "${LO[@]}"; do emit "  ${LIME}✔${R} ${GRAY}${e}${R}"; done; else emit "  ${PINK}✗ no evidence captured${R}"; fi

banner "SUMMARY"
TOTAL=$((PASS+FAIL))
emit "  ${LIME}PASS: ${PASS}${R}   ${PINK}FAIL: ${FAIL}${R}   ${GRAY}of ${TOTAL} steps${R}"
if [ "$FAIL" = "0" ]; then
  emit "  ${LIME}✔ ALL STEPS PASSED — demo aligns with EO4d, TO5, EO5a-d. Ready to record.${R}"
else
  emit "  ${PINK}✗ ${FAIL} step(s) failed — fix above, reset, and re-run.${R}"
fi
blank
emit "  ${GRAY}full readable log written to:${R} ${LGRN}module3/clip6_preflight_log.txt${R}"
exit "$FAIL"
