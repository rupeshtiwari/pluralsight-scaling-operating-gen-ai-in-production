#!/usr/bin/env bash
# =============================================================================
# Module 2 · Demo — Diagnose latency, quota pressure, cost drift, and quality
# AUTHOR PREFLIGHT: runs every demo step in the SAME order as module2/demo/clip6.md,
# captures each command and its on-screen output, asserts the output proves the
# learning objectives (TO2, EO2e, TO3, EO3a-e), and writes a readable log.
#
#   bash module2/scripts/clip6_preflight_check.sh
#
# Defaults target Docker Compose on macOS; override with env vars for a native
# stack: API_BASE, PGHOST, PGPORT, PGUSER, PGDATABASE, PGPASSWORD
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
LOG="$ROOT/module2/clip6_preflight_log.txt"
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

banner "MODULE 2 · DEMO — DIAGNOSE LATENCY, QUOTA, COST, AND QUALITY  (LO: TO2, EO2e, TO3, EO3a-e)"
emit "${GRAY}stack:${R} API=${LGRN}${API_BASE}${R}"
emit "${GRAY}triggering the controlled incident (one provider fault, four alerts) ...${R}"
curl -s -X POST "$API_BASE/admin/reset" >/dev/null 2>&1
curl -s -X POST "$API_BASE/incident/run" >/dev/null 2>&1

# STEP 1 — alert timeline
step_head "1" "Read the alert timeline" \
  "A simulated incident must surface an ordered alert timeline with a clear first bad signal." \
  "four alerts in fire order; latency fires first, quality pages last."
show_cmd "curl -s -X POST \$API_BASE/incident/run >/dev/null; curl -s \$API_BASE/incident/alerts | python3 scripts/fmt.py --type incident-alerts"
RAW="$(curl -s "$API_BASE/incident/alerts")"
emit "$(printf '%s' "$RAW" | $FMT --type incident-alerts 2>&1)"
if echo "$RAW" | jq -e '(.alerts|length==4) and (.first_signal=="LatencyP95AboveObjective") and ([.alerts[].dimension]|(index("latency") and index("quota") and index("cost") and index("output_quality"))) and ((.alerts[]|select(.dimension=="output_quality").severity)=="page")' >/dev/null 2>&1; then
  verdict 0 "four alerts fire in order; latency is the first signal and the quality breach pages" "" ""
  LO+=("Step 1: a simulated incident surfaces an ordered alert timeline (EO2e, EO3d)")
else
  verdict 1 "the alert timeline is wrong" \
    "Check the alerts block in app/incident/diagnose.py." \
    "GET /incident/alerts after /incident/run must return 4 alerts, first_signal LatencyP95AboveObjective, dimensions latency/quota/cost/output_quality, quality severity page. Fix app/incident/diagnose.py."
fi

# STEP 2 — operator dashboard
step_head "2" "Open the operator dashboard" \
  "The four dimensions must show baseline versus current against each objective, all breached." \
  "latency p95, quota saturation, cost per request, quality pass rate — every panel red."
show_cmd "curl -s \$API_BASE/incident/dashboard | python3 scripts/fmt.py --type incident-dashboard"
RAW="$(curl -s "$API_BASE/incident/dashboard")"
emit "$(printf '%s' "$RAW" | $FMT --type incident-dashboard 2>&1)"
if echo "$RAW" | jq -e '(.panels|length==4) and (.breached==4) and (.panels|all(.status=="breach")) and ([.panels[].dimension]|(index("latency") and index("quota") and index("cost") and index("output_quality")))' >/dev/null 2>&1; then
  verdict 0 "the dashboard shows all four dimensions breached, each baseline vs current vs objective" "" ""
  LO+=("Step 2: an operator dashboard quantifies latency, quota, cost, and quality (TO3, EO3d)")
else
  verdict 1 "the dashboard panels are wrong" \
    "Check the dashboard block in app/incident/diagnose.py." \
    "GET /incident/dashboard must return 4 panels, breached=4, dimensions latency/quota/cost/output_quality, each status breach. Fix app/incident/diagnose.py."
fi

# STEP 3 — isolate latency from the trace
step_head "3" "Isolate the latency from one trace" \
  "The trace must clear queueing, retry, and fallback and pin the latency on the provider call." \
  "provider_call owns ~83% of the trace; queue, retry, fallback are innocent."
show_cmd "curl -s \$API_BASE/incident/isolate | python3 scripts/fmt.py --type incident-isolate"
RAW="$(curl -s "$API_BASE/incident/isolate")"
emit "$(printf '%s' "$RAW" | $FMT --type incident-isolate 2>&1)"
if echo "$RAW" | jq -e '.slowest_span=="provider_call" and .slowest_share_pct>80 and .provider=="balanced-ai" and .provider_status=="degraded_slow" and ((.contributors[]|select(.span=="provider_call").verdict)=="root cause") and ([.contributors[]|select(.span!="provider_call").verdict]|all(.=="innocent")) and (.trace_id|length==32)' >/dev/null 2>&1; then
  verdict 0 "the trace clears queueing/retry/fallback and pins the latency on the degraded provider call" "" ""
  LO+=("Step 3: one trace isolates the latency source across the pipeline (EO3a, EO3e)")
else
  verdict 1 "the isolation did not point at the provider" \
    "Check the isolate block and _incident_stages in app/incident/diagnose.py." \
    "GET /incident/isolate must show slowest_span=provider_call (>80%), provider balanced-ai degraded_slow, provider_call verdict root cause, others innocent, 32-char trace id. Fix app/incident/diagnose.py."
fi

# STEP 4 — quota pressure and shed
step_head "4" "Prove the quota pressure and the shed" \
  "Admission control must shed the excess load with a 429 and a Retry-After, protecting the provider." \
  "40 submitted, 34 accepted, 6 rejected with Retry-After; provider quota_exceeded."
show_cmd "curl -s \$API_BASE/incident/quota | python3 scripts/fmt.py --type incident-quota"
RAW="$(curl -s "$API_BASE/incident/quota")"
emit "$(printf '%s' "$RAW" | $FMT --type incident-quota 2>&1)"
if echo "$RAW" | jq -e '.submitted==40 and .accepted==34 and .rejected_429==6 and .provider_status=="quota_exceeded" and .retry_after_seconds==10 and (.submitted==(.accepted+.rejected_429)) and (.shed_working==true)' >/dev/null 2>&1; then
  verdict 0 "40 submitted = 34 accepted + 6 shed with Retry-After; the provider is held below exhaustion" "" ""
  LO+=("Step 4: admission control sheds quota pressure and protects the provider (TO2, EO2e)")
else
  verdict 1 "the quota shed accounting is wrong" \
    "Check the quota block in app/incident/diagnose.py." \
    "GET /incident/quota must show submitted=40, accepted=34, rejected_429=6, provider_status quota_exceeded, retry_after 10, shed_working true. Fix app/incident/diagnose.py."
fi

# STEP 5 — cost drift to its cause
step_head "5" "Trace the cost drift to its cause" \
  "The cost increase must reconcile exactly to named drivers on the degraded provider." \
  "\$0.0120 -> \$0.0210 per request (+75%), the delta split into retries and fallback overhead."
show_cmd "curl -s \$API_BASE/incident/cost | python3 scripts/fmt.py --type incident-cost"
RAW="$(curl -s "$API_BASE/incident/cost")"
emit "$(printf '%s' "$RAW" | $FMT --type incident-cost 2>&1)"
if echo "$RAW" | jq -e '.reconciles==true and .drift_pct==75.0 and (.current_per_request_usd>.objective_per_request_usd) and (.drivers|length>=2) and (.drivers|all(has("add_per_request_usd")))' >/dev/null 2>&1; then
  verdict 0 "the cost drift reconciles to the cent: retries + fallback overhead account for the full delta" "" ""
  LO+=("Step 5: cost drift ties to model identity, tokens, and retries (EO3b)")
else
  verdict 1 "the cost drift does not reconcile" \
    "Check the cost block and the driver figures in app/incident/diagnose.py." \
    "GET /incident/cost must show reconciles=true, drift_pct=75, current above objective, and drivers each with add_per_request_usd summing to the delta. Fix app/incident/diagnose.py."
fi

# STEP 6 — quality regression
step_head "6" "Confirm the quality regression from sampling" \
  "Sampling must confirm the pass rate dropped below objective, with failures clustered on the provider." \
  "pass rate 68% (17/25) vs 92% baseline; grouped reasons cluster on balanced-std."
show_cmd "curl -s \$API_BASE/incident/quality | python3 scripts/fmt.py --type incident-quality"
RAW="$(curl -s "$API_BASE/incident/quality")"
emit "$(printf '%s' "$RAW" | $FMT --type incident-quality 2>&1)"
if echo "$RAW" | jq -e '.pass_rate_pct==68.0 and .passed==17 and .failed==8 and (.pass_rate_pct<.objective_pass_rate_pct) and (.baseline_pass_rate_pct==92.0) and (.failure_reasons|length>=2) and (.cluster|test("balanced-std"))' >/dev/null 2>&1; then
  verdict 0 "sampling confirms 68% vs 92% baseline, below the 90% objective, failures clustered on the provider" "" ""
  LO+=("Step 6: output quality sampling confirms the regression (EO3c)")
else
  verdict 1 "the quality regression sample is wrong" \
    "Check the quality block in app/incident/diagnose.py." \
    "GET /incident/quality must show pass_rate 68, passed 17, failed 8, baseline 92, objective 90, grouped failure_reasons, cluster balanced-std. Fix app/incident/diagnose.py."
fi

# STEP 7 — root cause and coordinated action
step_head "7" "Choose the operator action from the evidence" \
  "Four alerts must resolve to one root cause and a coordinated, evidence-based action per dimension." \
  "root cause: one degraded provider; a decision for latency, quota, cost, and quality; disposition ACT."
show_cmd "curl -s \$API_BASE/incident/action | python3 scripts/fmt.py --type incident-action"
RAW="$(curl -s "$API_BASE/incident/action")"
emit "$(printf '%s' "$RAW" | $FMT --type incident-action 2>&1)"
if echo "$RAW" | jq -e '(.root_cause|test("balanced-ai")) and (.disposition=="ACT") and (.decisions|length==4) and ([.decisions[].dimension]|(index("latency") and index("quota") and index("cost") and index("output_quality"))) and (.decisions|all(has("evidence") and has("action") and has("expected_effect")))' >/dev/null 2>&1; then
  verdict 0 "four symptoms resolve to one root cause; each dimension gets an evidence-based action" "" ""
  LO+=("Step 7: observability data drives a root-cause, evidence-based decision (EO3e, TO2)")
else
  verdict 1 "the root-cause action is incomplete" \
    "Check the action block in app/incident/diagnose.py." \
    "GET /incident/action must return root_cause on balanced-ai, disposition ACT, 4 decisions covering latency/quota/cost/output_quality each with evidence, action, expected_effect. Fix app/incident/diagnose.py."
fi

# COVERAGE + SUMMARY
banner "LEARNING OBJECTIVE COVERAGE"
emit "${WHITE}TO2, EO2e, TO3, EO3a-e — Read a simulated incident from its alerts and${R}"
emit "${WHITE}       dashboard, isolate the latency, shed the quota pressure, reconcile the${R}"
emit "${WHITE}       cost drift, confirm the quality regression, and act on one root cause.${R}"
if [ "${#LO[@]}" -gt 0 ]; then for e in "${LO[@]}"; do emit "  ${LIME}✔${R} ${GRAY}${e}${R}"; done; else emit "  ${PINK}✗ no evidence captured${R}"; fi

banner "SUMMARY"
TOTAL=$((PASS+FAIL))
emit "  ${LIME}PASS: ${PASS}${R}   ${PINK}FAIL: ${FAIL}${R}   ${GRAY}of ${TOTAL} steps${R}"
if [ "$FAIL" = "0" ]; then
  emit "  ${LIME}✔ ALL STEPS PASSED — demo aligns with TO2, EO2e, TO3, EO3a-e. Ready to record.${R}"
else
  emit "  ${PINK}✗ ${FAIL} step(s) failed — fix above, reset, and re-run.${R}"
fi
blank
emit "  ${GRAY}full readable log written to:${R} ${LGRN}module2/clip6_preflight_log.txt${R}"
exit "$FAIL"
