#!/usr/bin/env bash
# =============================================================================
# Module 2 · Demo — Prove traces, logs, metrics, and quality sampling
# AUTHOR PREFLIGHT: runs every demo step in the SAME order as module2/demo/clip5.md,
# captures each command and its on-screen output, asserts the output proves the
# learning objectives (EO3a-e), and writes a readable log for a reviewer.
#
#   bash module2/scripts/clip5_preflight_check.sh
#
# Defaults target Docker Compose on macOS; override with env vars for a native
# stack: API_BASE, PGHOST, PGPORT, PGUSER, PGDATABASE, PGPASSWORD
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
LOG="$ROOT/module2/clip5_preflight_log.txt"
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

banner "MODULE 2 · DEMO — TRACES, LOGS, METRICS, AND QUALITY SAMPLING  (LO: EO3a-e)"
emit "${GRAY}stack:${R} API=${LGRN}${API_BASE}${R}"
emit "${GRAY}running the observed batch (emits traces, records metrics, samples quality) ...${R}"
curl -s -X POST "$API_BASE/admin/reset" >/dev/null 2>&1
curl -s -X POST "$API_BASE/observe/run" >/dev/null 2>&1

# STEP 1 — end-to-end trace
step_head "1" "Open the end-to-end trace" \
  "One request must be traceable across every stage of the pipeline." \
  "a span timeline: ingress, queue, routing, provider_call, retry_backoff, fallback, response."
show_cmd "curl -s -X POST \$API_BASE/observe/run >/dev/null; curl -s \$API_BASE/observe/trace | python3 scripts/fmt.py --type trace"
RAW="$(curl -s "$API_BASE/observe/trace")"
emit "$(printf '%s' "$RAW" | $FMT --type trace 2>&1)"
if echo "$RAW" | jq -e '([.spans[].span]|(index("ingress") and index("queue") and index("routing") and index("provider_call") and index("retry_backoff") and index("fallback") and index("response"))) and (.total_ms>0) and (.trace_id|length==32)' >/dev/null 2>&1; then
  verdict 0 "the trace spans ingress → queue → routing → provider call → retry → fallback → response" "" ""
  LO+=("Step 1: distributed tracing across the application, AI service, and provider layers (EO3a)")
else
  verdict 1 "the trace does not span every pipeline stage" \
    "Check the span stages in app/observability/observe.py (_fallback_stages) and the OTel tracer setup." \
    "GET /observe/trace after /observe/run must show spans ingress, queue, routing, provider_call, retry_backoff, fallback, response with a 32-char trace id. Fix app/observability/observe.py."
fi

# STEP 2 — structured logs
step_head "2" "Inspect the structured logs" \
  "Each request must log one record with the full operator field set." \
  "request id, model, route reason, tokens (prompt/completion/total), cost, latency, status, quality."
show_cmd "curl -s \$API_BASE/observe/logs | python3 scripts/fmt.py --type obs-logs"
RAW="$(curl -s "$API_BASE/observe/logs")"
emit "$(printf '%s' "$RAW" | $FMT --type obs-logs 2>&1)"
if echo "$RAW" | jq -e '(.logs|length>=3) and (.logs|all(has("request_id") and has("model") and has("route_reason") and has("prompt_tokens") and has("completion_tokens") and has("total_tokens") and has("cost_usd") and has("latency_ms") and has("provider_status") and has("quality_status")))' >/dev/null 2>&1; then
  verdict 0 "every structured log carries the full field set, tokens broken into prompt/completion/total" "" ""
  LO+=("Step 2: a structured logging schema for inputs, model, latency, tokens, and cost (EO3b)")
else
  verdict 1 "structured logs are missing fields" \
    "Check _structured_log in app/observability/observe.py." \
    "GET /observe/logs must return records with request_id, model, route_reason, prompt/completion/total tokens, cost_usd, latency_ms, provider_status, quality_status. Fix app/observability/observe.py."
fi

# STEP 3 — Prometheus metrics
step_head "3" "Read the Prometheus service metrics" \
  "Latency, availability, queue depth, fallback rate, retry rate, and cost must be quantified." \
  "p50 712ms, p95 2112ms, availability 100%, queue depth 4, fallback 15%, retry 15%, cost \$0.1533."
show_cmd "curl -s \$API_BASE/observe/metrics | python3 scripts/fmt.py --type metrics"
RAW="$(curl -s "$API_BASE/observe/metrics")"
emit "$(printf '%s' "$RAW" | $FMT --type metrics 2>&1)"
EXPO="$(curl -s "$API_BASE/metrics" | grep -c 'genai_request_latency_ms')"
if echo "$RAW" | jq -e '.latency_p50_ms==712 and .latency_p95_ms==2112 and .availability_pct==100.0 and .fallback_rate_pct==15.0 and .retry_rate_pct==15.0 and .queue_depth==4' >/dev/null 2>&1 && [ "${EXPO:-0}" -gt 0 ]; then
  verdict 0 "metrics quantify latency, availability, queue, fallback, retry, and cost — real Prometheus exposition at /metrics" "" ""
  LO+=("Step 3: metrics quantify latency, availability, queue, fallback, retry, and cost (EO3d)")
else
  verdict 1 "metrics summary or Prometheus exposition is wrong" \
    "Check run_observe metrics + the Prometheus registry in app/observability/observe.py and the /metrics endpoint." \
    "GET /observe/metrics must show p50=712, p95=2112, availability=100, fallback=15, retry=15, queue=4; GET /metrics must expose genai_request_latency_ms. Fix app/observability/observe.py."
fi

# STEP 4 — output quality sampling
step_head "4" "Sample output quality on live responses" \
  "A representative subset must be graded — a successful response can still fail quality." \
  "pass rate 60% (3/5) against a 0.85 bar, with reviewer reasons for each fail."
show_cmd "curl -s \$API_BASE/observe/quality | python3 scripts/fmt.py --type quality"
RAW="$(curl -s "$API_BASE/observe/quality")"
emit "$(printf '%s' "$RAW" | $FMT --type quality 2>&1)"
if echo "$RAW" | jq -e '.pass_rate_pct==60.0 and .passed==3 and .failed==2 and .quality_bar==0.85 and ([.samples[].quality_status]|(index("pass") and index("fail"))) and (.samples|all(has("reviewer_reason")))' >/dev/null 2>&1; then
  verdict 0 "quality sampling grades a subset 3 pass / 2 fail with reviewer reasons — a 200 can still fail quality" "" ""
  LO+=("Step 4: production output quality sampling on a representative subset (EO3c)")
else
  verdict 1 "quality sampling did not grade the subset as expected" \
    "Check the samples and QUALITY_BAR in app/observability/observe.py." \
    "GET /observe/quality must show pass_rate=60, passed=3, failed=2, bar=0.85, samples spanning pass and fail with reviewer_reason. Fix app/observability/observe.py."
fi

# STEP 5 — SLO alert rules
step_head "5" "Confirm the SLO alert rules" \
  "Latency, availability, and output quality must each have an objective that fires on a breach." \
  "disposition ALERT: availability ok, latency ok, quality pass rate breach with severity page."
show_cmd "curl -s \$API_BASE/observe/slo | python3 scripts/fmt.py --type slo"
RAW="$(curl -s "$API_BASE/observe/slo")"
emit "$(printf '%s' "$RAW" | $FMT --type slo 2>&1)"
if echo "$RAW" | jq -e '.disposition=="ALERT" and ([.slos[].dimension]|(index("latency") and index("availability") and index("output quality"))) and (.slos[]|select(.dimension=="output quality").status)=="breach" and (.slos[]|select(.dimension=="output quality").severity)=="page"' >/dev/null 2>&1; then
  verdict 0 "SLO rules cover latency, availability, and output quality; the quality breach fires severity page" "" ""
  LO+=("Step 5: SLOs for latency, availability, and output quality, with alerting (EO3d)")
else
  verdict 1 "SLO evaluation or alerting is wrong" \
    "Check the SLO thresholds and _slo evaluation in app/observability/observe.py." \
    "GET /observe/slo must return disposition=ALERT with dimensions latency, availability, output quality, and the quality breach at severity page. Fix app/observability/observe.py."
fi

# STEP 6 — diagnose the slow request
step_head "6" "Diagnose the slow request from its trace" \
  "Nested span timings must point at the exact stage that owns the latency." \
  "provider_call is 2100ms of 2112ms (99.4%); root cause is provider latency, not queueing or retry."
show_cmd "curl -s \$API_BASE/observe/diagnose | python3 scripts/fmt.py --type diagnose"
RAW="$(curl -s "$API_BASE/observe/diagnose")"
emit "$(printf '%s' "$RAW" | $FMT --type diagnose 2>&1)"
if echo "$RAW" | jq -e '.slowest_span=="provider_call" and .slowest_share_pct>90 and (.provider_status=="degraded_slow") and (.root_cause|test("provider"))' >/dev/null 2>&1; then
  verdict 0 "the slow trace pins the latency on provider_call (over 90% of the total) — not queueing or retry" "" ""
  LO+=("Step 6: use observability data to diagnose a performance incident (EO3e)")
else
  verdict 1 "the diagnosis did not isolate the latency source" \
    "Check the diagnose block and the slow trace in app/observability/observe.py." \
    "GET /observe/diagnose must show slowest_span=provider_call with share>90%, provider_status degraded_slow, root cause provider latency. Fix app/observability/observe.py."
fi

# STEP 7 — correlate cost, quality, and operator action
step_head "7" "Correlate cost, quality, and the operator action" \
  "One record must tie tokens and cost to the quality verdict and the operator action." \
  "a failed request with its token count, cost, quality score, and the recorded operator action."
show_cmd "curl -s \$API_BASE/observe/correlate | python3 scripts/fmt.py --type correlate"
RAW="$(curl -s "$API_BASE/observe/correlate")"
emit "$(printf '%s' "$RAW" | $FMT --type correlate 2>&1)"
if echo "$RAW" | jq -e '.quality_status=="fail" and (.total_tokens>0) and (.cost_usd>0) and (.operator_action|length>0) and has("request_id")' >/dev/null 2>&1; then
  verdict 0 "one record correlates tokens, cost, the quality verdict, and the operator action" "" ""
  LO+=("Step 7: structured evidence connects cost, quality, and the operator action (EO3e)")
else
  verdict 1 "the correlation record is incomplete" \
    "Check the correlate block in app/observability/observe.py." \
    "GET /observe/correlate must return request_id, total_tokens, cost_usd, quality_status=fail, and operator_action. Fix app/observability/observe.py."
fi

# COVERAGE + SUMMARY
banner "LEARNING OBJECTIVE COVERAGE"
emit "${WHITE}EO3a-e — Trace one request end to end, log its full field set, quantify${R}"
emit "${WHITE}       the metrics, sample output quality, alert on the SLOs, and diagnose${R}"
if [ "${#LO[@]}" -gt 0 ]; then for e in "${LO[@]}"; do emit "  ${LIME}✔${R} ${GRAY}${e}${R}"; done; else emit "  ${PINK}✗ no evidence captured${R}"; fi

banner "SUMMARY"
TOTAL=$((PASS+FAIL))
emit "  ${LIME}PASS: ${PASS}${R}   ${PINK}FAIL: ${FAIL}${R}   ${GRAY}of ${TOTAL} steps${R}"
if [ "$FAIL" = "0" ]; then
  emit "  ${LIME}✔ ALL STEPS PASSED — demo aligns with EO3a-e. Ready to record.${R}"
else
  emit "  ${PINK}✗ ${FAIL} step(s) failed — fix above, reset, and re-run.${R}"
fi
blank
emit "  ${GRAY}full readable log written to:${R} ${LGRN}module2/clip5_preflight_log.txt${R}"
exit "$FAIL"
