#!/usr/bin/env bash
# Capture the Module 3 demos exactly as they run, command + output in sequence,
# to a plain-text transcript you can hand to a reviewer. No assertions here —
# this is the raw "what appears on screen" record. For pass/fail + LO coverage
# use the clipN_preflight_check.sh scripts instead.
#
#   bash module3/scripts/capture_demo_output.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
OUT="$ROOT/module3/demo_capture.txt"
: > "$OUT"

API_BASE="${API_BASE:-http://localhost:8000}"
FMT="python3 $ROOT/scripts/fmt.py"

strip() { sed -E 's/\x1b\[[0-9;]*m//g'; }
rec() { printf '%s\n' "$*"; printf '%s\n' "$*" | strip >> "$OUT"; }
run() { # label  displayed-command  fetch-expression  fmt-type
  rec ""
  rec "### $1"
  rec "\$ $2"
  rec ""
  local data; data="$(eval "$3" 2>&1)"
  local pretty; pretty="$(printf '%s' "$data" | $FMT --type "$4" 2>&1)"
  printf '%s\n' "$pretty"
  printf '%s\n' "$pretty" | strip >> "$OUT"
}

# --- Clip 2: prompt versioning + reproducible rollback ---------------------
rec "MODULE 3 · CLIP 2 — DEMO CAPTURE (prompt versioning + reproducible rollback)"
curl -s -X POST "$API_BASE/admin/reset" >/dev/null 2>&1
curl -s -X POST "$API_BASE/lifecycle/prompts/run" >/dev/null 2>&1

run "Step 1 — Inspect the prompt version registry" \
  "curl -s -X POST \$API_BASE/lifecycle/prompts/run >/dev/null; curl -s \$API_BASE/lifecycle/prompts/registry | python3 scripts/fmt.py --type lc-registry" \
  "curl -s $API_BASE/lifecycle/prompts/registry" lc-registry
run "Step 2 — Link prompt version, model, and eval run to receipts" \
  "curl -s \$API_BASE/lifecycle/prompts/receipts | python3 scripts/fmt.py --type lc-prompt-receipts" \
  "curl -s $API_BASE/lifecycle/prompts/receipts" lc-prompt-receipts
run "Step 3 — Deploy the prompt change to an isolated lane" \
  "curl -s \$API_BASE/lifecycle/prompts/isolation | python3 scripts/fmt.py --type lc-isolation" \
  "curl -s $API_BASE/lifecycle/prompts/isolation" lc-isolation
run "Step 4 — Roll back production to the approved release" \
  "curl -s \$API_BASE/lifecycle/prompts/rollback | python3 scripts/fmt.py --type lc-rollback" \
  "curl -s $API_BASE/lifecycle/prompts/rollback" lc-rollback
run "Step 5 — Prove the rollback is reproducible" \
  "curl -s \$API_BASE/lifecycle/prompts/reproducibility | python3 scripts/fmt.py --type lc-reproducibility" \
  "curl -s $API_BASE/lifecycle/prompts/reproducibility" lc-reproducibility
run "Step 6 — Reconcile the release state" \
  "curl -s \$API_BASE/lifecycle/prompts/reconcile | python3 scripts/fmt.py --type lc-reconcile" \
  "curl -s $API_BASE/lifecycle/prompts/reconcile" lc-reconcile

# --- Clip 3: validate model updates against quality baselines --------------
rec ""
rec "MODULE 3 · CLIP 3 — DEMO CAPTURE (validate model updates against quality baselines)"
curl -s -X POST "$API_BASE/admin/reset" >/dev/null 2>&1
curl -s -X POST "$API_BASE/lifecycle/validation/run" >/dev/null 2>&1

run "Step 1 — Run the baseline gate (Pytest)" \
  "pytest tests/baseline -q; curl -s \$API_BASE/lifecycle/validation/gate | python3 scripts/fmt.py --type validation-gate" \
  "curl -s $API_BASE/lifecycle/validation/gate" validation-gate
run "Step 2 — Inspect the baseline thresholds" \
  "curl -s \$API_BASE/lifecycle/validation/baseline | python3 scripts/fmt.py --type validation-baseline" \
  "curl -s $API_BASE/lifecycle/validation/baseline" validation-baseline
run "Step 3 — Validate the passing candidate" \
  "curl -s \$API_BASE/lifecycle/validation/pass | python3 scripts/fmt.py --type validation-candidate" \
  "curl -s $API_BASE/lifecycle/validation/pass" validation-candidate
run "Step 4 — Validate the failing candidate" \
  "curl -s \$API_BASE/lifecycle/validation/fail | python3 scripts/fmt.py --type validation-candidate" \
  "curl -s $API_BASE/lifecycle/validation/fail" validation-candidate
run "Step 5 — Record the release decision" \
  "curl -s \$API_BASE/lifecycle/validation/decision | python3 scripts/fmt.py --type validation-decision" \
  "curl -s $API_BASE/lifecycle/validation/decision" validation-decision
run "Step 6 — Reconcile the release state" \
  "curl -s \$API_BASE/lifecycle/validation/reconcile | python3 scripts/fmt.py --type validation-reconcile" \
  "curl -s $API_BASE/lifecycle/validation/reconcile" validation-reconcile

# --- Clip 5: canary promotion, hold, and rollback --------------------------
rec ""
rec "MODULE 3 · CLIP 5 — DEMO CAPTURE (canary promotion, hold, and rollback)"
curl -s -X POST "$API_BASE/admin/reset" >/dev/null 2>&1
curl -s -X POST "$API_BASE/lifecycle/canary/run" >/dev/null 2>&1

run "Step 1 — Start the canary" \
  "curl -s -X POST \$API_BASE/lifecycle/canary/run >/dev/null; curl -s \$API_BASE/lifecycle/canary/start | python3 scripts/fmt.py --type canary-start" \
  "curl -s $API_BASE/lifecycle/canary/start" canary-start
run "Step 2 — Watch the canary signals" \
  "curl -s \$API_BASE/lifecycle/canary/watch | python3 scripts/fmt.py --type canary-watch" \
  "curl -s $API_BASE/lifecycle/canary/watch" canary-watch
run "Step 3 — Check the promotion criteria" \
  "curl -s \$API_BASE/lifecycle/canary/criteria | python3 scripts/fmt.py --type canary-criteria" \
  "curl -s $API_BASE/lifecycle/canary/criteria" canary-criteria
run "Step 4 — Promote the healthy canary" \
  "curl -s \$API_BASE/lifecycle/canary/promote | python3 scripts/fmt.py --type canary-promote" \
  "curl -s $API_BASE/lifecycle/canary/promote" canary-promote
run "Step 5 — Hold and roll back the degraded canary" \
  "curl -s \$API_BASE/lifecycle/canary/rollback | python3 scripts/fmt.py --type canary-rollback" \
  "curl -s $API_BASE/lifecycle/canary/rollback" canary-rollback
run "Step 6 — Reconcile after rollback" \
  "curl -s \$API_BASE/lifecycle/canary/reconcile | python3 scripts/fmt.py --type canary-reconcile" \
  "curl -s $API_BASE/lifecycle/canary/reconcile" canary-reconcile

rec ""
rec "transcript written to: module3/demo_capture.txt"
