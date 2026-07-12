#!/usr/bin/env bash
# =============================================================================
# Module 1 · Clip 2 — Build the FastAPI provider adapter layer
# AUTHOR PREFLIGHT: runs every demo step in the SAME order as module1/demo/clip2.md,
# captures each command and its on-screen output, asserts the output proves the
# learning objectives (TO1, EO1a), and writes a readable log you can hand to a
# reviewer to confirm LO coverage before you record.
#
#   bash module1/scripts/preflight_check.sh
#
# Works against any running stack. Defaults target Docker Compose on macOS;
# override with env vars for a native stack:
#   API_BASE, PGHOST, PGPORT, PGUSER, PGDATABASE, PGPASSWORD
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
LOG="$ROOT/module1/preflight_log.txt"
: > "$LOG"

# --- connection defaults (Docker Compose on macOS) ---------------------------
API_BASE="${API_BASE:-http://localhost:8000}"
export PGHOST="${PGHOST:-localhost}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-genai}"
export PGDATABASE="${PGDATABASE:-genai}"
export PGPASSWORD="${PGPASSWORD:-genai}"

FMT="python3 $ROOT/scripts/fmt.py"
PAYLOAD="$ROOT/data/payloads/baseline_request.json"

# Query Postgres the way the runbook does — inside the Docker container. Falls
# back to a host psql (PGHOST/PGPORT/PGUSER/... env) when Docker is unavailable,
# so the same preflight runs on the Docker Mac and in a native CI environment.
pg_query() {
  local sql="$1" out
  out="$(docker compose exec -T postgres psql -U "${PGUSER:-genai}" -d "${PGDATABASE:-genai}" -tAc "$sql" 2>/dev/null)"
  [ -z "$out" ] && out="$(psql -tAc "$sql" 2>/dev/null)"
  printf '%s' "$out"
}
SQL_RECEIPT="SELECT row_to_json(r) FROM (SELECT selected_model,provider_tier,provider_status,prompt_tokens,completion_tokens,total_tokens,cost_estimate_usd,quality_score,policy_name,request_id FROM receipts ORDER BY created_at DESC LIMIT 1) r"

# --- Pluralsight palette ------------------------------------------------------
PINK=$'\033[38;2;255;22;117m'; LIME=$'\033[38;2;207;255;110m'
LGRN=$'\033[38;2;64;255;191m'; BLUE=$'\033[38;2;42;236;250m'
GRAY=$'\033[38;2;191;191;191m'; WHITE=$'\033[1;37m'; R=$'\033[0m'

PASS=0; FAIL=0
declare -a LO_TO1=() LO_EO1a=()

emit() { printf '%s\n' "$1"; printf '%s\n' "$1" | sed -E 's/\x1b\[[0-9;]*m//g' >> "$LOG"; }
blank(){ emit ""; }

banner() {
  emit "${WHITE}================================================================================${R}"
  emit "${WHITE} $1${R}"
  emit "${WHITE}================================================================================${R}"
}

step_head() { # num  title  why  learn
  blank
  emit "${WHITE}┌── STEP $1 ─────────────────────────────────────────────────────────────────${R}"
  emit "${WHITE}│ $2${R}"
  emit "${BLUE}│ WHY WE RUN THIS:${R} ${GRAY}$3${R}"
  emit "${LIME}│ WHAT THE LEARNER SEES:${R} ${GRAY}$4${R}"
  emit "${WHITE}└────────────────────────────────────────────────────────────────────────────${R}"
}

show_cmd() { emit "${BLUE}\$ $1${R}"; blank; }

verdict() { # ok(0/1)  reason  fixprompt
  if [ "$1" = "0" ]; then
    PASS=$((PASS+1))
    emit "  ${LIME}✔ PASS${R} — $2"
  else
    FAIL=$((FAIL+1))
    emit "  ${PINK}✗ FAIL${R} — $2"
    emit "  ${PINK}HOW TO FIX:${R} ${GRAY}$3${R}"
    emit "  ${PINK}PROMPT TO FIX:${R} ${LGRN}$4${R}"
  fi
  blank
}

banner "MODULE 1 · CLIP 2 — FASTAPI PROVIDER ADAPTER LAYER  (LOs: TO1, EO1a)"
emit "${GRAY}stack:${R} API=${LGRN}${API_BASE}${R}  PG=${LGRN}${PGHOST}:${PGPORT}/${PGDATABASE}${R}"

# =============================================================================
# STEP 1 — Stack readiness
# =============================================================================
step_head "1" "Start the local stack and verify all layers are healthy" \
  "A dedicated AI service is only trustworthy if every layer is up first." \
  "status healthy, and fastapi + redis + postgres + provider_stubs all healthy."
CMD="curl -s \$API_BASE/health | python3 scripts/fmt.py --type health"
show_cmd "$CMD"
RAW="$(curl -s "$API_BASE/health")"
OUT="$(printf '%s' "$RAW" | $FMT --type health 2>&1)"; emit "$OUT"
if echo "$RAW" | jq -e '.status=="healthy" and (.components|to_entries|all(.value=="healthy"))' >/dev/null 2>&1; then
  verdict 0 "every component reports healthy" "" ""
  LO_EO1a+=("Step 1: service layer + Redis + PostgreSQL confirmed up")
else
  verdict 1 "one or more components are not healthy" \
    "Start the stack: 'bash module1/scripts/demo_up.sh' and wait for /health." \
    "The /health endpoint is not all-healthy. Diagnose which component (redis/postgres/provider_stubs) is down in app/main.py health() and fix its connection."
fi

# =============================================================================
# STEP 2 — Provider adapter configuration
# =============================================================================
step_head "2" "Inspect the provider adapter configuration for every model tier" \
  "The adapter contract is the decoupling boundary: one uniform shape per model." \
  "3 adapters, each with tier, latency_target_ms, quota_mode, cost, quality, status."
CMD="curl -s \$API_BASE/providers | python3 scripts/fmt.py --type providers"
show_cmd "$CMD"
RAW="$(curl -s "$API_BASE/providers")"
OUT="$(printf '%s' "$RAW" | $FMT --type providers 2>&1)"; emit "$OUT"
if echo "$RAW" | jq -e '.count==3 and (.adapters|all(has("tier") and has("latency_target_ms") and has("quota_mode") and has("cost_per_1k_usd") and has("quality_score") and has("status")))' >/dev/null 2>&1; then
  verdict 0 "all 3 adapters expose the full uniform contract" "" ""
  LO_TO1+=("Step 2: multi-model adapter set (low_cost, balanced, premium)")
  LO_EO1a+=("Step 2: identical contract fields across every provider")
else
  verdict 1 "adapter contract is incomplete or wrong count" \
    "Check BASE_ADAPTERS in app/providers/registry.py and AdapterConfig in app/schemas.py." \
    "The /providers response must return 3 adapters each exposing tier, latency_target_ms, quota_mode, cost_per_1k_usd, quality_score, status. Fix app/providers/registry.py."
fi

# =============================================================================
# STEP 3 — Deterministic local simulation (no external API calls)
# =============================================================================
step_head "3" "Prove the adapter is a deterministic local simulation" \
  "Repeatable demos need zero external calls — same input, same result, always." \
  "external_api_calls=0, deterministic=true, and two probes returning identical output."
CMD="curl -s \$API_BASE/providers/balanced-std/probe | python3 scripts/fmt.py --type probe"
show_cmd "$CMD"
RAW="$(curl -s "$API_BASE/providers/balanced-std/probe")"
RAW2="$(curl -s "$API_BASE/providers/balanced-std/probe")"
OUT="$(printf '%s' "$RAW" | $FMT --type probe 2>&1)"; emit "$OUT"
if echo "$RAW" | jq -e '.external_api_calls==0 and .deterministic==true' >/dev/null 2>&1 && [ "$RAW" = "$RAW2" ]; then
  verdict 0 "zero external calls and two probes are byte-identical" "" ""
  LO_EO1a+=("Step 3: deterministic stub, no vendor SDK or network egress")
else
  verdict 1 "probe is non-deterministic or reports external calls" \
    "Ensure probe() in app/providers/adapter.py is a pure function of (model, condition)." \
    "The /providers/{model}/probe endpoint must return external_api_calls=0, deterministic=true, and be identical across calls. Fix app/providers/adapter.py probe()."
fi

# =============================================================================
# STEP 4 — Active provider condition matrix
# =============================================================================
step_head "4" "Show the active provider condition matrix" \
  "Every simulated condition is on screen so scenarios are reproducible on demand." \
  "active condition per model (all healthy) plus all 6 supported conditions."
CMD="curl -s \$API_BASE/providers/conditions | python3 scripts/fmt.py --type conditions"
show_cmd "$CMD"
RAW="$(curl -s "$API_BASE/providers/conditions")"
OUT="$(printf '%s' "$RAW" | $FMT --type conditions 2>&1)"; emit "$OUT"
if echo "$RAW" | jq -e '(.supported|keys|sort)==["deprecation","error","healthy","quality","quota","slow"] and (.active|length==3)' >/dev/null 2>&1; then
  verdict 0 "all 6 conditions supported; 3 models show an active condition" "" ""
  LO_EO1a+=("Step 4: repeatable condition matrix (healthy/slow/error/quota/quality/deprecation)")
else
  verdict 1 "condition matrix is incomplete" \
    "Check CONDITIONS in app/providers/registry.py (must define all 6)." \
    "The /providers/conditions response must list all 6 supported conditions and an active condition per model. Fix CONDITIONS in app/providers/registry.py."
fi

# =============================================================================
# STEP 5 — Baseline request
# =============================================================================
step_head "5" "Send a baseline request through the adapter layer" \
  "One request returns a normalized decision the caller can trust." \
  "selected_model, token_estimate (prompt/completion/total), cost_estimate, provider_status."
CMD="curl -s -X POST \$API_BASE/route -H 'Content-Type: application/json' -d @data/payloads/baseline_request.json | python3 scripts/fmt.py --type route"
show_cmd "$CMD"
RAW="$(curl -s -X POST "$API_BASE/route" -H 'Content-Type: application/json' -d @"$PAYLOAD")"
OUT="$(printf '%s' "$RAW" | $FMT --type route 2>&1)"; emit "$OUT"
if echo "$RAW" | jq -e '.selected_model=="balanced-std" and .provider_status=="healthy" and .token_estimate.total>0 and .cost_estimate_usd>0 and (.request_id|length>0)' >/dev/null 2>&1; then
  verdict 0 "baseline routed to balanced-std with tokens and cost estimated" "" ""
  LO_TO1+=("Step 5: intelligent baseline routing decision with token+cost estimate")
else
  verdict 1 "baseline route response is missing required fields" \
    "Check route() in app/routing/router.py and estimate_tokens/estimate_cost in app/providers/adapter.py." \
    "POST /route must return selected_model=balanced-std, provider_status=healthy, a non-zero token_estimate.total and cost_estimate_usd, and a request_id. Fix app/routing/router.py."
fi

# =============================================================================
# STEP 6 — Query PostgreSQL receipts (decoupling proof)
# =============================================================================
step_head "6" "Query the PostgreSQL receipt to prove decoupling" \
  "A normalized receipt proves the app never depends on a provider response shape." \
  "one receipt row with the same normalized columns regardless of which model served it."
CMD="docker compose exec -T postgres psql -U genai -d genai -tAc \"SELECT row_to_json(r) FROM (SELECT selected_model,provider_tier,provider_status,prompt_tokens,completion_tokens,total_tokens,cost_estimate_usd,quality_score,policy_name,request_id FROM receipts ORDER BY created_at DESC LIMIT 1) r\" | python3 scripts/fmt.py --type receipt"
show_cmd "$CMD"
RAW="$(pg_query "$SQL_RECEIPT")"
OUT="$(printf '%s' "$RAW" | $FMT --type receipt 2>&1)"; emit "$OUT"
if echo "$RAW" | jq -e '.selected_model=="balanced-std" and .total_tokens>0 and (.request_id|length>0)' >/dev/null 2>&1; then
  verdict 0 "receipt persisted in PostgreSQL with the normalized schema" "" ""
  LO_TO1+=("Step 6: request receipt ties the routing decision to a durable record")
  LO_EO1a+=("Step 6: provider-agnostic receipt columns prove application decoupling")
else
  verdict 1 "no normalized receipt found in PostgreSQL" \
    "Ensure POST /route inserts via insert_receipt() and the receipts DDL ran (app/db/postgres.py)." \
    "Querying receipts returned no normalized row. Confirm app/main.py route_request() calls postgres.insert_receipt and the receipts table exists. Fix app/db/postgres.py."
fi

# =============================================================================
# LEARNING OBJECTIVE COVERAGE
# =============================================================================
banner "LEARNING OBJECTIVE COVERAGE"
emit "${WHITE}TO1 — Implement load balancing and intelligent request routing for${R}"
emit "${WHITE}      multi-model GenAI service architectures${R}"
if [ "${#LO_TO1[@]}" -gt 0 ]; then
  for e in "${LO_TO1[@]}"; do emit "  ${LIME}✔${R} ${GRAY}${e}${R}"; done
else
  emit "  ${PINK}✗ no evidence captured${R}"
fi
blank
emit "${WHITE}EO1a — Design a dedicated AI service layer that decouples application${R}"
emit "${WHITE}       logic from model provider dependencies and enables independent scaling${R}"
if [ "${#LO_EO1a[@]}" -gt 0 ]; then
  for e in "${LO_EO1a[@]}"; do emit "  ${LIME}✔${R} ${GRAY}${e}${R}"; done
else
  emit "  ${PINK}✗ no evidence captured${R}"
fi

# =============================================================================
# SUMMARY
# =============================================================================
banner "SUMMARY"
TOTAL=$((PASS+FAIL))
emit "  ${LIME}PASS: ${PASS}${R}   ${PINK}FAIL: ${FAIL}${R}   ${GRAY}of ${TOTAL} steps${R}"
if [ "$FAIL" = "0" ]; then
  emit "  ${LIME}✔ ALL STEPS PASSED — demo aligns with TO1 and EO1a. Ready to record.${R}"
else
  emit "  ${PINK}✗ ${FAIL} step(s) failed — fix above, reset, and re-run.${R}"
fi
blank
emit "${WHITE}PROMPT TO FIX THIS CHECK (paste into Claude if any step failed):${R}"
emit "${GRAY}\"Run bash module1/scripts/preflight_check.sh. For every step marked ✗ FAIL,${R}"
emit "${GRAY} read the HOW TO FIX and PROMPT TO FIX lines, open the named source file,${R}"
emit "${GRAY} correct the app so the step's assertion passes, then reset with${R}"
emit "${GRAY} ./scripts/module1-demo-reset.sh and re-run the preflight until PASS: 6,${R}"
emit "${GRAY} FAIL: 0. Do not change the demo steps or the learning objectives.\"${R}"
blank
emit "  ${GRAY}full readable log written to:${R} ${LGRN}module1/preflight_log.txt${R}"
exit "$FAIL"
