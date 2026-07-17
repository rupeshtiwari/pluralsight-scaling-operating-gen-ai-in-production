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

**What you will see:** Seven moments that turn a black box into an operable system —
one request's end-to-end trace across ingress, queue, routing, provider call, retry,
fallback, and response; the structured log that carries its full field set; the
Prometheus metrics for latency, availability, queue depth, fallback and retry rate,
and cost; output quality sampling that separates a successful response from a
trustworthy one; the SLO rules that fire an alert when a dimension breaches; a slow
request diagnosed straight from its span timings; and one record that ties cost and
quality to the operator's action.

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
| 4 | EO3c | Quality sampling grades a representative subset with schema, policy, and reviewer reasons |
| 5 | EO3d | SLO rules cover latency, availability, and output quality, and fire on a breach |
| 6 | EO3e | A slow request's nested span timings pinpoint the provider as the root cause |
| 7 | EO3e | One record correlates tokens, cost, quality status, and the operator action |

## What this demo proves — and each step is unique

| Step | Command | What it teaches (nothing repeats) |
|------|---------|-----------------------------------|
| 1 | `/observe/trace` | Where a request spends its time, stage by stage |
| 2 | `/observe/logs` | The durable field set behind every request |
| 3 | `/observe/metrics` | The aggregate health signals over a window |
| 4 | `/observe/quality` | A 200 response can still fail quality |
| 5 | `/observe/slo` | Metrics become a go / no-go alert |
| 6 | `/observe/diagnose` | Nested timings isolate the latency source |
| 7 | `/observe/correlate` | Cost and quality tie to one operator action |

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

**Expected output:** ★ a `trace id`, ★ `total: 1812 ms`, then the span timeline —
`ingress`, `queue`, `routing`, `provider_call` (1200ms), `retry_backoff` (200ms),
`fallback` (400ms), `response` — each with a proportional bar.

**What the learner should notice:** This is one request, made fully legible. The
spans read like a story: it arrived (`ingress`), waited briefly (`queue`), chose a
model (`routing`), called the primary (`provider_call`), that call was unsafe so it
backed off (`retry_backoff`) and failed over (`fallback`), then returned. The bar
lengths are the lesson — the `provider_call` span dwarfs everything the service
itself did. This is real OpenTelemetry: the same trace id shows up in Jaeger. When a
customer reports "slow," this is the first place you look, since it separates *your*
overhead from the *provider's* time in seconds.

### Step 2: Inspect the structured logs

**Goal:** Read the structured log records and confirm each carries the full operator
field set for one request.

```bash
curl -s http://localhost:8000/observe/logs | python3 scripts/fmt.py --type obs-logs \
  --title "Inspect the structured logs" \
  --why "One record per request: request id, model, route reason, tokens, cost, latency, provider status, and quality"
```

**Expected output:** ★ one record per request, each with `request-id`, `model`,
`route_reason`, `tokens` shown as `prompt`, `completion`, `total`, `cost`, `latency`,
`provider status`, and `quality`.

**What the learner should notice:** A trace shows shape; a structured log shows
facts, and these are the facts an operator queries at 2am. Every record is one
line of machine-readable fields, not free text, so you can filter and aggregate them.
Read the token breakdown as `prompt`, `completion`, `total`, never just a total —
the split is how you separate input cost from output cost. Look at the third record:
its `provider status` is `degraded_slow` and its `quality` is `fail`. That single
line is a whole incident in miniature, and structured fields are what let you find
the other requests exactly like it.

### Step 3: Read the Prometheus service metrics

**Goal:** Read the aggregate metrics over the window — the numbers an operator
watches on a dashboard.

```bash
curl -s http://localhost:8000/observe/metrics | python3 scripts/fmt.py --type metrics \
  --title "Read the Prometheus service metrics" \
  --why "Latency, availability, queue depth, fallback rate, retry rate, and cost — the operator's health signals"
```

> The raw Prometheus exposition is live at `http://localhost:8000/metrics`, which the
> Prometheus server scrapes on the `obs` profile.

**Expected output:** ★ `requests observed: 20`, then ★ `p50: 712 ms`, ★ `p95: 2112
ms`, ★ `availability: 100.0%`, ★ `queue depth: 4`, ★ `fallback rate: 15.0%`,
★ `retry rate: 15.0%`, ★ `cost estimate: $0.1533`.

**What the learner should notice:** These are real Prometheus metrics, and they turn
feelings into numbers. Always read latency as two numbers, not one. The `p50` of 712
milliseconds is your typical request; the `p95` of 2112 milliseconds is the slow tail
your unhappy customers actually feel. A rising gap between them is your earliest
warning. `availability` at 100 percent looks perfect — hold that thought, since the
next steps will show why a perfect availability number can still hide a broken
service. `fallback rate` and `retry rate` at 15 percent tell you the primary provider
is struggling under the surface, even though every caller got an answer.

### Step 4: Sample output quality on live responses

**Goal:** Run automated quality checks on a representative subset and read the pass
rate against the quality bar.

```bash
curl -s http://localhost:8000/observe/quality | python3 scripts/fmt.py --type quality \
  --title "Sample output quality on live responses" \
  --why "Automated checks on a representative subset — a successful response can still fail quality"
```

**Expected output:** ★ `policy: output_quality_sampling`, ★ the `schema`, ★ `pass
rate: 60.0% (3/5)` against ★ `quality bar 0.85`, then a per-sample table with `score`,
`status`, and the `reviewer reason`.

**What the learner should notice:** This is the step that keeps you honest. Every one
of these responses returned a successful `200`, and yet two of the five **failed
quality**. Read the reviewer reasons: one *hallucinated a policy number*, another
*contradicts its source*. Those are not crashes; they are confident, wrong answers
that no latency or availability metric will ever catch. A 60 percent pass rate on a
0.85 bar is a serious signal — in production you sample a small, representative slice
of live traffic exactly like this, precisely because you cannot review everything and
you must not fly blind on trust. Availability tells you the service answered; quality
sampling tells you whether the answer was worth sending.

### Step 5: Confirm the SLO alert rules

**Goal:** Evaluate the service objectives across latency, availability, and output
quality, and read the alert a breach fires.

```bash
curl -s http://localhost:8000/observe/slo | python3 scripts/fmt.py --type slo \
  --title "Confirm the SLO alert rules" \
  --why "Latency, availability, and output quality each get an objective — a breach fires an alert"
```

**Expected output:** ★ `disposition: ALERT`, then three rows — `availability` `100 >=
99` `ok`, `latency_p95` `2112 <= 2500` `ok`, and `quality_pass_rate` `60 >= 90`
`breach` `page`.

**What the learner should notice:** An objective without an alert is a wish, so each
dimension gets a threshold and a severity. Two of your three objectives are green:
availability holds above 99 percent and the p95 latency sits under its 2500
millisecond budget. If you only watched those two, you would sleep soundly. The third
tells the truth. The quality pass rate of 60 percent is far below its 90 percent
objective, so the rule fires with severity `page`. This is the whole point of a
quality SLO — it pages a human when the service is *up and confidently wrong*, the
one failure mode your infrastructure dashboards are blind to.

### Step 6: Diagnose the slow request from its trace

**Goal:** Open a slow request's trace and use its nested span timings to find the
exact stage that owns the latency.

```bash
curl -s http://localhost:8000/observe/diagnose | python3 scripts/fmt.py --type diagnose \
  --title "Diagnose the slow request from its trace" \
  --why "Nested span timings point at the exact stage that owns the latency"
```

**Expected output:** ★ a `trace id`, ★ `total: 2112 ms`, the span timeline, then
★ `slowest span: provider_call — 2100ms (99.4%)`, ★ `provider status: degraded_slow`,
★ `root cause: provider latency, not queueing or retry`.

**What the learner should notice:** This is how you close an incident in under a
minute instead of an hour. The request took 2112 milliseconds, and the trace ends the
guesswork immediately: `provider_call` alone is 2100 of those milliseconds, which is
99.4 percent of the total. The queue, the routing, and the retry logic are all
innocent. Without a trace, a team burns an afternoon blaming its own code; with one,
you point straight at the provider, match the span to its `degraded_slow` status, and
open a ticket with the vendor holding real evidence. Nested timings turn "it's slow"
into "the provider is slow, here is the proof."

### Step 7: Correlate cost, quality, and the operator action

**Goal:** Read one record that ties a request's tokens and cost to its quality verdict
and the action an operator took.

```bash
curl -s http://localhost:8000/observe/correlate | python3 scripts/fmt.py --type correlate \
  --title "Correlate cost, quality, and the operator action" \
  --why "One record ties tokens and cost to the quality verdict and what the operator did about it"
```

**Expected output:** ★ a `request id`, ★ `total tokens: 50`, ★ `cost: $0.0150`,
★ `quality status: fail (score 0.55)`, ★ `operator action: sampled, flagged for
review, excluded from training set`.

**What the learner should notice:** Observability only pays off when the signals
connect to a decision. This one record does exactly that: it takes a single request,
shows the 50 tokens and 1.5 cents you spent producing the answer, states plainly that
the answer failed quality with a score of 0.55, and records what the operator did — it
was sampled, flagged for review, and kept out of any training set so a bad answer
never teaches the next model. That last field is the difference between a metric and
an operation. You are not just measuring cost and quality; you are turning a failed
response into a tracked action, which is what production ownership actually looks
like.

## Preflight check

```bash
bash module2/scripts/clip5_preflight_check.sh
```

Runs every step above, captures each command and its output, maps each step to
EO3a–e, and writes a readable log to `module2/clip5_preflight_log.txt`. Expect
`PASS: 7  FAIL: 0`.

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
