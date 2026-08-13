#!/usr/bin/env bash
# =============================================================================
# Module 3 · Demo — Validate model updates against quality baselines
# AUTHOR PREFLIGHT: runs every demo step in the SAME order as module3/demo/m3-demo3-model-update-validation.md,
# captures each command and its on-screen output, asserts the output proves the
# learning objective (EO4b), and writes a readable log.
#
#   bash module3/scripts/m3-demo3-model-update-validation.preflight.sh
#
# Defaults target Docker Compose on macOS; override with env vars for a native
# stack: API_BASE, PYTEST (the command that runs pytest, default ".venv/bin/python -m pytest")
#
# TRANSPORT SAFETY: this script fails LOUDLY and distinctly when the service is
# unreachable — it never lets a down stack masquerade as a content/logic failure.
# A precondition asserts API_BASE is set and /health is 200 before Step 1, and
# every read is status-gated (HTTP 200) before it is parsed.
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
LOG="$ROOT/preflight-logs/m3-demo3-model-update-validation.log"
: > "$LOG"

API_BASE="${API_BASE:-http://localhost:8000}"
# The course installs the pinned pytest==9.1.1 into the project virtualenv (.venv)
# via environment-setup/setup.sh — NOT into the system python. Prefer the venv's
# interpreter so the suite runs the pinned pytest regardless of what `python3`
# resolves to on the host. Override with PYTEST=... to manage deps differently.
if [ -z "${PYTEST:-}" ]; then
  if [ -x "$ROOT/.venv/bin/python" ]; then PYTEST=".venv/bin/python -m pytest"
  else PYTEST="python3 -m pytest"; fi
fi
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
    emit "${GRAY}  do NOT edit app/lifecycle/validation.py. Start the stack, then re-run:${R}"
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

# Emit a TRANSPORT failure verdict — points at the stack, never at validation.py.
transport_fail() {  # $1 = path(s) that failed
  verdict 1 "TRANSPORT — could not read $1 with HTTP 200 (service down or route missing)" \
    "Confirm the stack is up: curl \$API_BASE/health must be 200 and curl \$API_BASE/openapi.json must list /lifecycle/validation/*." \
    "Bring up FastAPI/Redis/Postgres (bash module3/scripts/demo_up.sh) and re-run. This is a service/transport failure — do NOT edit app/lifecycle/validation.py."
}

# The baseline gate is a real Pytest suite. It runs via the interpreter in $PYTEST
# (the project .venv by default, where setup.sh installs the pinned pytest==9.1.1).
# If that interpreter cannot import pytest, say exactly how to fix it — we never
# fabricate a pass, and we never silently fall back to a pytest-less "gate".
check_pytest() {  # returns non-zero and explains if pytest is not importable
  local pybin="${PYTEST%% -m pytest}"
  $pybin -c "import pytest" >/dev/null 2>&1 && return 0
  emit "${GRAY}pytest is not importable via '${pybin}'. The course installs it into the project venv —${R}"
  emit "${GRAY}  run: ${R}${LGRN}bash environment-setup/setup.sh${R}${GRAY}  (or: python3 -m venv .venv && .venv/bin/python -m pip install pytest==9.1.1)${R}"
  return 1
}

banner "MODULE 3 · DEMO — VALIDATE MODEL UPDATES AGAINST QUALITY BASELINES  (LO: EO4b)"
emit "${GRAY}stack:${R} API=${LGRN}${API_BASE}${R}"
require_stack
emit "${GRAY}evaluating candidates against the baseline gate ...${R}"
curl -s -X POST "$API_BASE/admin/reset" >/dev/null 2>&1
SEED_CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API_BASE/lifecycle/validation/run" 2>/dev/null)
if [ "$SEED_CODE" != "200" ]; then
  emit "${PINK}✗ SEEDING FAILED — POST ${API_BASE}/lifecycle/validation/run returned HTTP ${SEED_CODE:-000}.${R}"
  emit "${GRAY}  No lifecycle state was built, so every downstream read would be empty. This is a${R}"
  emit "${GRAY}  routing/transport failure, not a logic bug — do NOT edit app/lifecycle/validation.py.${R}"
  exit 2
fi

# STEP 1 — run the real Pytest baseline gate + inspect the baseline thresholds
step_head "1" "Run the baseline gate (Pytest) and inspect the thresholds" \
  "The gate must be a real automated test, not a claim — run the Pytest baseline suite — and the baseline must cover quality, latency, cost, failure rate, and contract compliance." \
  "the Pytest suite passes and the gate marks one candidate eligible and one blocked, then five dimensions each with its objective (a min floor or a max ceiling)."
show_cmd "$PYTEST tests/baseline -q  &&  curl -s \$API_BASE/lifecycle/validation/gate | python3 scripts/fmt.py --type validation-gate"
# The baseline gate is a REAL Pytest suite. The outline requires it to RUN, and the
# course environment pins pytest==9.1.1 — so run it for real and let its pass BE the
# evidence. A host that cannot run pytest is a setup gap to fix, never a pass to fake:
# there is no server-side fallback that fabricates a "suite passed" line.
check_pytest || true
PYOUT="$($PYTEST tests/baseline -q 2>&1)"; PYRC=$?
emit "${GRAY}${PYOUT}${R}"
get_json "/lifecycle/validation/gate" && RAW_GATE="$GET_BODY" || RAW_GATE=""
[ -n "$RAW_GATE" ] && emit "$(printf '%s' "$RAW_GATE" | $FMT --type validation-gate 2>&1)"
show_cmd "curl -s \$API_BASE/lifecycle/validation/baseline | python3 scripts/fmt.py --type validation-baseline"
get_json "/lifecycle/validation/baseline" && RAW_BASE="$GET_BODY" || RAW_BASE=""
[ -n "$RAW_BASE" ] && emit "$(printf '%s' "$RAW_BASE" | $FMT --type validation-baseline 2>&1)"
if [ -z "$RAW_GATE" ] || [ -z "$RAW_BASE" ]; then
  transport_fail "/lifecycle/validation/gate or /baseline"
else
  GATE_OK=1; BASE_OK=1
  echo "$RAW_GATE" | jq -e '.checks==10 and .gate_enforced==true and ([.candidates[].eligible]|(index(true) and index(false)))' >/dev/null 2>&1 || GATE_OK=0
  echo "$RAW_BASE" | jq -e '(.rows|length==5) and (.rows|all(has("approved"))) and ([.rows[].dimension]|(index("quality_score") and index("latency_p95_ms") and index("cost_per_1k_usd") and index("failure_rate_pct") and index("contract_compliance_pct")))' >/dev/null 2>&1 || BASE_OK=0
  # Pytest must ACTUALLY pass — it is the gate the outline requires, not decoration.
  # Step 1 passes only if the real suite is green AND the gate/baseline are correct.
  if [ "$PYRC" = "0" ]; then
    emit "  ${LIME}Pytest baseline gate: suite passed — the promotion criteria are enforced as code.${R}"
  else
    emit "  ${PINK}Pytest baseline gate: the suite did NOT pass (pytest rc=$PYRC) — the recorded clip must show it green before you record.${R}"
  fi
  if [ "$PYRC" = "0" ] && [ "$GATE_OK" = "1" ] && [ "$BASE_OK" = "1" ]; then
    verdict 0 "the real Pytest baseline suite passed, the gate is enforced (checks=10, one candidate eligible and one blocked), and the baseline shows the approved model's values across quality, latency, cost, failure rate, and contract compliance" "" ""
    LO+=("Step 1: a real Pytest suite enforces the promotion criteria as code (EO4b)")
    LO+=("Step 1: the baseline shows the approved model's values across quality and performance dimensions (EO4b)")
  else
    verdict 1 "the Pytest baseline suite did not pass, or the gate/baseline is wrong" \
      "Run '$PYTEST tests/baseline -q' — it must exit 0. If pytest is missing, the course installs it into the project venv: run 'bash environment-setup/setup.sh' (or 'python3 -m venv .venv && .venv/bin/python -m pip install pytest==9.1.1'). Then check app/lifecycle/validation.py." \
      "The recorded clip must show the REAL Pytest suite passing — do not rely on any server-side fallback. Ensure 'python3 -m pytest tests/baseline -q' passes, then GET /lifecycle/validation/gate shows checks=10, gate_enforced true, one eligible + one blocked; GET /lifecycle/validation/baseline lists 5 dimensions each carrying the approved model's value. Fix app/lifecycle/validation.py or the environment."
  fi
fi

# STEP 2 — passing candidate
step_head "2" "Validate the passing candidate" \
  "A candidate within every threshold must be eligible for promotion." \
  "every dimension passes; the candidate is eligible."
show_cmd "curl -s \$API_BASE/lifecycle/validation/pass | python3 scripts/fmt.py --type validation-candidate"
get_json "/lifecycle/validation/pass" && RAW="$GET_BODY" || RAW=""
if [ -z "$RAW" ]; then
  transport_fail "/lifecycle/validation/pass"
else
  emit "$(printf '%s' "$RAW" | $FMT --type validation-candidate 2>&1)"
  if echo "$RAW" | jq -e '.eligible==true and (.breaches|length==0) and (.rows|all(.status=="pass")) and (.rows|all(has("approved")))' >/dev/null 2>&1; then
    verdict 0 "the passing candidate clears every baseline dimension and is eligible" "" ""
    LO+=("Step 2: a candidate within thresholds is eligible for promotion (EO4b)")
  else
    verdict 1 "the passing candidate was not eligible" \
      "Check the passing candidate metrics in app/lifecycle/validation.py." \
      "GET /lifecycle/validation/pass must show eligible true, no breaches, all rows pass. Fix app/lifecycle/validation.py."
  fi
fi

# STEP 3 — failing candidate
step_head "3" "Validate the failing candidate" \
  "A candidate that drifts on any dimension must be blocked, with the breaches named." \
  "quality, latency, failure rate, and contract breach; the candidate is blocked."
show_cmd "curl -s \$API_BASE/lifecycle/validation/fail | python3 scripts/fmt.py --type validation-candidate"
get_json "/lifecycle/validation/fail" && RAW="$GET_BODY" || RAW=""
if [ -z "$RAW" ]; then
  transport_fail "/lifecycle/validation/fail"
else
  emit "$(printf '%s' "$RAW" | $FMT --type validation-candidate 2>&1)"
  if echo "$RAW" | jq -e '.eligible==false and (.rows|all(has("approved"))) and ([.breaches[]]|(index("quality_score") and index("latency_p95_ms") and index("failure_rate_pct") and index("contract_compliance_pct")))' >/dev/null 2>&1; then
    verdict 0 "the failing candidate is blocked on quality, latency, failure rate, and contract drift" "" ""
    LO+=("Step 3: a candidate that breaches any dimension is blocked (EO4b)")
  else
    verdict 1 "the failing candidate was not blocked as expected" \
      "Check the failing candidate metrics in app/lifecycle/validation.py." \
      "GET /lifecycle/validation/fail must show eligible false with breaches quality_score, latency_p95_ms, failure_rate_pct, contract_compliance_pct. Fix app/lifecycle/validation.py."
  fi
fi

# STEP 4 — release decision + reconcile the release state
step_head "4" "Record the release decision and reconcile the release state" \
  "The decision must promote the passing candidate, block the failing one, and make neither the default — and the default must stay on the approved model, with only baseline-passing candidates eligible." \
  "promote for the passing candidate, blocked for the failing one, becomes_default false for both, then disposition CONFIRMED: default unchanged, eligible and blocked candidates listed, gate enforced."
show_cmd "curl -s \$API_BASE/lifecycle/validation/decision | python3 scripts/fmt.py --type validation-decision"
get_json "/lifecycle/validation/decision" && RAW_DEC="$GET_BODY" || RAW_DEC=""
[ -n "$RAW_DEC" ] && emit "$(printf '%s' "$RAW_DEC" | $FMT --type validation-decision 2>&1)"
show_cmd "curl -s \$API_BASE/lifecycle/validation/reconcile | python3 scripts/fmt.py --type validation-reconcile"
get_json "/lifecycle/validation/reconcile" && RAW_REC="$GET_BODY" || RAW_REC=""
[ -n "$RAW_REC" ] && emit "$(printf '%s' "$RAW_REC" | $FMT --type validation-reconcile 2>&1)"
if [ -z "$RAW_DEC" ] || [ -z "$RAW_REC" ]; then
  transport_fail "/lifecycle/validation/decision or /reconcile"
else
  DEC_OK=1; REC_OK=1
  echo "$RAW_DEC" | jq -e '(.decisions|length==2) and (.decisions|all(.becomes_default==false)) and (.decisions[]|select(.candidate=="econo-fast@2026-07").decision=="blocked") and (.decisions[]|select(.candidate=="balanced-std@2026-07").eligible==true)' >/dev/null 2>&1 || DEC_OK=0
  echo "$RAW_REC" | jq -e '.disposition=="CONFIRMED" and .default_unchanged==true and .gate_enforced==true and ([.eligible_candidates[]]|index("balanced-std@2026-07")) and ([.blocked_candidates[]]|index("econo-fast@2026-07"))' >/dev/null 2>&1 || REC_OK=0
  if [ "$DEC_OK" = "1" ] && [ "$REC_OK" = "1" ]; then
    verdict 0 "the passing candidate is promoted to candidate default (eligible, not the production default), the failing one blocked, neither is the default; the default stays on the approved model and only the baseline-passing candidate is eligible" "" ""
    LO+=("Step 4: a candidate cannot become the default without passing the baseline (EO4b)")
    LO+=("Step 4: the release state reconciles with the gate enforced (EO4b)")
  else
    verdict 1 "the release decision is wrong or the release state did not reconcile" \
      "Check the decisions and reconcile blocks in app/lifecycle/validation.py." \
      "GET /lifecycle/validation/decision must show 2 decisions, both becomes_default false, failing candidate blocked, passing candidate eligible; GET /lifecycle/validation/reconcile must return disposition CONFIRMED, default_unchanged true, gate_enforced true, eligible/blocked lists correct. Fix app/lifecycle/validation.py."
  fi
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
emit "  ${GRAY}full readable log written to:${R} ${LGRN}preflight-logs/m3-demo3-model-update-validation.log${R}"
exit "$FAIL"
