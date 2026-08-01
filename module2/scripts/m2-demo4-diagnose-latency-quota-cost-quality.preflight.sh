#!/usr/bin/env bash
# =============================================================================
# Module 2 · Demo — Diagnose latency, quota pressure, cost drift, and quality
# AUTHOR PREFLIGHT: runs every demo step in the SAME order as module2/demo/m2-demo4-diagnose-latency-quota-cost-quality.md,
# captures each command and its on-screen output, asserts the output proves the
# learning objectives (TO2, EO2e, TO3, EO3a-e), and writes a readable log.
#
#   bash module2/scripts/m2-demo4-diagnose-latency-quota-cost-quality.preflight.sh
#
# Defaults target Docker Compose on macOS; override with env vars for a native
# stack: API_BASE, PGHOST, PGPORT, PGUSER, PGDATABASE, PGPASSWORD
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
LOG="$ROOT/preflight-logs/m2-demo4-diagnose-latency-quota-cost-quality.log"
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

banner "MODULE 2 · DEMO — DIAGNOSE LATENCY, QUOTA, COST, AND QUALITY  (LO: TO2, EO2e, TO3, EO3a-e)"
emit "${GRAY}stack:${R} API=${LGRN}${API_BASE}${R}"
emit "${GRAY}triggering the controlled incident (one provider fault, four alerts) ...${R}"
curl -s -X POST "$API_BASE/admin/reset" >/dev/null 2>&1
curl -s -X POST "$API_BASE/incident/run" >/dev/null 2>&1

# STEP 1 — trigger the incident: alert timeline + operator dashboard
step_head "1" "Read the alert timeline and open the dashboard" \
  "A simulated incident must surface an ordered alert timeline with a clear first bad signal, and a dashboard showing all four dimensions breached." \
  "four alerts in fire order (latency first, quality pages last); four dashboard panels all red, baseline vs current vs objective."
show_cmd "curl -s -X POST \$API_BASE/incident/run >/dev/null; curl -s \$API_BASE/incident/alerts | python3 scripts/fmt.py --type incident-alerts"
AL="$(curl -s "$API_BASE/incident/alerts")"
emit "$(printf '%s' "$AL" | $FMT --type incident-alerts 2>&1)"
show_cmd "curl -s \$API_BASE/incident/dashboard | python3 scripts/fmt.py --type incident-dashboard"
DB="$(curl -s "$API_BASE/incident/dashboard")"
emit "$(printf '%s' "$DB" | $FMT --type incident-dashboard 2>&1)"
if echo "$AL" | jq -e '(.alerts|length==4) and (.first_signal=="LatencyP95AboveObjective") and ([.alerts[].dimension]|(index("latency") and index("quota") and index("cost") and index("output_quality"))) and ((.alerts[]|select(.dimension=="output_quality").severity)=="page")' >/dev/null 2>&1 \
  && echo "$DB" | jq -e '(.panels|length==4) and (.breached==4) and (.panels|all(.status=="breach")) and ([.panels[].dimension]|(index("latency") and index("quota") and index("cost") and index("output_quality")))' >/dev/null 2>&1; then
  verdict 0 "four alerts fire in order (latency first, quality pages), and the dashboard shows all four dimensions breached" "" ""
  LO+=("Step 1: a simulated incident surfaces an ordered alert timeline and an operator dashboard (EO2e, TO3, EO3d)")
else
  verdict 1 "the alert timeline or the dashboard is wrong" \
    "Check the alerts and dashboard blocks in app/incident/diagnose.py." \
    "GET /incident/alerts must return 4 alerts, first_signal LatencyP95AboveObjective, quality severity page; GET /incident/dashboard must return 4 breached panels. Fix app/incident/diagnose.py."
fi

# STEP 2 — isolate latency from the trace
step_head "2" "Isolate the latency from one trace" \
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

# STEP 3 — quota pressure and shed
step_head "3" "Prove the quota pressure and the shed" \
  "Admission control must shed the excess load with a 429 and a caller backoff, protecting the provider." \
  "40 submitted = 34 accepted + 6 rejected (caller backoff 60s); provider quota_exceeded at 98% utilization."
show_cmd "curl -s \$API_BASE/incident/quota | python3 scripts/fmt.py --type incident-quota"
RAW="$(curl -s "$API_BASE/incident/quota")"
emit "$(printf '%s' "$RAW" | $FMT --type incident-quota 2>&1)"
if echo "$RAW" | jq -e '.submitted==40 and .accepted==34 and .rejected_429==6 and .provider_status=="quota_exceeded" and .retry_after_seconds==60 and (.submitted==(.accepted+.rejected_429)) and (.shed_working==true)' >/dev/null 2>&1; then
  verdict 0 "40 submitted = 34 accepted + 6 shed with a 60s caller backoff; the provider is held below exhaustion" "" ""
  LO+=("Step 4: admission control sheds quota pressure and protects the provider (TO2, EO2e)")
else
  verdict 1 "the quota shed accounting is wrong" \
    "Check the quota block in app/incident/diagnose.py." \
    "GET /incident/quota must show submitted=40, accepted=34, rejected_429=6, provider_status quota_exceeded, retry_after 60, shed_working true. Fix app/incident/diagnose.py."
fi

# STEP 4 — connect model identity, tokens, cost, and quality (cost drift + quality regression)
step_head "4" "Connect the cost drift and the quality regression to the provider" \
  "Logs and receipts must tie model identity, tokens, and cost to the drift, and sampling must confirm the quality regression — both on the same degraded provider." \
  "\$0.0120 -> \$0.0210 per request (+75%) reconciled to retries + fallback; pass rate 68% (17/25) vs 92% baseline, clustered on balanced-std."
show_cmd "curl -s \$API_BASE/incident/cost | python3 scripts/fmt.py --type incident-cost"
CO="$(curl -s "$API_BASE/incident/cost")"
emit "$(printf '%s' "$CO" | $FMT --type incident-cost 2>&1)"
show_cmd "curl -s \$API_BASE/incident/quality | python3 scripts/fmt.py --type incident-quality"
QR="$(curl -s "$API_BASE/incident/quality")"
emit "$(printf '%s' "$QR" | $FMT --type incident-quality 2>&1)"
if echo "$CO" | jq -e '.reconciles==true and .drift_pct==75.0 and (.current_per_request_usd>.objective_per_request_usd) and (.drivers|length>=2) and (.drivers|all(has("add_per_request_usd")))' >/dev/null 2>&1 \
  && echo "$QR" | jq -e '.pass_rate_pct==68.0 and .passed==17 and .failed==8 and (.pass_rate_pct<.objective_pass_rate_pct) and (.baseline_pass_rate_pct==92.0) and (.failure_reasons|length>=2) and (.cluster|test("balanced-std"))' >/dev/null 2>&1; then
  verdict 0 "cost drift reconciles to retries + fallback, and quality sampling confirms 68% vs 92% — both on balanced-std" "" ""
  LO+=("Step 4: connect model identity, tokens, cost, and quality to the degraded provider (EO3b, EO3c)")
else
  verdict 1 "the cost drift or the quality regression is wrong" \
    "Check the cost and quality blocks in app/incident/diagnose.py." \
    "GET /incident/cost must show reconciles=true, drift 75, current above objective, >=2 drivers; GET /incident/quality must show pass_rate 68, 17/8, baseline 92, cluster balanced-std. Fix app/incident/diagnose.py."
fi

# STEP 5 — root cause and coordinated action
step_head "5" "Choose the operator action from the evidence" \
  "Four alerts must resolve to one root cause and a coordinated, evidence-based action per dimension." \
  "root cause: one degraded provider; a decision for latency, quota, cost, and quality; disposition ACT."
show_cmd "curl -s \$API_BASE/incident/action | python3 scripts/fmt.py --type incident-action"
RAW="$(curl -s "$API_BASE/incident/action")"
emit "$(printf '%s' "$RAW" | $FMT --type incident-action 2>&1)"
if echo "$RAW" | jq -e '(.root_cause|test("balanced-ai")) and (.disposition=="ACT") and (.decisions|length==4) and ([.decisions[].dimension]|(index("latency") and index("quota") and index("cost") and index("output_quality"))) and (.decisions|all(has("evidence") and has("action") and has("expected_effect")))' >/dev/null 2>&1; then
  verdict 0 "four symptoms resolve to one root cause; each dimension gets an evidence-based action" "" ""
  LO+=("Step 5: observability data drives a root-cause, evidence-based decision (EO3e, TO2)")
else
  verdict 1 "the root-cause action is incomplete" \
    "Check the action block in app/incident/diagnose.py." \
    "GET /incident/action must return root_cause on balanced-ai, disposition ACT, 4 decisions covering latency/quota/cost/output_quality each with evidence, action, expected_effect. Fix app/incident/diagnose.py."
fi

# COVERAGE + SUMMARY — one line per objective, each with its own evidence marker
banner "LEARNING OBJECTIVE COVERAGE"
if [ "$FAIL" = "0" ]; then M="${LIME}✔${R}"; else M="${PINK}✗${R}"; fi
emit "  ${M} ${WHITE}TO2 / EO2e${R} ${GRAY}resilience under a real incident: admission sheds quota pressure${R}"
emit "      ${GRAY}Step 3 — 40 submitted = 34 accepted + 6 shed (429, 60s backoff), provider held below exhaustion${R}"
emit "  ${M} ${WHITE}TO3 / EO3d${R} ${GRAY}the incident is read from alerts, a dashboard, and SLO breaches${R}"
emit "      ${GRAY}Step 1 — 4 alerts in fire order (latency first, quality pages) and 4 dashboard dimensions red${R}"
emit "  ${M} ${WHITE}EO3a${R} ${GRAY}distributed tracing isolates the latency source across the pipeline${R}"
emit "      ${GRAY}Step 2 — one trace clears queue/retry/fallback and pins provider_call on balanced-ai${R}"
emit "  ${M} ${WHITE}EO3b${R} ${GRAY}logs and receipts tie model identity, tokens, and cost to the drift${R}"
emit "      ${GRAY}Step 4 — cost \$0.0120→\$0.0210/req (+75%) reconciled to retries + fallback on balanced-ai${R}"
emit "  ${M} ${WHITE}EO3c${R} ${GRAY}output quality sampling confirms the regression${R}"
emit "      ${GRAY}Step 4 — pass rate 68% (17/25) vs 92% baseline, failures clustered on balanced-std${R}"
emit "  ${M} ${WHITE}EO3e${R} ${GRAY}observability data drives one root-cause, evidence-based decision${R}"
emit "      ${GRAY}Step 5 — four symptoms → one degraded provider → an action per dimension, disposition ACT${R}"

banner "SUMMARY"
TOTAL=$((PASS+FAIL))
emit "  ${LIME}PASS: ${PASS}${R}   ${PINK}FAIL: ${FAIL}${R}   ${GRAY}of ${TOTAL} steps${R}"
if [ "$FAIL" = "0" ]; then
  emit "  ${LIME}✔ ALL STEPS PASSED — demo aligns with TO2, EO2e, TO3, EO3a-e. Ready to record.${R}"
else
  emit "  ${PINK}✗ ${FAIL} step(s) failed — fix above, reset, and re-run.${R}"
fi
blank
emit "  ${GRAY}full readable log written to:${R} ${LGRN}preflight-logs/m2-demo4-diagnose-latency-quota-cost-quality.log${R}"
exit "$FAIL"
