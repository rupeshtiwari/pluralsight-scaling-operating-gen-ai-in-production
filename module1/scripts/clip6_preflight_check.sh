#!/usr/bin/env bash
# =============================================================================
# Module 1 · Demo — Validate routing receipts, counters, and final disposition
# AUTHOR PREFLIGHT: runs every demo step in the SAME order as module1/demo/clip6.md,
# captures each command and its on-screen output, asserts the output proves the
# learning objectives (TO1, EO1a-d), and writes a readable log for a reviewer.
#
#   bash module1/scripts/clip6_preflight_check.sh
#
# Defaults target Docker Compose on macOS; override with env vars for a native
# stack: API_BASE, PGHOST, PGPORT, PGUSER, PGDATABASE, PGPASSWORD
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
LOG="$ROOT/module1/clip6_preflight_log.txt"
: > "$LOG"

API_BASE="${API_BASE:-http://localhost:8000}"
export PGHOST="${PGHOST:-localhost}"; export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-genai}"; export PGDATABASE="${PGDATABASE:-genai}"
export PGPASSWORD="${PGPASSWORD:-genai}"
FMT="python3 $ROOT/scripts/fmt.py"

pg_query() {
  local sql="$1" out
  out="$(docker compose exec -T postgres psql -U "${PGUSER:-genai}" -d "${PGDATABASE:-genai}" -tAc "$sql" 2>/dev/null)"
  [ -z "$out" ] && out="$(psql -tAc "$sql" 2>/dev/null)"
  printf '%s' "$out"
}
redis_query() {
  local out
  out="$(docker compose exec -T redis redis-cli "$@" 2>/dev/null)"
  [ -z "$out" ] && out="$(redis-cli "$@" 2>/dev/null)"
  printf '%s' "$out"
}
FIELDS="request_id,policy_name,provider_tier,latency_target_ms,total_tokens,cost_estimate_usd,quality_score"
SQL_RECEIPTS="SELECT row_to_json(r) FROM ((SELECT 'weighted' AS kind,$FIELDS FROM receipts WHERE route_reason='weighted_distribution' LIMIT 2) UNION ALL (SELECT 'payload' AS kind,$FIELDS FROM receipts WHERE route_reason LIKE 'complexity_%' LIMIT 2) UNION ALL (SELECT 'override' AS kind,$FIELDS FROM receipts WHERE route_reason LIKE 'override_%' LIMIT 2)) r"

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

banner "MODULE 1 · DEMO — VALIDATE RECEIPTS, COUNTERS, AND FINAL DISPOSITION  (LO: TO1, EO1a-d)"
emit "${GRAY}stack:${R} API=${LGRN}${API_BASE}${R}  PG=${LGRN}${PGHOST}:${PGPORT}/${PGDATABASE}${R}"
emit "${GRAY}resetting to a clean, repeatable state ...${R}"
curl -s -X POST "$API_BASE/admin/reset" >/dev/null 2>&1

# STEP 1 — mixed batch
step_head "1" "Run the mixed routing batch" \
  "One service must run weighted, payload, and override traffic together." \
  "total 16, and weighted 10, payload 4, override 2 (the declared test population)."
show_cmd "curl -s -X POST \$API_BASE/route/mixed | python3 scripts/fmt.py --type mixed"
RAW="$(curl -s -X POST "$API_BASE/route/mixed")"
emit "$(printf '%s' "$RAW" | $FMT --type mixed 2>&1)"
if echo "$RAW" | jq -e '.total==16 and .by_kind.weighted==10 and .by_kind.payload==4 and .by_kind.override==2' >/dev/null 2>&1; then
  verdict 0 "mixed batch routed 16 across weighted/payload/override (10/4/2)" "" ""
  LO+=("Step 1: one service composes weighted, payload, and override routing (TO1, EO1b-d)")
else
  verdict 1 "mixed batch did not route the expected mix" \
    "Check POST /route/mixed in app/main.py — 10 weighted + 4 payload + 2 override." \
    "POST /route/mixed must return total=16 with by_kind weighted=10, payload=4, override=2. Fix app/main.py route_mixed()."
fi

# STEP 2 — representative samples (span kinds + policy shown)
step_head "2" "Inspect representative routing decisions" \
  "Each request must be tagged with kind, policy, model, and route reason — all three kinds visible." \
  "samples spanning weighted, payload, and override, each with its policy and route reason."
show_cmd "curl -s \$API_BASE/routing/mixed-batch?limit=6 | python3 scripts/fmt.py --type mixed-samples"
RAW="$(curl -s "$API_BASE/routing/mixed-batch?limit=6")"
emit "$(printf '%s' "$RAW" | $FMT --type mixed-samples 2>&1)"
if echo "$RAW" | jq -e '([.samples[].kind]|unique|(index("weighted") and index("payload") and index("override"))) and (.samples|all(has("policy_name") and has("route_reason")))' >/dev/null 2>&1; then
  verdict 0 "the 6 shown samples span all three kinds, each carrying policy and route reason" "" ""
  LO+=("Step 2: per-request proof — kind, policy, and route reason for weighted, payload, and override (TO1, EO1a, EO1c, EO1d)")
else
  verdict 1 "samples do not visibly span all kinds with policy + route reason" \
    "Check the interleave in route_mixed() and the mixed-samples fields (kind, policy_name, route_reason)." \
    "GET /routing/mixed-batch?limit=6 must show weighted, payload, AND override rows, each with policy_name and route_reason. Fix app/main.py route_mixed()."
fi

# STEP 3 — redis aggregate matches
step_head "3" "Verify the fast aggregate in Redis" \
  "The datastore's per-kind tally must match the API summary." \
  "total 16, and weighted 10, payload 4, override 2 read from the hash."
show_cmd "docker compose exec -T redis redis-cli --json HGETALL mixed:counters | python3 scripts/fmt.py --type mixed-counters"
RAW="$(redis_query --json HGETALL mixed:counters)"
emit "$(printf '%s' "$RAW" | $FMT --type mixed-counters 2>&1)"
if echo "$RAW" | jq -e '(.weighted|tonumber)==10 and (.payload|tonumber)==4 and (.override|tonumber)==2' >/dev/null 2>&1; then
  verdict 0 "Redis mixed:counters match the batch (10/4/2)" "" ""
  LO+=("Step 3: the Redis fast aggregate matches the batch (EO1b)")
else
  verdict 1 "Redis counters do not match the batch" \
    "Check mixed_incr/reset_mixed in app/db/redis_client.py and the route_mixed loop." \
    "HGETALL mixed:counters after a mixed batch must be weighted=10, payload=4, override=2. Fix app/db/redis_client.py."
fi

# STEP 4 — durable receipts across kinds (both policies)
step_head "4" "Verify the durable receipts in PostgreSQL" \
  "Every routing KIND must have a durable receipt with the full operator field set." \
  "6 rows spanning weighted, payload, and override, each with request ID, policy, provider, latency target, tokens, cost, quality."
show_cmd "docker compose exec -T postgres psql ... request_id, policy, provider, latency, tokens, cost, quality ... | python3 scripts/fmt.py --type mixed-receipts"
RAW="$(pg_query "$SQL_RECEIPTS")"
emit "$(printf '%s' "$RAW" | $FMT --type mixed-receipts 2>&1)"
if echo "$RAW" | jq -s -e 'length==6 and ([.[].kind]|unique|(index("weighted") and index("payload") and index("override"))) and (all(.[]; (.request_id|startswith("req-")) and .policy_name!=null and .quality_score!=null and .latency_target_ms!=null and .cost_estimate_usd!=null))' >/dev/null 2>&1; then
  verdict 0 "durable receipts span all three kinds, each with request ID, policy, provider, latency target, tokens, cost, quality" "" ""
  LO+=("Step 4: durable receipts across every routing kind — request ID, policy, provider, latency target, tokens, cost, quality (TO1, EO1a)")
else
  verdict 1 "receipts do not visibly span all three kinds or are missing operator fields" \
    "Ensure the query returns request_id and the mixed batch persisted all kinds with non-null fields." \
    "The receipts query must return 6 rows spanning weighted, payload, and override, each with request_id, policy_name, latency_target_ms, total_tokens, cost_estimate_usd, quality_score. Fix the query and app/main.py."
fi

# STEP 5 — reconcile + final disposition (merged)
step_head "5" "Reconcile the evidence and confirm the disposition" \
  "The operator decision is CONFIRMED only when the views agree, receipts are complete, and policies are consistent." \
  "disposition CONFIRMED, with counts_agree, receipts_complete, and policies_consistent all true; api==redis==receipts per kind."
show_cmd "curl -s \$API_BASE/routing/disposition | python3 scripts/fmt.py --type disposition"
RAW="$(curl -s "$API_BASE/routing/disposition")"
emit "$(printf '%s' "$RAW" | $FMT --type disposition 2>&1)"
if echo "$RAW" | jq -e '.disposition=="CONFIRMED" and .counts_agree==true and .receipts_complete==true and .policies_consistent==true and (.kinds|to_entries|all(.value.agree==true))' >/dev/null 2>&1; then
  verdict 0 "final disposition CONFIRMED — counts agree, receipts complete, policies consistent" "" ""
  LO+=("Step 5: a single accept-or-investigate disposition validates the routing evidence for this batch (TO1, EO1a-d)")
else
  verdict 1 "final disposition is not CONFIRMED" \
    "Check /routing/disposition in app/main.py (counts_agree, receipts_complete, policies_consistent) and count_by_kind/inconsistent_receipts in app/db/postgres.py." \
    "GET /routing/disposition after a clean mixed batch must return disposition=CONFIRMED with counts_agree, receipts_complete, and policies_consistent all true. Fix app/main.py routing_disposition()."
fi

# COVERAGE + SUMMARY
banner "LEARNING OBJECTIVE COVERAGE"
emit "${WHITE}TO1, EO1a-d — Validate the routing evidence for a mixed batch: reconciled${R}"
emit "${WHITE}       across the API, Redis, and PostgreSQL views into one disposition${R}"
if [ "${#LO[@]}" -gt 0 ]; then for e in "${LO[@]}"; do emit "  ${LIME}✔${R} ${GRAY}${e}${R}"; done; else emit "  ${PINK}✗ no evidence captured${R}"; fi

banner "SUMMARY"
TOTAL=$((PASS+FAIL))
emit "  ${LIME}PASS: ${PASS}${R}   ${PINK}FAIL: ${FAIL}${R}   ${GRAY}of ${TOTAL} steps${R}"
if [ "$FAIL" = "0" ]; then
  emit "  ${LIME}✔ ALL STEPS PASSED — demo aligns with TO1 and EO1a-d. Ready to record.${R}"
else
  emit "  ${PINK}✗ ${FAIL} step(s) failed — fix above, reset, and re-run.${R}"
fi
blank
emit "  ${GRAY}full readable log written to:${R} ${LGRN}module1/clip6_preflight_log.txt${R}"
exit "$FAIL"
