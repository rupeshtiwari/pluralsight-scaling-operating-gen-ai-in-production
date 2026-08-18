#!/usr/bin/env bash
# =============================================================================
# Module 3 · Demo — Run readiness audit and finalize operational runbook proof
# AUTHOR PREFLIGHT: runs every demo step in the SAME order as module3/demo/m3-demo6-readiness-audit-runbook.md,
# captures each command and its on-screen output (including the rich CLIs the
# clip records), asserts the output proves the learning objectives (EO4d, TO5,
# EO5a-d), and writes a readable log.
#
#   bash module3/scripts/m3-demo6-readiness-audit-runbook.preflight.sh
#
# Defaults target Docker Compose on macOS; override with env vars for a native
# stack: API_BASE
#
# The rich CLIs (readiness_audit.py, workload_decision.py, maturity_check.py,
# ops_view.py) need the `rich` package. setup.sh installs it into .venv, so this
# preflight prefers .venv/bin/python and falls back to python3 — exactly like the
# demo doc (which invokes .venv/bin/python scripts/...).
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
export API_BASE   # the rich CLIs (_richutil) read the base from this env var
FMT="python3 $ROOT/scripts/fmt.py"

# Prefer the project virtualenv (setup.sh installs the pinned `rich` there); fall
# back to system python3. This mirrors the demo doc's `.venv/bin/python scripts/...`.
if [ -x "$ROOT/.venv/bin/python" ]; then PY="$ROOT/.venv/bin/python"; else PY="python3"; fi

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
    emit "${GRAY}  do NOT edit app/lifecycle/*.py. Start the stack, then re-run:${R}"
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

# Emit a TRANSPORT failure verdict — points at the stack, never at the app code.
transport_fail() {  # $1 = path(s) that failed
  verdict 1 "TRANSPORT — could not read $1 with HTTP 200 (service down or route missing)" \
    "Confirm the stack is up: curl \$API_BASE/health must be 200 and curl \$API_BASE/openapi.json must list the route." \
    "Bring up FastAPI/Redis/Postgres (bash module3/scripts/demo_up.sh) and re-run. This is a service/transport failure — do NOT edit the app code."
}

banner "MODULE 3 · DEMO — READINESS AUDIT AND OPERATIONAL RUNBOOK  (LO: EO4d, TO5, EO5a-d)"
emit "${GRAY}stack:${R} API=${LGRN}${API_BASE}${R}   ${GRAY}python:${R} ${LGRN}${PY}${R}"
require_stack
emit "${GRAY}seeding the readiness audit, runbook, and maturity decision ...${R}"
curl -s -X POST "$API_BASE/admin/reset" >/dev/null 2>&1
SEED_CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API_BASE/lifecycle/readiness/run" 2>/dev/null)
if [ "$SEED_CODE" != "200" ]; then
  emit "${PINK}✗ SEEDING FAILED — POST ${API_BASE}/lifecycle/readiness/run returned HTTP ${SEED_CODE:-000}.${R}"
  emit "${GRAY}  No lifecycle state was built, so every downstream read would be empty. This is a${R}"
  emit "${GRAY}  routing/transport failure, not a logic bug — do NOT edit app/lifecycle/readiness.py.${R}"
  exit 2
fi

# =============================================================================
# STEP 1 — deprecation migration proven with a compatibility receipt
# =============================================================================
step_head "1" "Prove the deprecation migration with receipt evidence" \
  "Retiring a deprecated model must be a route-swap behind the uniform adapter, and twelve live requests through it must aggregate into a compatibility receipt (id + retiring/replacement identity + four checks) — auditable proof the swap preserved the caller contract, not just a route change." \
  "POST /admin/deprecate activates the adapter; twelve POST /v1/completions route through it; then the MIGRATION COMPATIBILITY RECEIPT — mig-2026-06-30-001, retiring balanced-std@2026-04 -> balanced-std@2026-06, Requests Migrated 12, four checks PASS, DISPOSITION MIGRATED."
show_cmd "curl -s -X POST \$API_BASE/admin/deprecate?model=balanced-std@2026-04&replacement=balanced-std@2026-06 | jq ."
DEP=$(curl -s -w $'\n%{http_code}' -X POST "$API_BASE/admin/deprecate?model=balanced-std@2026-04&replacement=balanced-std@2026-06" 2>/dev/null)
DEP_CODE=${DEP##*$'\n'}; DEP_BODY=${DEP%$'\n'*}
[ "$DEP_CODE" = "200" ] && emit "$(printf '%s' "$DEP_BODY" | jq . 2>&1)"
show_cmd "k6 run --quiet scripts/migration-traffic.js   # 12 requests through the adapter (curl loop equivalent below)"
# k6 is the recorded traffic generator; the preflight uses a curl loop so it never
# depends on host k6 — both send the same 12 requests to the same endpoint.
MIG_SENT=0
for i in $(seq 1 12); do
  c=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API_BASE/v1/completions" \
        -H 'Content-Type: application/json' -d '{"model":"balanced-std@2026-04","prompt":"summarize this support ticket"}' 2>/dev/null)
  [ "$c" = "200" ] && MIG_SENT=$((MIG_SENT+1))
done
emit "${GRAY}sent ${MIG_SENT}/12 migration requests through POST /v1/completions${R}"
show_cmd "curl -s \$API_BASE/receipts/migration | $PY scripts/ops_view.py --type receipt"
get_json "/receipts/migration" && RAW_RCPT="$GET_BODY" || RAW_RCPT=""
if [ -z "$RAW_RCPT" ] || [ "$DEP_CODE" != "200" ]; then
  transport_fail "/admin/deprecate or /receipts/migration"
else
  emit "$(printf '%s' "$RAW_RCPT" | $PY "$ROOT/scripts/ops_view.py" --type receipt 2>&1)"
  if echo "$DEP_BODY" | jq -e '.status=="adapter_active"' >/dev/null 2>&1 && \
     echo "$RAW_RCPT" | jq -e '.disposition=="MIGRATED" and .requests_migrated==12 and (.receipt_id|test("mig-")) and .retiring_model=="balanced-std@2026-04" and .replacement_model=="balanced-std@2026-06" and (.checks|length==4) and (.checks|all(.result=="pass")) and ([.checks[].check]|(index("output_contract") and index("latency_within_slo") and index("cost_within_budget") and index("quality_above_baseline")))' >/dev/null 2>&1; then
    verdict 0 "the deprecated model retired through the replacement adapter (status adapter_active); twelve live requests aggregated into receipt mig-2026-06-30-001 (retiring balanced-std@2026-04 -> balanced-std@2026-06, 12 migrated), four compatibility checks all pass, disposition MIGRATED" "" ""
    LO+=("Step 1: manage an upstream deprecation with a receipt-backed 12-request migration (EO4d)")
  else
    verdict 1 "the deprecation migration or its receipt is wrong" \
      "Check app/lifecycle/migration.py (deprecate/complete/migration_receipt) and the /admin/deprecate, /v1/completions, /receipts/migration routes in app/main.py." \
      "POST /admin/deprecate must return status adapter_active; twelve POST /v1/completions with model balanced-std@2026-04 must record; GET /receipts/migration must show disposition MIGRATED, requests_migrated 12, receipt_id mig-..., retiring/replacement identities, and four checks all pass. Fix app/lifecycle/migration.py."
  fi
fi

# =============================================================================
# STEP 2 — production readiness audit with a quantified security gap
# =============================================================================
step_head "2" "Score readiness with a production audit" \
  "The audit must score scalability, observability, security, cost efficiency, and reliability, and quantify the one real gap — verified vs unverified requests, the 95% requirement, and the action — not a gut feel." \
  "the PRODUCTION READINESS AUDIT table (17/20, security 2/4 GAP) and the BLOCKING GAP DETAIL box: Verified 1,240 / 2,000 (62%), Unverified 760 (38%), example cust-102317 -> cust-XXX317, Required >= 95%, Gap +33 points, ACTION scale blocked."
show_cmd "$PY scripts/readiness_audit.py --format rich"
AUDIT_RENDER=$($PY "$ROOT/scripts/readiness_audit.py" --format rich 2>&1)
emit "$AUDIT_RENDER"
get_json "/lifecycle/readiness/audit" && RAW_AUD="$GET_BODY" || RAW_AUD=""
if [ -z "$RAW_AUD" ]; then
  transport_fail "/lifecycle/readiness/audit"
else
  if echo "$RAW_AUD" | jq -e '(.rows|length==5) and ([.rows[].dimension]|(index("scalability") and index("observability") and index("security") and index("cost_efficiency") and index("reliability"))) and ([.gaps[]]|index("security")) and .score==17 and (.redaction_sample|has("verified_requests") and has("total_requests") and has("unverified_requests") and (.coverage_pct<100) and (.required_pct==95) and (.gap_pp==33) and (.redacted!=.raw))' >/dev/null 2>&1 \
     && echo "$AUDIT_RENDER" | grep -q "17/20" \
     && echo "$AUDIT_RENDER" | grep -q "cust-XXX317"; then
    verdict 0 "the audit scores all five dimensions (17/20, security the one gap) and quantifies it: 1,240/2,000 verified (62%), 760 unverified, example cust-102317 -> cust-XXX317, required >= 95%, gap +33 points, with the scale-blocking action" "" ""
    LO+=("Step 2: evaluate the architecture against readiness criteria, gap quantified (TO5, EO5a)")
  else
    verdict 1 "the readiness audit or its quantified gap is wrong" \
      "Check the audit block (audit_rows + redaction_sample) in app/lifecycle/readiness.py and scripts/readiness_audit.py." \
      "GET /lifecycle/readiness/audit must score the five dimensions (total 17, security the gap) with a redaction_sample carrying verified_requests, total_requests, unverified_requests, coverage_pct<100, required_pct 95, gap_pp 33, and raw!=redacted; the rich CLI must render 17/20 and cust-XXX317. Fix app/lifecycle/readiness.py."
  fi
fi

# =============================================================================
# STEP 3 — workload-derived deployment + a runbook proven live by an injected breach
# =============================================================================
step_head "3" "Derive the deployment from workload evidence and prove the runbook fires" \
  "The deployment pattern must be DERIVED from a measured workload (config/deployment.yaml), the three patterns compared, the runbook inspected as a real file with trigger->action controls, and an injected p95 above the 2500ms SLO must fire the mapped scale-out alert LIVE." \
  "the WORKLOAD PROFILE panel (9.8 RPS, cold-start 3.6x over target), the pattern table (serverless VIOLATES / containers RECOMMENDED / dedicated_gpu OVERKILL), DECISION containers; the runbook controls; then an injected 2600ms breach fires the RUNBOOK ALERT with a scale_out action."
show_cmd "$PY scripts/workload_decision.py --sample-minutes 15 --latency-target 500"
WL_RENDER=$($PY "$ROOT/scripts/workload_decision.py" --sample-minutes 15 --latency-target 500 2>&1)
emit "$WL_RENDER"
show_cmd "sed -n '/^controls:/,\$p' docs/runbook.yaml   # the runbook is a real file — inspect its controls"
CONTROLS=$(sed -n '/^controls:/,$p' "$ROOT/docs/runbook.yaml" 2>/dev/null)
emit "$CONTROLS"
show_cmd "curl -s -X POST \$API_BASE/admin/inject-latency?p95_ms=2600&duration_s=90 | jq ."
INJ=$(curl -s -w $'\n%{http_code}' -X POST "$API_BASE/admin/inject-latency?p95_ms=2600&duration_s=90" 2>/dev/null)
INJ_CODE=${INJ##*$'\n'}; INJ_BODY=${INJ%$'\n'*}
[ "$INJ_CODE" = "200" ] && emit "$(printf '%s' "$INJ_BODY" | jq . 2>&1)"
show_cmd "curl -s \$API_BASE/admin/alerts | $PY scripts/ops_view.py --type alert"
get_json "/admin/alerts" && RAW_ALERT="$GET_BODY" || RAW_ALERT=""
[ -n "$RAW_ALERT" ] && emit "$(printf '%s' "$RAW_ALERT" | $PY "$ROOT/scripts/ops_view.py" --type alert 2>&1)"
if [ -z "$RAW_ALERT" ] || [ "$INJ_CODE" != "200" ]; then
  transport_fail "/admin/inject-latency or /admin/alerts"
else
  WL_OK=1; ALERT_OK=1
  echo "$WL_RENDER" | grep -q "RECOMMENDED" && echo "$WL_RENDER" | grep -q "DECISION:" && echo "$WL_RENDER" | grep -qi "containers" || WL_OK=0
  echo "$CONTROLS" | grep -q "trigger" && echo "$CONTROLS" | grep -q "action" || WL_OK=0
  echo "$RAW_ALERT" | jq -e '.latest.fired==true and .latest.measured_ms>.latest.threshold_ms and (.latest.alert|test("latency")) and (.latest.action_taken|test("scale")) and ((.alerts|length)>=1)' >/dev/null 2>&1 || ALERT_OK=0
  if [ "$WL_OK" = "1" ] && [ "$ALERT_OK" = "1" ]; then
    verdict 0 "the measured workload derives the containers recommendation (patterns compared), the runbook exposes trigger->action controls in docs/runbook.yaml, and an injected 2600ms p95 (> 2500ms SLO) fired the runbook alert live with a scale_out action" "" ""
    LO+=("Step 3: a measured workload drives the deployment decision, patterns compared (EO5b)")
    LO+=("Step 3: a runbook with trigger->action controls, proven live by an injected breach (EO5c)")
  else
    verdict 1 "the workload decision, the runbook controls, or the live breach alert is wrong" \
      "Check config/deployment.yaml + scripts/workload_decision.py, docs/runbook.yaml (controls:), and inject_breach/alert in app/lifecycle/readiness.py (+ /admin/inject-latency, /admin/alerts in app/main.py)." \
      "workload_decision.py must render RECOMMENDED containers and a DECISION line; docs/runbook.yaml must carry controls with trigger/action; POST /admin/inject-latency?p95_ms=2600 then GET /admin/alerts must show latest.fired true, measured_ms>threshold_ms, a latency alert with a scale action and a non-empty alerts list. Fix the workload/runbook/breach logic."
  fi
fi

# =============================================================================
# STEP 4 — operational maturity decision, evidence-derived, gaps name the investment
# =============================================================================
step_head "4" "Check maturity and name the gaps honestly" \
  "The maturity level must be DERIVED from the accumulated evidence — name the three ladder levels, list the proven capabilities (>= 7), and name three gaps to scale-ready where each gap states its concrete investment." \
  "MATURITY ASSESSMENT current MANAGED-PRODUCTION with the ladder marker; PROVEN CAPABILITIES (seven ✅ rows); GAPS BLOCKING SCALE-READY (three 🔴 rows each with its investment); disposition MANAGED_PRODUCTION."
show_cmd "$PY scripts/maturity_check.py --format rich"
MAT_RENDER=$($PY "$ROOT/scripts/maturity_check.py" --format rich 2>&1)
emit "$MAT_RENDER"
get_json "/lifecycle/readiness/maturity" && RAW_MAT="$GET_BODY" || RAW_MAT=""
if [ -z "$RAW_MAT" ]; then
  transport_fail "/lifecycle/readiness/maturity"
else
  if echo "$RAW_MAT" | jq -e '.current=="managed_production" and .disposition=="MANAGED_PRODUCTION" and ([.levels[]]|(index("prototype") and index("managed_production") and index("scale_ready"))) and (.proven_capabilities|length>=7) and (.proven_capabilities|all(has("capability") and has("evidence"))) and (.gap_to_next|length>=3) and (.gap_to_next|all(has("gap") and has("investment"))) and (.derived_from|test("audit"))' >/dev/null 2>&1 \
     && echo "$MAT_RENDER" | grep -qi "MANAGED-PRODUCTION" \
     && echo "$MAT_RENDER" | grep -qi "PROVEN CAPABILITIES"; then
    verdict 0 "the maturity level is computed from the evidence — managed production, seven proven capabilities, and three gaps to scale-ready each naming its investment" "" ""
    LO+=("Step 4: maturity derived from evidence, capabilities proven, gaps name the investment (EO5d)")
  else
    verdict 1 "the maturity decision, its capabilities, or its investment-named gaps are wrong" \
      "Check the maturity derivation (proven_capabilities + gap_to_next) in app/lifecycle/readiness.py and scripts/maturity_check.py." \
      "GET /lifecycle/readiness/maturity must show current managed_production, disposition MANAGED_PRODUCTION, the three levels, derived_from referencing the audit, >= 7 proven_capabilities (capability+evidence), and >= 3 gap_to_next entries each with gap+investment; the rich CLI must render MANAGED-PRODUCTION and PROVEN CAPABILITIES. Fix app/lifecycle/readiness.py."
  fi
fi

# COVERAGE + SUMMARY
banner "LEARNING OBJECTIVE COVERAGE"
emit "${WHITE}EO4d, TO5, EO5a-d — Migrate off a deprecated model with a receipt, audit${R}"
emit "${WHITE}       readiness across five dimensions, derive the deployment pattern, prove${R}"
emit "${WHITE}       the runbook fires live, and decide the operational maturity on evidence.${R}"
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
