#!/usr/bin/env bash
# =============================================================================
# Module 3 · Demo — Prove prompt versioning and reproducible rollback
# AUTHOR PREFLIGHT: runs every demo step in the SAME order as module3/demo/m3-demo2-prompt-versioning-rollback.md,
# captures each command and its on-screen output, asserts the output proves the
# learning objectives (TO4, EO4a), and writes a readable log.
#
#   bash module3/scripts/m3-demo2-prompt-versioning-rollback.preflight.sh
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
LOG="$ROOT/preflight-logs/m3-demo2-prompt-versioning-rollback.log"
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
    emit "${GRAY}  do NOT edit app/lifecycle/prompts.py. Start the stack, then re-run:${R}"
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

# Emit a TRANSPORT failure verdict — points at the stack, never at prompts.py.
transport_fail() {  # $1 = path(s) that failed
  verdict 1 "TRANSPORT — could not read $1 with HTTP 200 (service down or route missing)" \
    "Confirm the stack is up: curl \$API_BASE/health must be 200 and curl \$API_BASE/openapi.json must list /lifecycle/prompts/*." \
    "Bring up FastAPI/Redis/Postgres (bash module3/scripts/demo_up.sh) and re-run. This is a service/transport failure — do NOT edit app/lifecycle/prompts.py."
}

banner "MODULE 3 · DEMO — PROMPT VERSIONING AND REPRODUCIBLE ROLLBACK  (LO: TO4, EO4a)"
emit "${GRAY}stack:${R} API=${LGRN}${API_BASE}${R}"
require_stack
emit "${GRAY}reading the prompt repository and building the lifecycle state ...${R}"
curl -s -X POST "$API_BASE/admin/reset" >/dev/null 2>&1
SEED_CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API_BASE/lifecycle/prompts/run" 2>/dev/null)
if [ "$SEED_CODE" != "200" ]; then
  emit "${PINK}✗ SEEDING FAILED — POST ${API_BASE}/lifecycle/prompts/run returned HTTP ${SEED_CODE:-000}.${R}"
  emit "${GRAY}  No lifecycle state was built, so every downstream read would be empty. This is a${R}"
  emit "${GRAY}  routing/transport failure, not a logic bug — do NOT edit app/lifecycle/prompts.py.${R}"
  exit 2
fi

# STEP 1 — source-controlled registry.yaml + runtime registry + receipts
step_head "1" "Inspect the source-controlled registry and link receipts to releases" \
  "The registry must be a source-controlled file (prompts/registry.yaml) with owner/fixture/model/eval/release/status, the service must read that same registry, and every receipt must carry the release identity." \
  "the raw prompts/registry.yaml source with full metadata, then the same registry via the service, then the one release identity every request carries plus the request ids stamped with it."
# 1a — the source-controlled manifest (a real file in the repo)
show_cmd "grep -vE '^[[:space:]]*(#|file:|created:|notes:)' prompts/registry.yaml | sed -E 's/[[:space:]]+#.*\$//;/^[[:space:]]*\$/d'"
REGYAML="$ROOT/prompts/registry.yaml"
[ -f "$REGYAML" ] && emit "${GRAY}$(grep -vE '^[[:space:]]*(#|file:|created:|notes:)' "$REGYAML" | sed -E 's/[[:space:]]+#.*$//;/^[[:space:]]*$/d')${R}"
SRC_OK=1
{ [ -f "$REGYAML" ] \
  && grep -q "prompt_id: support_summary" "$REGYAML" \
  && grep -q "approved_release: rel-2026.06" "$REGYAML" \
  && grep -q "owner:" "$REGYAML" && grep -q "fixture:" "$REGYAML" \
  && grep -q "model_version:" "$REGYAML" && grep -q "eval_run_id:" "$REGYAML" \
  && grep -q "release_tag:" "$REGYAML" \
  && grep -q "status: approved" "$REGYAML" && grep -q "status: candidate" "$REGYAML" \
  && grep -q "status: superseded" "$REGYAML" ; } || SRC_OK=0
# 1b — the same registry read through the service
show_cmd "curl -s \$API_BASE/lifecycle/prompts/registry | python3 scripts/fmt.py --type lc-registry"
get_json "/lifecycle/prompts/registry" && RAW_REG="$GET_BODY" || RAW_REG=""
[ -n "$RAW_REG" ] && emit "$(printf '%s' "$RAW_REG" | $FMT --type lc-registry 2>&1)"
# 1c — receipts carry the release identity
show_cmd "curl -s \$API_BASE/lifecycle/prompts/receipts | python3 scripts/fmt.py --type lc-prompt-receipts"
get_json "/lifecycle/prompts/receipts" && RAW_RCP="$GET_BODY" || RAW_RCP=""
[ -n "$RAW_RCP" ] && emit "$(printf '%s' "$RAW_RCP" | $FMT --type lc-prompt-receipts 2>&1)"
if [ -z "$RAW_REG" ] || [ -z "$RAW_RCP" ]; then
  transport_fail "/lifecycle/prompts/registry or /receipts"
else
  REG_OK=1; RCP_OK=1
  echo "$RAW_REG" | jq -e '(.versions|length>=3) and (.approved_release=="rel-2026.06") and ([.versions[].status]|(index("approved") and index("candidate") and index("superseded"))) and (.versions|all(has("model_version") and has("eval_run_id") and has("result_hash")))' >/dev/null 2>&1 || REG_OK=0
  echo "$RAW_RCP" | jq -e '(.receipts|length>=1) and (.approved_version=="v2.0.0") and (.receipts|all(.prompt_version=="v2.0.0" and has("model_version") and has("eval_run_id") and has("release_tag") and has("result_hash")))' >/dev/null 2>&1 || RCP_OK=0
  if [ "$SRC_OK" = "1" ] && [ "$REG_OK" = "1" ] && [ "$RCP_OK" = "1" ]; then
    verdict 0 "prompts/registry.yaml is a source-controlled manifest with full metadata, the service reads the same registry, and every receipt links prompt version, model version, and eval run id to a release and result hash" "" ""
    LO+=("Step 1: source-controlled prompt registry — versioned like code with full metadata (EO4a)")
    LO+=("Step 1: receipts link prompt version, model version, and eval run id (EO4a)")
  else
    verdict 1 "the source registry file, the runtime registry, or the receipts are wrong" \
      "Check prompts/registry.yaml (owner/fixture/model_version/eval_run_id/release_tag/status per version) and the registry/receipts blocks in app/lifecycle/prompts.py." \
      "prompts/registry.yaml must exist with prompt_id support_summary, approved_release rel-2026.06, and versions carrying owner/fixture/model_version/eval_run_id/release_tag and status approved/candidate/superseded; GET /lifecycle/prompts/registry must list >=3 versions each with model_version/eval_run_id/result_hash; GET /lifecycle/prompts/receipts must be all on v2.0.0 with model_version, eval_run_id, release_tag, result_hash. Fix prompts/registry.yaml or app/lifecycle/prompts.py."
  fi
fi

# STEP 2 — candidate isolated
step_head "2" "Deploy the prompt change to an isolated lane" \
  "A candidate prompt must be isolated so approved production traffic never reaches it." \
  "two lanes — production on the approved version, an isolated candidate lane; zero candidate traffic in production."
show_cmd "curl -s \$API_BASE/lifecycle/prompts/isolation | python3 scripts/fmt.py --type lc-isolation"
get_json "/lifecycle/prompts/isolation" && RAW="$GET_BODY" || RAW=""
if [ -z "$RAW" ]; then
  transport_fail "/lifecycle/prompts/isolation"
else
  emit "$(printf '%s' "$RAW" | $FMT --type lc-isolation 2>&1)"
  if echo "$RAW" | jq -e '.candidate_in_production==0 and .isolated==true and (.lanes|length==2) and ((.lanes[]|select(.lane=="production").serves_customers)==true) and ((.lanes[]|select(.lane=="isolated_candidate").serves_customers)==false)' >/dev/null 2>&1; then
    verdict 0 "the candidate runs in an isolated lane with zero production traffic — blast radius is nil" "" ""
    LO+=("Step 2: a candidate change is isolated from approved production traffic (EO4a)")
  else
    verdict 1 "the candidate is not isolated" \
      "Check the isolation block in app/lifecycle/prompts.py." \
      "GET /lifecycle/prompts/isolation must show candidate_in_production 0, isolated true, production lane serves_customers true, candidate lane false. Fix app/lifecycle/prompts.py."
  fi
fi

# STEP 3 — rollback to approved + fresh post-rollback receipt + reproducibility
step_head "3" "Roll back to the approved release and prove it reproduces" \
  "A rollback must return production to the approved release id (a retained immutable version), a fresh request after the rollback must receipt on the approved release, and the preserved prompt/fixture/model must reproduce the same result hash." \
  "from the candidate to the approved version, then a fresh request whose receipt lands on rel-2026.06, then recorded and replayed hashes match and reproducible is true."
show_cmd "curl -s \$API_BASE/lifecycle/prompts/rollback | python3 scripts/fmt.py --type lc-rollback"
get_json "/lifecycle/prompts/rollback" && RAW_RB="$GET_BODY" || RAW_RB=""
[ -n "$RAW_RB" ] && emit "$(printf '%s' "$RAW_RB" | $FMT --type lc-rollback 2>&1)"
show_cmd "curl -s \$API_BASE/lifecycle/prompts/post-rollback-receipt | python3 scripts/fmt.py --type lc-post-rollback-receipt"
get_json "/lifecycle/prompts/post-rollback-receipt" && RAW_PRR="$GET_BODY" || RAW_PRR=""
[ -n "$RAW_PRR" ] && emit "$(printf '%s' "$RAW_PRR" | $FMT --type lc-post-rollback-receipt 2>&1)"
show_cmd "curl -s \$API_BASE/lifecycle/prompts/reproducibility | python3 scripts/fmt.py --type lc-reproducibility"
get_json "/lifecycle/prompts/reproducibility" && RAW_RP="$GET_BODY" || RAW_RP=""
[ -n "$RAW_RP" ] && emit "$(printf '%s' "$RAW_RP" | $FMT --type lc-reproducibility 2>&1)"
if [ -z "$RAW_RB" ] || [ -z "$RAW_PRR" ] || [ -z "$RAW_RP" ]; then
  transport_fail "/lifecycle/prompts/rollback, /post-rollback-receipt or /reproducibility"
else
  RB_OK=1; PRR_OK=1; RP_OK=1
  echo "$RAW_RB" | jq -e '.to_release=="rel-2026.06" and .active_release_after=="rel-2026.06" and .active_version_after=="v2.0.0" and .candidate_in_production_after==0 and ([.retained_versions[]]|index("v3.0.0-rc1"))' >/dev/null 2>&1 || RB_OK=0
  echo "$RAW_PRR" | jq -e '.on_approved_release==true and .prompt_version=="v2.0.0" and .release_tag=="rel-2026.06" and (.request_id|test("req-pv-")) and .sent_after=="rollback"' >/dev/null 2>&1 || PRR_OK=0
  echo "$RAW_RP" | jq -e '.reproducible==true and (.recorded_result_hash==.replayed_result_hash) and ([.preserved[]]|(index("prompt_text") and index("fixture") and index("model_version")))' >/dev/null 2>&1 || RP_OK=0
  if [ "$RB_OK" = "1" ] && [ "$PRR_OK" = "1" ] && [ "$RP_OK" = "1" ]; then
    verdict 0 "rollback returns production to the approved release id (candidate retained), a fresh post-rollback request's receipt lands on the approved release rel-2026.06, and the same prompt, fixture, and model reproduce the same result hash" "" ""
    LO+=("Step 3: safe rollback to the approved release id, proven by a fresh post-rollback receipt on rel-2026.06 (EO4a)")
    LO+=("Step 3: rollback is reproducible because prompt, fixture, model, and result are preserved (EO4a)")
  else
    verdict 1 "the rollback, the fresh post-rollback receipt, or reproducibility is wrong" \
      "Check the rollback, post_rollback_receipt, and reproducibility blocks (and _result_hash) in app/lifecycle/prompts.py." \
      "GET /lifecycle/prompts/rollback must show to_release/active_release_after rel-2026.06, active_version_after v2.0.0, candidate_in_production_after 0, candidate retained; GET /lifecycle/prompts/post-rollback-receipt must show on_approved_release true, prompt_version v2.0.0, release_tag rel-2026.06, sent_after rollback; GET /lifecycle/prompts/reproducibility must show reproducible true with recorded==replayed hash and preserved prompt_text/fixture/model_version. Fix app/lifecycle/prompts.py."
  fi
fi

# STEP 4 — reconcile
step_head "4" "Reconcile the release state" \
  "The active release must match approved, with no candidate traffic in production and a reproducible result." \
  "disposition CONFIRMED: active matches approved, candidate in production 0, reproducible true."
show_cmd "curl -s \$API_BASE/lifecycle/prompts/reconcile | python3 scripts/fmt.py --type lc-reconcile"
get_json "/lifecycle/prompts/reconcile" && RAW="$GET_BODY" || RAW=""
if [ -z "$RAW" ]; then
  transport_fail "/lifecycle/prompts/reconcile"
else
  emit "$(printf '%s' "$RAW" | $FMT --type lc-reconcile 2>&1)"
  if echo "$RAW" | jq -e '.disposition=="CONFIRMED" and .active_matches_approved==true and .candidate_in_production==0 and .reproducible==true' >/dev/null 2>&1; then
    verdict 0 "the release state is provable: on the approved release, no leaked candidate traffic, reproducible" "" ""
    LO+=("Step 4: the release state reconciles to a provable, approved production state (TO4, EO4a)")
  else
    verdict 1 "the release state did not reconcile" \
      "Check the reconcile block in app/lifecycle/prompts.py." \
      "GET /lifecycle/prompts/reconcile must return disposition CONFIRMED with active_matches_approved true, candidate_in_production 0, reproducible true. Fix app/lifecycle/prompts.py."
  fi
fi

# COVERAGE + SUMMARY
banner "LEARNING OBJECTIVE COVERAGE"
emit "${WHITE}TO4, EO4a — Version prompts like code, link every receipt to a release${R}"
emit "${WHITE}       identity, isolate a candidate change, roll back to the approved${R}"
emit "${WHITE}       release, and prove the rollback is reproducible.${R}"
if [ "${#LO[@]}" -gt 0 ]; then for e in "${LO[@]}"; do emit "  ${LIME}✔${R} ${GRAY}${e}${R}"; done; else emit "  ${PINK}✗ no evidence captured${R}"; fi

banner "SUMMARY"
TOTAL=$((PASS+FAIL))
emit "  ${LIME}PASS: ${PASS}${R}   ${PINK}FAIL: ${FAIL}${R}   ${GRAY}of ${TOTAL} steps${R}"
if [ "$FAIL" = "0" ]; then
  emit "  ${LIME}✔ ALL STEPS PASSED — demo aligns with TO4, EO4a. Ready to record.${R}"
else
  emit "  ${PINK}✗ ${FAIL} step(s) failed — fix above, reset, and re-run.${R}"
fi
blank
emit "  ${GRAY}full readable log written to:${R} ${LGRN}preflight-logs/m3-demo2-prompt-versioning-rollback.log${R}"
exit "$FAIL"
