# Module 2 — Demo: Prove traces, logs, metrics, and quality sampling

## Why this matters

**The problem:** Your service now routes, absorbs spikes, and fails over. But when
a customer says "it was slow" or "the answer was wrong," a green health check tells
you nothing. You need to see *inside* one request — every stage it passed through
and how long each took — and you need aggregate signals that turn "it feels slow"
into a number with an objective attached. Worst of all, a request can return a
clean `200` and still be **untrustworthy**: the model answered confidently and got
it wrong. A service that cannot observe latency, cost, and output quality together
is a service you operate by hope. How do you make one request fully observable, and
turn raw signals into an alert an operator can act on?

**What you will see:** Five moments that turn a black box into an operable system —
one request's end-to-end trace across ingress, queue, routing, provider call, retry,
fallback, and response; the structured log that carries its full field set; the
Prometheus metrics for latency, availability, queue depth, fallback and retry rate,
and cost; output quality sampling that separates a successful response from a
trustworthy one and the SLO rule that fires an alert on the quality breach; and a
slow request diagnosed straight from its span timings, with one record that ties
cost and quality to the operator's action.

**What you walk away with:** Full observability for the AI service — distributed
tracing across the layers (EO3a), a structured logging schema (EO3b), production
output quality sampling (EO3c), SLOs with alerting (EO3d), and the ability to
diagnose a real incident from trace and log evidence (EO3e).

## Learning objectives covered

| Step | LO sub-element | What proves it |
|------|----------------|----------------|
| 1 | EO3a | One trace spans ingress → queue → routing → provider call → retry → fallback → response |
| 2 | EO3b | A structured log carries request id, model, route reason, tokens, cost, latency, status |
| 3 | EO3d | Prometheus metrics quantify latency, availability, queue depth, fallback, retry, cost |
| 4 | EO3c, EO3d | Quality sampling grades a representative subset, and the quality SLO fires an alert on the breach |
| 5 | EO3e | A slow request's nested timings pinpoint the provider, and one record ties cost and quality to the operator action |

## What this demo proves — and each step is unique

| Step | Command | What it teaches (nothing repeats) |
|------|---------|-----------------------------------|
| 1 | `/observe/trace` | Where a request spends its time, stage by stage |
| 2 | `/observe/logs` | The durable field set behind every request |
| 3 | `/observe/metrics` | The aggregate health signals over a window |
| 4 | `/observe/quality` + `/observe/slo` | A 200 can still fail quality, and that breach fires an alert |
| 5 | `/observe/diagnose` + `/observe/correlate` | Nested timings isolate the source, tied to one operator action |

## Prerequisites

### Software this clip needs — do you have it?

This clip uses **Docker Desktop** (with Compose), **curl**, **jq**, **python3**,
**psql**, and **tmux**, plus the observability stack — **OpenTelemetry Collector**,
**Jaeger**, and **Prometheus** — which come up as Compose services. Two commands
cover every case:

```bash
bash scripts/ensure-ready.sh       # CHECK  — ✔ / ✗ for each tool, with a fix for anything missing
bash environment-setup/setup.sh    # INSTALL — one step: installs everything the course uses, then the pinned deps
```

- **First time on this Mac?** Run the install step once. When it prints `READY`,
  you have everything this clip needs, including the OpenTelemetry and Prometheus
  Python libraries.
- **Already set up?** The check confirms you're good in seconds.

### Start the stack

**Start the stack first.** This brings up FastAPI, Redis, and PostgreSQL and waits
until healthy:

```bash
bash module2/scripts/demo_up.sh
```

The service is instrumented with real OpenTelemetry and exposes a real Prometheus
`/metrics` endpoint. To bring up the observability servers too — the OpenTelemetry
Collector, Jaeger, and Prometheus — start the `obs` profile:

```bash
docker compose --profile obs up -d
```

The terminal steps below read the same trace, metric, and quality data the service
produces, so they work with or without the browser tools open. Reset before you
start:

```bash
./scripts/module2-demo-reset.sh
```

## Demo steps

### Step 1: Open the end-to-end trace

**Goal:** Run one observed batch and open a single request's trace across every
stage, to see where its time went.

```bash
curl -s -X POST http://localhost:8000/observe/run >/dev/null
curl -s http://localhost:8000/observe/trace | python3 scripts/fmt.py --type trace \
  --title "Open the end-to-end trace" \
  --why "One request across ingress, queue, routing, provider call, retry, fallback, and response"
```

**Expected output:** ★ a `trace id`, ★ a `request id` (`req-4f18c0a7d2b9` — the
join key that ties this trace to its structured log), ★ `total: 1812 ms`, then the
child-span timeline — `ingress`, `queue`, `routing`, `provider_call` (1200ms),
`retry_backoff` (200ms), `fallback` (400ms), `response` — each with a proportional
bar.

**What the learner should notice:** This is one request, made fully legible. We open
a **failover** request on purpose, because it exercises *every* stage: it arrived
(`ingress`), waited briefly (`queue`), chose a model (`routing`), called the primary
(`provider_call`), that call was unsafe so it backed off (`retry_backoff`) and failed
over (`fallback`), then returned. A clean request would skip retry and fallback, so
this exemplar is the one that shows the whole pipeline in a single trace. The bar
lengths are the lesson — the `provider_call` span dwarfs everything the service
itself did. This is real OpenTelemetry: the same trace id shows up in Jaeger. When a
customer reports "slow," this is the first place you look, since it separates *your*
overhead from the *provider's* time in seconds. (In Step 5 we open a *different*
request — a slow one — to run a root-cause diagnosis; this one is here to show the
full seven-stage shape.)

### Step 2: Inspect the structured logs

**Goal:** Read the structured log records and confirm each carries the full operator
field set for one request.

```bash
curl -s http://localhost:8000/observe/logs | python3 scripts/fmt.py --type obs-logs \
  --title "Inspect the structured logs" \
  --why "One record per request: request id, model, route reason, tokens, cost, latency, provider status, and quality"
```

**Expected output:** ★ one record per request over two compact lines — an identity
line (`request-id`, `model`, `route_reason`) and a numbers line (`tok`
prompt/completion/total, `$` cost, `lat` latency, provider status, `qual`). The
third record is `req-2a7c55e1b93f`: `balanced-std`, `degraded_slow`, quality `fail`.

**What the learner should notice:** A trace shows shape; a structured log shows
facts, and these are the facts an operator queries at 2am. Every record is one
line of machine-readable fields, not free text, so you can filter and aggregate them.
Read the token breakdown as `prompt/completion/total`, never just a total — the
split is how you separate input cost from output cost. Now find the one record that
matters: the third, **`req-2a7c55e1b93f`**, is `degraded_slow` and quality `fail`.
Remember that id — it is the same request you will grade in Step 4, diagnose the
latency of, and tie to an operator action in Step 5. One request ID, threaded across
logs, quality, and the ledger, is how a real incident is followed end to end.

### Step 3: Read the Prometheus service metrics

**Goal:** Read the aggregate metrics over the window — the numbers an operator
watches on a dashboard.

```bash
# First, the raw Prometheus exposition on the wire — what a Prometheus server scrapes
curl -s http://localhost:8000/metrics | grep -E '^genai_(fallbacks|retries|qu)'
# Then the operator summary
curl -s http://localhost:8000/observe/metrics | python3 scripts/fmt.py --type metrics \
  --title "Read the Prometheus service metrics" \
  --why "Latency, availability, queue depth, fallback rate, retry rate, and cost — the operator's health signals"
```

> Show the raw exposition first (four `genai_*` lines straight from `/metrics`) so the
> learner sees the metrics on the wire, then the formatted summary. `/metrics` is the
> deterministic snapshot; the Prometheus server scrapes the same metric names from the
> live `/live-metrics` endpoint on the `obs` profile (that live stream is what feeds
> the Grafana dashboard in Clip 6).

**Expected output:** first four raw lines — `genai_fallbacks_total 3.0`,
`genai_retries_total 3.0`, `genai_queue_depth 4.0`, `genai_quality_pass_rate 60.0` —
then the summary: ★ `requests observed: 20`, ★ `p50: 712 ms`, ★ `p95: 2112 ms`,
★ `availability: 100.0%`, ★ `queue depth: 4`, ★ `fallback rate: 15.0%`,
★ `retry rate: 15.0%`, ★ `cost estimate: $0.1533`.

**What the learner should notice:** These are real Prometheus metrics, and they turn
feelings into numbers. Always read latency as two numbers, not one. The `p50` of 712
milliseconds is your typical request; the `p95` of 2112 milliseconds is the slow tail
your unhappy customers actually feel. A rising gap between them is your earliest
warning. `availability` at 100 percent looks perfect — hold that thought, since the
next steps will show why a perfect availability number can still hide a broken
service. `fallback rate` and `retry rate` at 15 percent tell you the primary provider
is struggling under the surface, even though every caller got an answer.

### Step 4: Sample output quality and confirm the SLO alert

**Goal:** Run automated quality checks on a representative subset, then evaluate the
service objectives and read the alert the quality breach fires.

```bash
curl -s http://localhost:8000/observe/quality | python3 scripts/fmt.py --type quality \
  --title "Sample output quality and confirm the SLO alert" \
  --why "Automated checks on a representative subset — a successful response can still fail quality"
curl -s http://localhost:8000/observe/slo | python3 scripts/fmt.py --type slo \
  --title "Sample output quality and confirm the SLO alert" \
  --why "Latency, availability, and output quality each get an objective — the quality breach fires an alert"
```

**Expected output:** first the sample — ★ `policy: output_quality_sampling`,
★ `sampled: 5 of 20 requests (25.0%)`, ★ `pass rate: 60.0% (3/5)` against a
★ `per-response bar 0.85`, with a per-sample `score` / `status` / `reviewer reason`;
then the SLO — ★ `disposition: ALERT`, three rows: `availability` `100 >= 99` `ok`,
`latency` `2112 <= 2500` `ok`, `output quality` `60 >= 90` `breach` `page`.

**What the learner should notice:** This is the step that keeps you honest. Every one
of these responses returned a successful `200`, and yet two of the five **failed
quality** — one *hallucinated a policy number*, another *contradicts its source*.
Those are not crashes; they are confident, wrong answers no latency or availability
metric will ever catch. Then watch what the SLO does with that: an objective without
an alert is a wish, so each dimension gets a threshold and a severity. Availability
and p95 latency are both green — if you only watched those two, you would sleep
soundly. But the quality pass rate of 60 percent is far below its 90 percent
objective, so the rule fires with severity `page`. That is the whole point of a
quality SLO — it pages a human when the service is *up and confidently wrong*, the one
failure mode your infrastructure dashboards are blind to.

### Step 5: Diagnose the slow request and correlate the operator action

**Goal:** Use a slow request's nested span timings to find the stage that owns the
latency, then read one record that ties its tokens, cost, and quality to the operator
action.

```bash
curl -s http://localhost:8000/observe/diagnose | python3 scripts/fmt.py --type diagnose \
  --title "Diagnose the slow request and correlate the operator action" \
  --why "Nested span timings point at the exact stage that owns the latency"
curl -s http://localhost:8000/observe/correlate | python3 scripts/fmt.py --type correlate \
  --title "Diagnose the slow request and correlate the operator action" \
  --why "One record ties tokens and cost to the quality verdict and what the operator did about it"
```

**Expected output:** first the diagnosis — ★ `trace id`, ★ `request id:
req-2a7c55e1b93f` (the same id from the Step 2 log and Step 4 sample), ★ `total: 2112
ms`, ★ `slowest span: provider_call — 2100ms (99.4%)`, ★ `provider status:
degraded_slow`, ★ `root cause: provider latency, not queueing or retry`; then the
correlation — ★ `request id: req-2a7c55e1b93f`, ★ `total tokens: 50`, ★ `cost:
$0.0150`, ★ `quality status: fail (score 0.55)`, ★ `operator action: sampled, flagged
for review, excluded from training set`.

**What the learner should notice:** This is how you close an incident in under a
minute instead of an hour. The diagnosis opens a **slow** request (a different one
from Step 1's failover trace — this exemplar is clean latency, no retry or fallback
spans to distract). It took 2112 milliseconds, and the trace ends the guesswork:
`provider_call` alone is 2100 of those milliseconds — 99.4 percent — while the queue,
routing, and response are all innocent. You point straight at the provider, match the
span to its `degraded_slow` status, and open a vendor ticket holding real evidence.
Then the correlation closes the loop, and notice the **request id: it is
`req-2a7c55e1b93f`, the exact record you first saw fail in the Step 2 logs and grade
0.55 in Step 4**. That one id has now been followed across the log, the quality
sample, and the ledger: one record shows the 50 tokens and 1.5 cents you spent,
states plainly that the answer failed quality at 0.55, and records
what the operator did — sampled, flagged for review, and kept out of any training set
so a bad answer never teaches the next model. That last field is the difference
between a metric and an operation: you are not just measuring cost and quality, you
are turning a failed response into a tracked action, which is what production
ownership actually looks like.

## Preflight check

```bash
bash module2/scripts/m2-demo5-traces-logs-metrics-quality.preflight.sh
```

Runs every step above, captures each command and its output, maps each step to
EO3a–e, and writes a readable log to `preflight-logs/m2-demo5-traces-logs-metrics-quality.log`. Expect
`PASS: 5  FAIL: 0`.

## Cleanup

```bash
./scripts/module2-demo-reset.sh
```

## Key files

- `app/main.py` — the `/observe/run`, `/observe/trace`, `/observe/logs`, `/metrics`,
  `/observe/metrics`, `/observe/quality`, `/observe/slo`, `/observe/diagnose`, and
  `/observe/correlate` endpoints
- `app/observability/observe.py` — real OpenTelemetry spans, Prometheus metrics,
  quality sampling, and SLO evaluation, all deterministic
- `observability/` — the OpenTelemetry Collector, Prometheus, and alert-rule configs
- `docker-compose.yml` — the `otel-collector`, `jaeger`, and `prometheus` services
  (the `obs` profile)
- `scripts/fmt.py` — the `trace` / `obs-logs` / `metrics` / `quality` / `slo` /
  `diagnose` / `correlate` views
