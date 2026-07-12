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
SQL_RECEIPTS="SELECT row_to_json(r) FROM (SELECT request_id,policy_name,provider_tier,latency_target_ms,total_tokens,cost_estimate_usd,quality_score FROM receipts ORDER BY created_at DESC LIMIT 6) r"

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
  "total 16, and weighted 10, payload 4, override 2."
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

# STEP 2 — samples span all kinds
step_head "2" "Inspect the individual mixed decisions" \
  "Each request must be tagged with its kind, policy, model, and route reason." \
  "samples where weighted, payload, and override all appear."
show_cmd "curl -s \$API_BASE/routing/mixed-batch?limit=6 | python3 scripts/fmt.py --type mixed-samples"
RAW="$(curl -s "$API_BASE/routing/mixed-batch?limit=16")"
emit "$(printf '%s' "$(curl -s "$API_BASE/routing/mixed-batch?limit=6")" | $FMT --type mixed-samples 2>&1)"
if echo "$RAW" | jq -e '[.samples[].kind]|unique|(index("weighted") and index("payload") and index("override"))' >/dev/null 2>&1; then
  verdict 0 "samples are tagged and span all three routing kinds" "" ""
  LO+=("Step 2: each decision carries its policy and route reason (TO1, EO1a)")
else
  verdict 1 "samples do not span weighted, payload, and override" \
    "Check the samples built in route_mixed() and GET /routing/mixed-batch." \
    "GET /routing/mixed-batch must return samples tagged weighted, payload, and override. Fix app/main.py."
fi

# STEP 3 — redis aggregate matches
step_head "3" "Prove the aggregate spread in Redis" \
  "The datastore's per-kind tally must match the API summary." \
  "total 16, and weighted 10, payload 4, override 2 read from the hash."
show_cmd "docker compose exec -T redis redis-cli --json HGETALL mixed:counters | python3 scripts/fmt.py --type mixed-counters"
RAW="$(redis_query --json HGETALL mixed:counters)"
emit "$(printf '%s' "$RAW" | $FMT --type mixed-counters 2>&1)"
if echo "$RAW" | jq -e '(.weighted|tonumber)==10 and (.payload|tonumber)==4 and (.override|tonumber)==2' >/dev/null 2>&1; then
  verdict 0 "Redis mixed:counters match the batch (10/4/2)" "" ""
  LO+=("Step 3: the Redis datastore aggregates the mixed spread (EO1b)")
else
  verdict 1 "Redis counters do not match the batch" \
    "Check mixed_incr/reset_mixed in app/db/redis_client.py and the route_mixed loop." \
    "HGETALL mixed:counters after a mixed batch must be weighted=10, payload=4, override=2. Fix app/db/redis_client.py."
fi

# STEP 4 — receipts full field set
step_head "4" "Read the full per-request receipts in PostgreSQL" \
  "Every request must carry the operator field set, quality included." \
  "6 rows with policy, provider, latency, tokens, cost, and quality; both policies present."
show_cmd "docker compose exec -T postgres psql ... policy_name,provider_tier,latency_target_ms,total_tokens,cost_estimate_usd,quality_score ... | python3 scripts/fmt.py --type mixed-receipts"
RAW="$(pg_query "$SQL_RECEIPTS")"
emit "$(printf '%s' "$RAW" | $FMT --type mixed-receipts 2>&1)"
if echo "$RAW" | jq -s -e 'length==6 and (all(.[]; .quality_score!=null and .latency_target_ms!=null and .cost_estimate_usd!=null))' >/dev/null 2>&1; then
  verdict 0 "receipts carry the full operator field set including quality_score" "" ""
  LO+=("Step 4: durable receipts hold policy, provider, latency, tokens, cost, quality (TO1, EO1a)")
else
  verdict 1 "receipts are missing operator fields" \
    "Check the receipts columns in app/db/postgres.py and that route_mixed persisted them." \
    "Querying receipts must return rows with policy_name, latency_target_ms, total_tokens, cost_estimate_usd, quality_score. Fix app/db/postgres.py."
fi

# STEP 5 — reconcile sources
step_head "5" "Reconcile the three sources of truth" \
  "API summary, Redis counters, and PostgreSQL receipts must agree per kind." \
  "sources_agree true, with api==redis==receipts for weighted, payload, override."
show_cmd "curl -s \$API_BASE/routing/disposition | python3 scripts/fmt.py --type disposition"
RAW="$(curl -s "$API_BASE/routing/disposition")"
emit "$(printf '%s' "$RAW" | $FMT --type disposition 2>&1)"
if echo "$RAW" | jq -e '.sources_agree==true and (.kinds|to_entries|all(.value.agree==true))' >/dev/null 2>&1; then
  verdict 0 "API, Redis, and receipts agree on every routing kind" "" ""
  LO+=("Step 5: three independent records reconcile per routing kind (TO1, EO1a-d)")
else
  verdict 1 "the three sources do not reconcile" \
    "Check /routing/disposition in app/main.py and count_by_kind in app/db/postgres.py." \
    "GET /routing/disposition must return sources_agree=true with api==redis==receipts per kind. Fix app/main.py routing_disposition()."
fi

# STEP 6 — final disposition
step_head "6" "Confirm the final operator disposition" \
  "The operator decision is CONFIRMED only when all three agree and policies are consistent." \
  "disposition CONFIRMED, sources_agree true, policies_consistent true."
show_cmd "curl -s \$API_BASE/routing/disposition | python3 scripts/fmt.py --type disposition"
RAW="$(curl -s "$API_BASE/routing/disposition")"
emit "$(printf '%s' "$RAW" | $FMT --type disposition 2>&1)"
if echo "$RAW" | jq -e '.disposition=="CONFIRMED" and .policies_consistent==true' >/dev/null 2>&1; then
  verdict 0 "final disposition is CONFIRMED — policy, receipt, and model agree" "" ""
  LO+=("Step 6: a single go/no-go disposition confirms the whole routing layer (TO1, EO1a-d)")
else
  verdict 1 "final disposition is not CONFIRMED" \
    "Check policies_consistent (inconsistent_receipts) and the disposition logic in app/main.py." \
    "GET /routing/disposition must return disposition=CONFIRMED and policies_consistent=true after a clean mixed batch. Fix app/main.py and app/db/postgres.py."
fi

# COVERAGE + SUMMARY
banner "LEARNING OBJECTIVE COVERAGE"
emit "${WHITE}TO1, EO1a-d — Validate the whole routing layer: mixed traffic reconciled${R}"
emit "${WHITE}       across API, Redis, and PostgreSQL into one operator disposition${R}"
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
