#!/usr/bin/env bash
# =============================================================================
# Module 3 · Demo — Prove prompt versioning and reproducible rollback
# AUTHOR PREFLIGHT: runs every demo step in the SAME order as module3/demo/clip2.md,
# captures each command and its on-screen output, asserts the output proves the
# learning objectives (TO4, EO4a), and writes a readable log.
#
#   bash module3/scripts/clip2_preflight_check.sh
#
# Defaults target Docker Compose on macOS; override with env vars for a native
# stack: API_BASE
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
LOG="$ROOT/module3/clip2_preflight_log.txt"
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

banner "MODULE 3 · DEMO — PROMPT VERSIONING AND REPRODUCIBLE ROLLBACK  (LO: TO4, EO4a)"
emit "${GRAY}stack:${R} API=${LGRN}${API_BASE}${R}"
emit "${GRAY}reading the prompt repository and building the lifecycle state ...${R}"
curl -s -X POST "$API_BASE/admin/reset" >/dev/null 2>&1
curl -s -X POST "$API_BASE/lifecycle/prompts/run" >/dev/null 2>&1

# STEP 1 — prompt registry
step_head "1" "Inspect the prompt version registry" \
  "Prompts must be versioned like code, with owner, fixture, model pin, eval run, release tag, status." \
  "three versions — superseded, approved, candidate — each with its metadata and result hash."
show_cmd "curl -s -X POST \$API_BASE/lifecycle/prompts/run >/dev/null; curl -s \$API_BASE/lifecycle/prompts/registry | python3 scripts/fmt.py --type lc-registry"
RAW="$(curl -s "$API_BASE/lifecycle/prompts/registry")"
emit "$(printf '%s' "$RAW" | $FMT --type lc-registry 2>&1)"
if echo "$RAW" | jq -e '(.versions|length>=3) and (.approved_release=="rel-2026.06") and ([.versions[].status]|(index("approved") and index("candidate") and index("superseded"))) and (.versions|all(has("model_version") and has("eval_run_id") and has("result_hash")))' >/dev/null 2>&1; then
  verdict 0 "the registry lists versions with owner, fixture, model, eval run, release tag, and status" "" ""
  LO+=("Step 1: prompt version control — versioned like code with full metadata (EO4a)")
else
  verdict 1 "the prompt registry is wrong" \
    "Check prompts/registry.yaml and _version_records in app/lifecycle/prompts.py." \
    "GET /lifecycle/prompts/registry must list >=3 versions, approved_release rel-2026.06, statuses approved/candidate/superseded, each with model_version, eval_run_id, result_hash. Fix app/lifecycle/prompts.py."
fi

# STEP 2 — receipts link version + model + eval
step_head "2" "Link prompt version, model, and eval run to receipts" \
  "Every request receipt must carry the release identity: prompt version, model version, eval run, release, hash." \
  "six receipts, each on the approved version with its model, eval run, release tag, and result hash."
show_cmd "curl -s \$API_BASE/lifecycle/prompts/receipts | python3 scripts/fmt.py --type lc-prompt-receipts"
RAW="$(curl -s "$API_BASE/lifecycle/prompts/receipts")"
emit "$(printf '%s' "$RAW" | $FMT --type lc-prompt-receipts 2>&1)"
if echo "$RAW" | jq -e '(.receipts|length>=1) and (.approved_version=="v2.0.0") and (.receipts|all(.prompt_version=="v2.0.0" and has("model_version") and has("eval_run_id") and has("release_tag") and has("result_hash")))' >/dev/null 2>&1; then
  verdict 0 "every receipt links prompt version, model version, and evaluation run id to a release and result hash" "" ""
  LO+=("Step 2: receipts link prompt version, model version, and eval run id (EO4a)")
else
  verdict 1 "receipts do not carry the release identity" \
    "Check the receipts block in app/lifecycle/prompts.py." \
    "GET /lifecycle/prompts/receipts must return receipts all on v2.0.0 with model_version, eval_run_id, release_tag, result_hash. Fix app/lifecycle/prompts.py."
fi

# STEP 3 — candidate isolated
step_head "3" "Deploy the prompt change to an isolated lane" \
  "A candidate prompt must be isolated so approved production traffic never reaches it." \
  "two lanes — production on the approved version, an isolated candidate lane; zero candidate traffic in production."
show_cmd "curl -s \$API_BASE/lifecycle/prompts/isolation | python3 scripts/fmt.py --type lc-isolation"
RAW="$(curl -s "$API_BASE/lifecycle/prompts/isolation")"
emit "$(printf '%s' "$RAW" | $FMT --type lc-isolation 2>&1)"
if echo "$RAW" | jq -e '.candidate_in_production==0 and .isolated==true and (.lanes|length==2) and ((.lanes[]|select(.lane=="production").serves_customers)==true) and ((.lanes[]|select(.lane=="isolated_candidate").serves_customers)==false)' >/dev/null 2>&1; then
  verdict 0 "the candidate runs in an isolated lane with zero production traffic — blast radius is nil" "" ""
  LO+=("Step 3: a candidate change is isolated from approved production traffic (EO4a)")
else
  verdict 1 "the candidate is not isolated" \
    "Check the isolation block in app/lifecycle/prompts.py." \
    "GET /lifecycle/prompts/isolation must show candidate_in_production 0, isolated true, production lane serves_customers true, candidate lane false. Fix app/lifecycle/prompts.py."
fi

# STEP 4 — rollback to approved
step_head "4" "Roll back production to the approved release" \
  "A rollback must return production to the approved release id, targeting a retained immutable version." \
  "from the candidate to the approved version; active release rel-2026.06, zero candidate traffic after."
show_cmd "curl -s \$API_BASE/lifecycle/prompts/rollback | python3 scripts/fmt.py --type lc-rollback"
RAW="$(curl -s "$API_BASE/lifecycle/prompts/rollback")"
emit "$(printf '%s' "$RAW" | $FMT --type lc-rollback 2>&1)"
if echo "$RAW" | jq -e '.to_release=="rel-2026.06" and .active_release_after=="rel-2026.06" and .active_version_after=="v2.0.0" and .candidate_in_production_after==0 and ([.retained_versions[]]|index("v3.0.0-rc1"))' >/dev/null 2>&1; then
  verdict 0 "rollback returns production to the approved release id, with the candidate retained but withdrawn" "" ""
  LO+=("Step 4: safe rollback returns production to the approved release id (EO4a)")
else
  verdict 1 "the rollback did not return to the approved release" \
    "Check the rollback block in app/lifecycle/prompts.py." \
    "GET /lifecycle/prompts/rollback must show to_release/active_release_after rel-2026.06, active_version_after v2.0.0, candidate_in_production_after 0, candidate retained. Fix app/lifecycle/prompts.py."
fi

# STEP 5 — reproducibility
step_head "5" "Prove the rollback is reproducible" \
  "Preserved prompt, fixture, and model must reproduce the same result hash on replay." \
  "the recorded and replayed result hashes match; reproducible is true."
show_cmd "curl -s \$API_BASE/lifecycle/prompts/reproducibility | python3 scripts/fmt.py --type lc-reproducibility"
RAW="$(curl -s "$API_BASE/lifecycle/prompts/reproducibility")"
emit "$(printf '%s' "$RAW" | $FMT --type lc-reproducibility 2>&1)"
if echo "$RAW" | jq -e '.reproducible==true and (.recorded_result_hash==.replayed_result_hash) and ([.preserved[]]|(index("prompt_text") and index("fixture") and index("model_version")))' >/dev/null 2>&1; then
  verdict 0 "the same prompt, fixture, and model reproduce the same result hash — reproducible, not re-run" "" ""
  LO+=("Step 5: rollback is reproducible because prompt, fixture, model, and result are preserved (EO4a)")
else
  verdict 1 "the rollback is not reproducible" \
    "Check _result_hash and the reproducibility block in app/lifecycle/prompts.py." \
    "GET /lifecycle/prompts/reproducibility must show reproducible true with recorded==replayed hash and preserved prompt_text/fixture/model_version. Fix app/lifecycle/prompts.py."
fi

# STEP 6 — reconcile
step_head "6" "Reconcile the release state" \
  "The active release must match approved, with no candidate traffic in production and a reproducible result." \
  "disposition CONFIRMED: active matches approved, candidate in production 0, reproducible true."
show_cmd "curl -s \$API_BASE/lifecycle/prompts/reconcile | python3 scripts/fmt.py --type lc-reconcile"
RAW="$(curl -s "$API_BASE/lifecycle/prompts/reconcile")"
emit "$(printf '%s' "$RAW" | $FMT --type lc-reconcile 2>&1)"
if echo "$RAW" | jq -e '.disposition=="CONFIRMED" and .active_matches_approved==true and .candidate_in_production==0 and .reproducible==true' >/dev/null 2>&1; then
  verdict 0 "the release state is provable: on the approved release, no leaked candidate traffic, reproducible" "" ""
  LO+=("Step 6: the release state reconciles to a provable, approved production state (TO4, EO4a)")
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
emit "  ${GRAY}full readable log written to:${R} ${LGRN}module3/clip2_preflight_log.txt${R}"
exit "$FAIL"
