#!/usr/bin/env bash
# Collect any legacy preflight logs into the preflight-logs/ folder.
#
# Older runs wrote loose files like module2/clip5_preflight_log.txt into each
# module root. Preflight logs now live in one place, preflight-logs/, named after
# the demo (m<module>-demo<n>-<name>.log). This script moves any legacy loose logs
# it finds into that folder under the new names. It is safe to run repeatedly —
# it only moves files that still exist, and never overwrites a newer log.
#
#   bash scripts/collect-preflight-logs.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
DEST="$ROOT/preflight-logs"
mkdir -p "$DEST"

LIME=$'\033[38;2;2;224;136m'; GRAY=$'\033[38;2;88;95;162m'
BLUE=$'\033[38;2;0;163;255m'; R=$'\033[0m'

# legacy loose path  ->  new name in preflight-logs/
map=(
  "module1/preflight_log.txt=m1-demo1-provider-adapter-layer.log"
  "module1/clip3_preflight_log.txt=m1-demo2-weighted-routing.log"
  "module1/clip5_preflight_log.txt=m1-demo3-payload-routing-and-overrides.log"
  "module1/clip6_preflight_log.txt=m1-demo4-routing-receipts-and-disposition.log"
  "module2/clip2_preflight_log.txt=m2-demo1-queues-rate-limits-failfast.log"
  "module2/clip3_preflight_log.txt=m2-demo2-circuit-breaker-fallback-retry.log"
  "module2/clip5_preflight_log.txt=m2-demo3-traces-logs-metrics-quality.log"
  "module2/clip6_preflight_log.txt=m2-demo4-diagnose-latency-quota-cost-quality.log"
  "module3/clip2_preflight_log.txt=m3-demo1-prompt-versioning-rollback.log"
  "module3/clip3_preflight_log.txt=m3-demo2-model-update-validation.log"
  "module3/clip5_preflight_log.txt=m3-demo3-canary-promotion-rollback.log"
  "module3/clip6_preflight_log.txt=m3-demo4-readiness-audit-runbook.log"
)

moved=0
for entry in "${map[@]}"; do
  src="${entry%%=*}"; dst="$DEST/${entry##*=}"
  if [ -f "$src" ]; then
    mv -f "$src" "$dst"
    echo "${LIME}moved${R} ${GRAY}${src}${R} ${BLUE}->${R} ${GRAY}preflight-logs/${entry##*=}${R}"
    moved=$((moved+1))
  fi
done

if [ "$moved" -eq 0 ]; then
  echo "${GRAY}no legacy loose logs found — nothing to move (logs already in preflight-logs/).${R}"
else
  echo "${LIME}✔ collected ${moved} legacy log(s) into preflight-logs/${R}"
fi
