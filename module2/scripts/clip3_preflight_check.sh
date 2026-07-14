#!/usr/bin/env bash
# =============================================================================
# Module 2 · Demo — Prove circuit breaker fallback and retry backoff
# AUTHOR PREFLIGHT: runs every demo step in the SAME order as module2/demo/clip3.md,
# captures each command and its on-screen output, asserts the output proves the
# learning objectives (EO2c, EO2d, EO2e), and writes a readable log for a reviewer.
#
#   bash module2/scripts/clip3_preflight_check.sh
#
# Defaults target Docker Compose on macOS; override with env vars for a native
# stack: API_BASE, PGHOST, PGPORT, PGUSER, PGDATABASE, PGPASSWORD
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
LOG="$ROOT/module2/clip3_preflight_log.txt"
: > "$LOG"

API_BASE="${API_BASE:-http://localhost:8000}"
export PGHOST="${PGHOST:-localhost}"; export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-genai}"; export PGDATABASE="${PGDATABASE:-genai}"
export PGPASSWORD="${PGPASSWORD:-genai}"
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

banner "MODULE 2 · DEMO — CIRCUIT BREAKER FALLBACK AND RETRY BACKOFF  (LO: EO2c, EO2d, EO2e)"
emit "${GRAY}stack:${R} API=${LGRN}${API_BASE}${R}  PG=${LGRN}${PGHOST}:${PGPORT}/${PGDATABASE}${R}"
emit "${GRAY}resetting to a clean, repeatable state ...${R}"
curl -s -X POST "$API_BASE/admin/reset" >/dev/null 2>&1

# STEP 1 — config + deterministic failure modes
step_head "1" "Load the circuit-breaker configuration" \
  "The failure modes must be deterministic stubs and every threshold must be explicit." \
  "failure modes error/quota/slow, failure_threshold 3, fallback routes, and a 3-row backoff schedule."
show_cmd "curl -s \$API_BASE/resilience/circuit-config | python3 scripts/fmt.py --type circuit-config"
RAW="$(curl -s "$API_BASE/resilience/circuit-config")"
emit "$(printf '%s' "$RAW" | $FMT --type circuit-config 2>&1)"
if echo "$RAW" | jq -e '(.failure_modes|index("error") and index("quota") and index("slow")) and .failure_threshold==3 and (.backoff_schedule|length)==3 and (.fallback_routes["balanced-std"]=="econo-mini")' >/dev/null 2>&1; then
  verdict 0 "config exposes deterministic failure modes, thresholds, fallback routes, and backoff schedule" "" ""
  LO+=("Step 1: failure modes are deterministic and thresholds are explicit (EO2e)")
else
  verdict 1 "circuit config is missing failure modes, thresholds, or routes" \
    "Check FAILURE_CONDITIONS, FAILURE_THRESHOLD, FALLBACK_ROUTES, backoff_schedule in app/providers/registry.py." \
    "GET /resilience/circuit-config must list failure_modes error/quota/slow, failure_threshold=3, fallback balanced-std→econo-mini, 3 backoff rows. Fix app/providers/registry.py."
fi

# STEP 2 — run drill, walk the states
step_head "2" "Walk the circuit through its states" \
  "One drill must drive the circuit through closed, open, half-open, recovered — against all three failure modes." \
  "an 8-row journey whose primary cond spans slow/error/quota and whose circuit column shows closed, open, half_open."
show_cmd "curl -s -X POST \$API_BASE/resilience/drill >/dev/null; curl -s \$API_BASE/resilience/circuit | python3 scripts/fmt.py --type circuit"
curl -s -X POST "$API_BASE/resilience/drill" >/dev/null
RAW="$(curl -s "$API_BASE/resilience/circuit")"
emit "$(printf '%s' "$RAW" | $FMT --type circuit 2>&1)"
if echo "$RAW" | jq -e '.tripped==true and .recovered==true and ([.timeline[].circuit]|unique|(index("closed") and index("open") and index("half_open"))) and ([.timeline[].transition]|index("recovered")) and ([.timeline[].primary_condition]|unique|(index("slow") and index("error") and index("quota")))' >/dev/null 2>&1; then
  verdict 0 "the drill walks closed → open → half_open → recovered, driven by slow, error, AND quota failures" "" ""
  LO+=("Step 2: the breaker moves through all four states, simulating slow, error, and quota (EO2c, EO2e)")
else
  verdict 1 "the circuit did not walk all four states across all three failure modes" \
    "Check the state machine and CIRCUIT_DRILL_SEQUENCE (must span slow/error/quota) in app/resilience/circuit.py and app/providers/registry.py." \
    "After POST /resilience/drill, GET /resilience/circuit must show primary_condition spanning slow, error, quota; circuit states closed, open, half_open; a recovered transition; tripped=true, recovered=true. Fix app/providers/registry.py."
fi

# STEP 3 — fallback keeps the caller whole
step_head "3" "Prove fallback routing keeps the caller whole" \
  "A healthy alternative must serve while the primary is unsafe, so no failure reaches the caller." \
  "requests answered 8/8, caller errors 0, served by primary 2, served by fallback 6."
show_cmd "curl -s \$API_BASE/resilience/fallback | python3 scripts/fmt.py --type fallback"
RAW="$(curl -s "$API_BASE/resilience/fallback")"
emit "$(printf '%s' "$RAW" | $FMT --type fallback 2>&1)"
if echo "$RAW" | jq -e '.requests_answered==8 and .caller_errors==0 and .primary_served==2 and .fallback_served==6' >/dev/null 2>&1; then
  verdict 0 "8/8 requests answered with 0 caller errors — 6 served by the healthy fallback" "" ""
  LO+=("Step 3: the breaker fails over to a healthy alternative model (EO2c)")
else
  verdict 1 "fallback routing did not keep the caller whole" \
    "Check run_drill fallback handling and FALLBACK_ROUTES in app/resilience/circuit.py." \
    "GET /resilience/fallback must show requests_answered=8, caller_errors=0, primary_served=2, fallback_served=6. Fix app/resilience/circuit.py."
fi

# STEP 4 — retry backoff, no storm
step_head "4" "Inspect retry backoff and prove no storm" \
  "Retries must be capped and spaced by exponential backoff, and an open circuit must make zero attempts." \
  "backoff schedule 0/430/870ms, 12 attempts with the breaker vs 18 without — 6 retries avoided."
show_cmd "curl -s \$API_BASE/resilience/retry-log | python3 scripts/fmt.py --type retry-log"
RAW="$(curl -s "$API_BASE/resilience/retry-log")"
emit "$(printf '%s' "$RAW" | $FMT --type retry-log 2>&1)"
if echo "$RAW" | jq -e '.total_primary_attempts==12 and .attempts_without_breaker==18 and .storm_prevented==true and (.backoff_schedule|length)==3' >/dev/null 2>&1; then
  verdict 0 "retries capped with backoff; opening the circuit avoided 6 attempts (12 vs 18) — no storm" "" ""
  LO+=("Step 4: retry logic uses exponential backoff and prevents a retry storm (EO2d)")
else
  verdict 1 "retry backoff or storm prevention did not hold" \
    "Check backoff_schedule and total_primary_attempts vs attempts_without_breaker in app/resilience/circuit.py." \
    "GET /resilience/retry-log must show total_primary_attempts=12, attempts_without_breaker=18, storm_prevented=true. Fix app/resilience/circuit.py."
fi

# STEP 5 — reconcile the three named sources: caller / fallback receipt / retry log
step_head "5" "Reconcile caller response, receipt, and retry log" \
  "The caller response, the PostgreSQL fallback receipt, and the retry log must agree and the circuit must have recovered." \
  "disposition CONFIRMED with counts_agree, recovered, receipts_complete true; primary 2/2/2 and fallback 6/6/6 across caller/receipt/retry log."
show_cmd "curl -s \$API_BASE/resilience/failover-reconcile | python3 scripts/fmt.py --type failover-reconcile"
RAW="$(curl -s "$API_BASE/resilience/failover-reconcile")"
emit "$(printf '%s' "$RAW" | $FMT --type failover-reconcile 2>&1)"
if echo "$RAW" | jq -e '.disposition=="CONFIRMED" and .counts_agree==true and .recovered==true and .receipts_complete==true and (.roles|to_entries|all(.value.agree==true and (.value|has("caller") and has("receipt") and has("retry_log"))))' >/dev/null 2>&1; then
  verdict 0 "caller response, fallback receipt, and retry log reconcile to CONFIRMED — failover validated end to end" "" ""
  LO+=("Step 5: caller response, fallback receipt, and retry log agree on one outcome (EO2e)")
else
  verdict 1 "the failover reconciliation is not CONFIRMED across the three sources" \
    "Check /resilience/failover-reconcile (caller/receipt/retry_log) in app/main.py and count_circuit_roles in app/db/postgres.py." \
    "GET /resilience/failover-reconcile after a clean drill must return disposition=CONFIRMED with caller, receipt, and retry_log agreeing per role. Fix app/main.py."
fi

# COVERAGE + SUMMARY
banner "LEARNING OBJECTIVE COVERAGE"
emit "${WHITE}EO2c, EO2d, EO2e — Trip on failures, fail over to a healthy model, retry${R}"
emit "${WHITE}       with capped backoff, and reconcile the recovery end to end${R}"
if [ "${#LO[@]}" -gt 0 ]; then for e in "${LO[@]}"; do emit "  ${LIME}✔${R} ${GRAY}${e}${R}"; done; else emit "  ${PINK}✗ no evidence captured${R}"; fi

banner "SUMMARY"
TOTAL=$((PASS+FAIL))
emit "  ${LIME}PASS: ${PASS}${R}   ${PINK}FAIL: ${FAIL}${R}   ${GRAY}of ${TOTAL} steps${R}"
if [ "$FAIL" = "0" ]; then
  emit "  ${LIME}✔ ALL STEPS PASSED — demo aligns with EO2c, EO2d, EO2e. Ready to record.${R}"
else
  emit "  ${PINK}✗ ${FAIL} step(s) failed — fix above, reset, and re-run.${R}"
fi
blank
emit "  ${GRAY}full readable log written to:${R} ${LGRN}module2/clip3_preflight_log.txt${R}"
exit "$FAIL"
