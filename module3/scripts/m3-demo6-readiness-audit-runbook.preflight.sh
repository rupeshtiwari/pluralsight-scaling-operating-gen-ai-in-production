#!/usr/bin/env bash
# =============================================================================
# Module 3 · Demo — Run readiness audit and finalize operational runbook proof
# AUTHOR PREFLIGHT: runs every demo step in the SAME order as module3/demo/m3-demo6-readiness-audit-runbook.md,
# captures each command and its on-screen output, asserts the output proves the
# learning objectives (EO4d, TO5, EO5a-d), and writes a readable log.
#
#   bash module3/scripts/m3-demo6-readiness-audit-runbook.preflight.sh
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
LOG="$ROOT/preflight-logs/m3-demo6-readiness-audit-runbook.log"
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
    emit "${GRAY}  do NOT edit app/lifecycle/readiness.py. Start the stack, then re-run:${R}"
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

# Emit a TRANSPORT failure verdict — points at the stack, never at readiness.py.
transport_fail() {  # $1 = path(s) that failed
  verdict 1 "TRANSPORT — could not read $1 with HTTP 200 (service down or route missing)" \
    "Confirm the stack is up: curl \$API_BASE/health must be 200 and curl \$API_BASE/openapi.json must list /lifecycle/readiness/*." \
    "Bring up FastAPI/Redis/Postgres (bash module3/scripts/demo_up.sh) and re-run. This is a service/transport failure — do NOT edit app/lifecycle/readiness.py."
}

banner "MODULE 3 · DEMO — READINESS AUDIT AND OPERATIONAL RUNBOOK  (LO: EO4d, TO5, EO5a-d)"
emit "${GRAY}stack:${R} API=${LGRN}${API_BASE}${R}"
require_stack
emit "${GRAY}building the readiness audit, runbook, and maturity decision ...${R}"
curl -s -X POST "$API_BASE/admin/reset" >/dev/null 2>&1
SEED_CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API_BASE/lifecycle/readiness/run" 2>/dev/null)
if [ "$SEED_CODE" != "200" ]; then
  emit "${PINK}✗ SEEDING FAILED — POST ${API_BASE}/lifecycle/readiness/run returned HTTP ${SEED_CODE:-000}.${R}"
  emit "${GRAY}  No lifecycle state was built, so every downstream read would be empty. This is a${R}"
  emit "${GRAY}  routing/transport failure, not a logic bug — do NOT edit app/lifecycle/readiness.py.${R}"
  exit 2
fi

# STEP 1 — deprecation migration
step_head "1" "Migrate off the deprecated model" \
  "A deprecated model must route through a replacement adapter with a concrete compatibility receipt (id + routed identity) proving the swap, and no observed disruption." \
  "deprecated -> replacement, a named compatibility receipt (dep-0012) with the routed model identity and four checks pass, disposition MIGRATED."
show_cmd "curl -s -X POST \$API_BASE/lifecycle/readiness/run >/dev/null; curl -s \$API_BASE/lifecycle/readiness/deprecation | python3 scripts/fmt.py --type readiness-deprecation"
get_json "/lifecycle/readiness/deprecation" && RAW="$GET_BODY" || RAW=""
if [ -z "$RAW" ]; then
  transport_fail "/lifecycle/readiness/deprecation"
else
  emit "$(printf '%s' "$RAW" | $FMT --type readiness-deprecation 2>&1)"
  if echo "$RAW" | jq -e '.disposition=="MIGRATED" and .disruption=="none" and (.compatibility|length>=3) and (.compatibility|all(.status=="pass")) and has("replacement_model") and has("deprecated_model") and (.receipt_id|test("dep-"))' >/dev/null 2>&1; then
    verdict 0 "deprecated traffic routes to the replacement behind a named compatibility receipt (dep-0012, deprecated->replacement identity, four checks pass); no disruption observed across the 12 migrated requests" "" ""
    LO+=("Step 1: manage an upstream deprecation with a receipt-backed migration (EO4d)")
  else
    verdict 1 "the deprecation migration is wrong" \
      "Check the deprecation block in app/lifecycle/readiness.py." \
      "GET /lifecycle/readiness/deprecation must show disposition MIGRATED, disruption none, a receipt_id (dep-...), deprecated_model and replacement_model, all compatibility checks pass. Fix app/lifecycle/readiness.py."
  fi
fi

# STEP 2 — readiness audit
step_head "2" "Run the production readiness audit" \
  "The audit must score scalability, observability, security, cost efficiency, and reliability." \
  "five dimensions scored; four ready, security a gap; overall 17/20."
show_cmd "curl -s \$API_BASE/lifecycle/readiness/audit | python3 scripts/fmt.py --type readiness-audit"
get_json "/lifecycle/readiness/audit" && RAW="$GET_BODY" || RAW=""
if [ -z "$RAW" ]; then
  transport_fail "/lifecycle/readiness/audit"
else
  emit "$(printf '%s' "$RAW" | $FMT --type readiness-audit 2>&1)"
  if echo "$RAW" | jq -e '(.rows|length==5) and ([.rows[].dimension]|(index("scalability") and index("observability") and index("security") and index("cost_efficiency") and index("reliability"))) and ([.gaps[]]|index("security"))' >/dev/null 2>&1; then
    verdict 0 "the audit scores all five readiness dimensions and names the open gap (security)" "" ""
    LO+=("Step 2: evaluate architecture against readiness criteria (EO5a)")
  else
    verdict 1 "the readiness audit is wrong" \
      "Check the audit block in app/lifecycle/readiness.py." \
      "GET /lifecycle/readiness/audit must score scalability, observability, security, cost_efficiency, reliability, with security a gap. Fix app/lifecycle/readiness.py."
  fi
fi

# STEP 3 — workload profile evidence -> derived decision + pattern comparison
step_head "3" "Read the workload profile, derive the deployment decision, and compare the alternatives" \
  "A workload profile (steady ~10 RPS, a latency target, a cold-start penalty) must be shown as evidence, the deployment decision must be DERIVED from it, and serverless, containers, and dedicated GPU must be compared on latency, throughput, warm start, ownership." \
  "workload signals with steady ~10 RPS, latency-sensitive, cold starts unacceptable; then a derived recommendation of containers with number-backed reasons; then three patterns compared, containers chosen."
show_cmd "curl -s \$API_BASE/lifecycle/readiness/workload | python3 scripts/fmt.py --type readiness-workload"
get_json "/lifecycle/readiness/workload" && RAW_WL="$GET_BODY" || RAW_WL=""
[ -n "$RAW_WL" ] && emit "$(printf '%s' "$RAW_WL" | $FMT --type readiness-workload 2>&1)"
show_cmd "curl -s \$API_BASE/lifecycle/readiness/decision | python3 scripts/fmt.py --type readiness-decision"
get_json "/lifecycle/readiness/decision" && RAW_DEC="$GET_BODY" || RAW_DEC=""
[ -n "$RAW_DEC" ] && emit "$(printf '%s' "$RAW_DEC" | $FMT --type readiness-decision 2>&1)"
show_cmd "curl -s \$API_BASE/lifecycle/readiness/patterns | python3 scripts/fmt.py --type readiness-patterns"
get_json "/lifecycle/readiness/patterns" && RAW_PAT="$GET_BODY" || RAW_PAT=""
[ -n "$RAW_PAT" ] && emit "$(printf '%s' "$RAW_PAT" | $FMT --type readiness-patterns 2>&1)"
if [ -z "$RAW_WL" ] || [ -z "$RAW_DEC" ] || [ -z "$RAW_PAT" ]; then
  transport_fail "/lifecycle/readiness/workload, /decision or /patterns"
else
  WL_OK=1; DEC_OK=1; PAT_OK=1
  # The workload must be concrete evidence: ~10 RPS, latency-sensitive, cold starts intolerable.
  echo "$RAW_WL" | jq -e '.measured_rps>=8 and .measured_rps<=12 and .latency_sensitive==true and .cold_start_tolerable==false and (.signals|length==3) and .latency_target_ms>0 and .cold_start_penalty_ms>.latency_target_ms' >/dev/null 2>&1 || WL_OK=0
  # The decision must be DERIVED from the workload (not a bare label).
  echo "$RAW_DEC" | jq -e '.recommended_pattern=="containers" and (.reasons|length>=3) and (.workload|test("RPS")) and (.derived_from|test("workload"))' >/dev/null 2>&1 || DEC_OK=0
  echo "$RAW_PAT" | jq -e '.chosen=="containers" and (.rows|length==3) and ([.rows[].pattern]|(index("serverless") and index("containers") and index("dedicated_gpu"))) and (.rows|all(has("latency") and has("throughput") and has("warm_start") and has("ownership")))' >/dev/null 2>&1 || PAT_OK=0
  if [ "$WL_OK" = "1" ] && [ "$DEC_OK" = "1" ] && [ "$PAT_OK" = "1" ]; then
    verdict 0 "a workload profile (steady ~10 RPS, latency-sensitive, cold-start penalty > deployment target) derives the containers recommendation with number-backed reasons, and all three patterns are compared on the deciding factors" "" ""
    LO+=("Step 3: a workload profile drives a derived deployment decision (EO5a, EO5b)")
    LO+=("Step 3: select a cloud-native deployment pattern by latency/throughput (EO5b)")
  else
    verdict 1 "the workload evidence, the derived decision, or the pattern comparison is wrong" \
      "Check the workload, decision, and patterns blocks in app/lifecycle/readiness.py." \
      "GET /lifecycle/readiness/workload must show measured_rps ~10, latency_sensitive true, cold_start_tolerable false, 3 signals, cold_start_penalty_ms > latency_target_ms; GET /lifecycle/readiness/decision must recommend containers with derived_from referencing the workload and >=3 reasons; GET /lifecycle/readiness/patterns must compare serverless, containers, dedicated_gpu on latency/throughput/warm_start/ownership with containers chosen. Fix app/lifecycle/readiness.py."
  fi
fi

# STEP 4 — runbook with actionable operator controls + derived maturity decision
step_head "4" "Inspect the operational runbook controls and decide the operational maturity" \
  "The runbook must cover deploy, monitoring, incident response, rollback, and capacity AND expose at least two concrete operator controls as trigger -> action rules (one scaling trigger, one paging trigger); the maturity level must be DERIVED from the audit evidence with the gaps named." \
  "five sections plus >=2 operator controls (a scale trigger and a paging trigger); then current managed_production derived from the audit, with the gaps to scale-ready."
show_cmd "curl -s \$API_BASE/lifecycle/readiness/runbook | python3 scripts/fmt.py --type readiness-runbook"
get_json "/lifecycle/readiness/runbook" && RAW_RUN="$GET_BODY" || RAW_RUN=""
[ -n "$RAW_RUN" ] && emit "$(printf '%s' "$RAW_RUN" | $FMT --type readiness-runbook 2>&1)"
show_cmd "curl -s \$API_BASE/lifecycle/readiness/maturity | python3 scripts/fmt.py --type readiness-maturity"
get_json "/lifecycle/readiness/maturity" && RAW_MAT="$GET_BODY" || RAW_MAT=""
[ -n "$RAW_MAT" ] && emit "$(printf '%s' "$RAW_MAT" | $FMT --type readiness-maturity 2>&1)"
if [ -z "$RAW_RUN" ] || [ -z "$RAW_MAT" ]; then
  transport_fail "/lifecycle/readiness/runbook or /maturity"
else
  RUN_OK=1; MAT_OK=1
  # Sections present AND >=2 actionable controls: at least one scale trigger and one page trigger.
  echo "$RAW_RUN" | jq -e '.complete==true and (.sections|length==5) and ([.sections[].section]|(index("deploy") and index("monitoring") and index("incident_response") and index("rollback") and index("capacity"))) and (.controls|length>=2) and (.controls|all(has("trigger") and has("action"))) and ([.controls[].action]|any(test("scale"))) and ([.controls[].action]|any(test("page")))' >/dev/null 2>&1 || RUN_OK=0
  # Maturity must be DERIVED (references the audit) and name the audit gap among the gaps.
  echo "$RAW_MAT" | jq -e '.current=="managed_production" and .disposition=="MANAGED_PRODUCTION" and ([.levels[]]|(index("prototype") and index("managed_production") and index("scale_ready"))) and (.gap_to_next|length>=1) and (.derived_from|test("audit")) and ([.gap_to_next[]]|any(test("audit")))' >/dev/null 2>&1 || MAT_OK=0
  if [ "$RUN_OK" = "1" ] && [ "$MAT_OK" = "1" ]; then
    verdict 0 "the runbook covers all five sections and exposes actionable operator controls (a scale trigger and a paging trigger), and the maturity level is derived from the audit — managed production, one open audit gap short of scale-ready" "" ""
    LO+=("Step 4: an operational runbook with executable trigger->action controls (EO5c)")
    LO+=("Step 4: maturity derived from evidence, prototype to scale (EO5d, TO5)")
  else
    verdict 1 "the runbook controls are missing/incomplete or the maturity decision is not evidence-derived" \
      "Check the runbook controls and the maturity derivation in app/lifecycle/readiness.py." \
      "GET /lifecycle/readiness/runbook must return 5 sections AND a controls[] list (>=2) with trigger+action, including a scale action and a page action; GET /lifecycle/readiness/maturity must show current managed_production, disposition MANAGED_PRODUCTION, the three levels, derived_from referencing the audit, and the audit gap among gap_to_next. Fix app/lifecycle/readiness.py."
  fi
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
emit "  ${GRAY}full readable log written to:${R} ${LGRN}preflight-logs/m3-demo6-readiness-audit-runbook.log${R}"
exit "$FAIL"
