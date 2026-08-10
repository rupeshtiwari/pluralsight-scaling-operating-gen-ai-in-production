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

banner "MODULE 3 · DEMO — PROMPT VERSIONING AND REPRODUCIBLE ROLLBACK  (LO: TO4, EO4a)"
emit "${GRAY}stack:${R} API=${LGRN}${API_BASE}${R}"
emit "${GRAY}reading the prompt repository and building the lifecycle state ...${R}"
curl -s -X POST "$API_BASE/admin/reset" >/dev/null 2>&1
curl -s -X POST "$API_BASE/lifecycle/prompts/run" >/dev/null 2>&1

# STEP 1 — registry + receipts (versioned like code, and every receipt links the release identity)
step_head "1" "Inspect the version registry and link receipts to releases" \
  "Prompts must be versioned like code with owner/fixture/model/eval/release/status, and every receipt must carry that release identity." \
  "three versions — superseded, approved, candidate — with metadata and hash, then six receipts on the approved version carrying model, eval run, release, and hash."
show_cmd "curl -s -X POST \$API_BASE/lifecycle/prompts/run >/dev/null; curl -s \$API_BASE/lifecycle/prompts/registry | python3 scripts/fmt.py --type lc-registry"
RAW_REG="$(curl -s "$API_BASE/lifecycle/prompts/registry")"
emit "$(printf '%s' "$RAW_REG" | $FMT --type lc-registry 2>&1)"
show_cmd "curl -s \$API_BASE/lifecycle/prompts/receipts | python3 scripts/fmt.py --type lc-prompt-receipts"
RAW_RCP="$(curl -s "$API_BASE/lifecycle/prompts/receipts")"
emit "$(printf '%s' "$RAW_RCP" | $FMT --type lc-prompt-receipts 2>&1)"
REG_OK=1; RCP_OK=1
echo "$RAW_REG" | jq -e '(.versions|length>=3) and (.approved_release=="rel-2026.06") and ([.versions[].status]|(index("approved") and index("candidate") and index("superseded"))) and (.versions|all(has("model_version") and has("eval_run_id") and has("result_hash")))' >/dev/null 2>&1 || REG_OK=0
echo "$RAW_RCP" | jq -e '(.receipts|length>=1) and (.approved_version=="v2.0.0") and (.receipts|all(.prompt_version=="v2.0.0" and has("model_version") and has("eval_run_id") and has("release_tag") and has("result_hash")))' >/dev/null 2>&1 || RCP_OK=0
if [ "$REG_OK" = "1" ] && [ "$RCP_OK" = "1" ]; then
  verdict 0 "the registry lists versions with full metadata, and every receipt links prompt version, model version, and evaluation run id to a release and result hash" "" ""
  LO+=("Step 1: prompt version control — versioned like code with full metadata (EO4a)")
  LO+=("Step 1: receipts link prompt version, model version, and eval run id (EO4a)")
else
  verdict 1 "the registry or receipts do not carry the release identity" \
    "Check prompts/registry.yaml, _version_records, and the receipts block in app/lifecycle/prompts.py." \
    "GET /lifecycle/prompts/registry must list >=3 versions (approved/candidate/superseded, each with model_version/eval_run_id/result_hash) and approved_release rel-2026.06; GET /lifecycle/prompts/receipts must return receipts all on v2.0.0 with model_version, eval_run_id, release_tag, result_hash. Fix app/lifecycle/prompts.py."
fi

# STEP 2 — candidate isolated
step_head "2" "Deploy the prompt change to an isolated lane" \
  "A candidate prompt must be isolated so approved production traffic never reaches it." \
  "two lanes — production on the approved version, an isolated candidate lane; zero candidate traffic in production."
show_cmd "curl -s \$API_BASE/lifecycle/prompts/isolation | python3 scripts/fmt.py --type lc-isolation"
RAW="$(curl -s "$API_BASE/lifecycle/prompts/isolation")"
emit "$(printf '%s' "$RAW" | $FMT --type lc-isolation 2>&1)"
if echo "$RAW" | jq -e '.candidate_in_production==0 and .isolated==true and (.lanes|length==2) and ((.lanes[]|select(.lane=="production").serves_customers)==true) and ((.lanes[]|select(.lane=="isolated_candidate").serves_customers)==false)' >/dev/null 2>&1; then
  verdict 0 "the candidate runs in an isolated lane with zero production traffic — blast radius is nil" "" ""
  LO+=("Step 2: a candidate change is isolated from approved production traffic (EO4a)")
else
  verdict 1 "the candidate is not isolated" \
    "Check the isolation block in app/lifecycle/prompts.py." \
    "GET /lifecycle/prompts/isolation must show candidate_in_production 0, isolated true, production lane serves_customers true, candidate lane false. Fix app/lifecycle/prompts.py."
fi

# STEP 3 — rollback to approved + reproducibility
step_head "3" "Roll back to the approved release and prove it reproduces" \
  "A rollback must return production to the approved release id (a retained immutable version), and the preserved prompt/fixture/model must reproduce the same result hash." \
  "from the candidate to the approved version, active release rel-2026.06 with zero candidate traffic, then recorded and replayed hashes match and reproducible is true."
show_cmd "curl -s \$API_BASE/lifecycle/prompts/rollback | python3 scripts/fmt.py --type lc-rollback"
RAW_RB="$(curl -s "$API_BASE/lifecycle/prompts/rollback")"
emit "$(printf '%s' "$RAW_RB" | $FMT --type lc-rollback 2>&1)"
show_cmd "curl -s \$API_BASE/lifecycle/prompts/reproducibility | python3 scripts/fmt.py --type lc-reproducibility"
RAW_RP="$(curl -s "$API_BASE/lifecycle/prompts/reproducibility")"
emit "$(printf '%s' "$RAW_RP" | $FMT --type lc-reproducibility 2>&1)"
RB_OK=1; RP_OK=1
echo "$RAW_RB" | jq -e '.to_release=="rel-2026.06" and .active_release_after=="rel-2026.06" and .active_version_after=="v2.0.0" and .candidate_in_production_after==0 and ([.retained_versions[]]|index("v3.0.0-rc1"))' >/dev/null 2>&1 || RB_OK=0
echo "$RAW_RP" | jq -e '.reproducible==true and (.recorded_result_hash==.replayed_result_hash) and ([.preserved[]]|(index("prompt_text") and index("fixture") and index("model_version")))' >/dev/null 2>&1 || RP_OK=0
if [ "$RB_OK" = "1" ] && [ "$RP_OK" = "1" ]; then
  verdict 0 "rollback returns production to the approved release id (candidate retained but withdrawn), and the same prompt, fixture, and model reproduce the same result hash" "" ""
  LO+=("Step 3: safe rollback returns production to the approved release id (EO4a)")
  LO+=("Step 3: rollback is reproducible because prompt, fixture, model, and result are preserved (EO4a)")
else
  verdict 1 "the rollback did not return to the approved release or is not reproducible" \
    "Check the rollback and reproducibility blocks (and _result_hash) in app/lifecycle/prompts.py." \
    "GET /lifecycle/prompts/rollback must show to_release/active_release_after rel-2026.06, active_version_after v2.0.0, candidate_in_production_after 0, candidate retained; GET /lifecycle/prompts/reproducibility must show reproducible true with recorded==replayed hash and preserved prompt_text/fixture/model_version. Fix app/lifecycle/prompts.py."
fi

# STEP 4 — reconcile
step_head "4" "Reconcile the release state" \
  "The active release must match approved, with no candidate traffic in production and a reproducible result." \
  "disposition CONFIRMED: active matches approved, candidate in production 0, reproducible true."
show_cmd "curl -s \$API_BASE/lifecycle/prompts/reconcile | python3 scripts/fmt.py --type lc-reconcile"
RAW="$(curl -s "$API_BASE/lifecycle/prompts/reconcile")"
emit "$(printf '%s' "$RAW" | $FMT --type lc-reconcile 2>&1)"
if echo "$RAW" | jq -e '.disposition=="CONFIRMED" and .active_matches_approved==true and .candidate_in_production==0 and .reproducible==true' >/dev/null 2>&1; then
  verdict 0 "the release state is provable: on the approved release, no leaked candidate traffic, reproducible" "" ""
  LO+=("Step 4: the release state reconciles to a provable, approved production state (TO4, EO4a)")
else
  verdict 1 "the release state did not reconcile" \
    "Check the reconcile block in app/lifecycle/prompts.py." \
    "GET /lifecycle/prompts/reconcile must return disposition CONFIRMED with active_matches_approved true, candidate_in_production 0, reproducible true. Fix app/lifecycle/prompts.py."
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
