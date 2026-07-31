# Module 2 — Demo: Diagnose latency, quota pressure, cost drift, and quality regression

## Why this matters

**The problem:** It is the middle of the afternoon and four alerts fire in the
space of two minutes: latency is up, a provider is saturating its quota, cost per
request is drifting, and output quality is sliding. The instinct is to treat this
as four fires and split the team four ways. That instinct is wrong, and it is
expensive. Most real incidents are *one* fault wearing four costumes — a single
degraded provider can inflate latency, trigger the retries that drive cost,
saturate its own quota, and hand back confident wrong answers all at once. The
skill that separates a senior operator from a panicked one is the ability to walk
from the first bad signal down to the single root cause, on evidence, and act on
the cause instead of chasing each symptom. How do you diagnose an incident with
four red dimensions and resolve it with one decision?

**What you will see:** Five moves that take a four-alarm incident down to one root
cause — the alert timeline and operator dashboard that show which signal fired first
with all four dimensions red against their objectives; the single trace that clears
queueing, retry, and fallback and pins the latency on the provider; the admission
control that sheds the quota pressure with a 429 and a Retry-After; the cost drift
reconciled to its real drivers alongside the quality sampling that confirms the
regression, both on the same provider; and the root-cause decision that assigns one
evidence-based action to each dimension.

**What you walk away with:** The ability to diagnose a production incident from
observability data (EO3e) — reading a simulated failure (EO2e) across tracing
(EO3a), structured evidence and cost (EO3b), quality sampling (EO3c), and SLO
alerting (EO3d), and resolving it with the resilience controls you built (TO2):
failover, load shedding, and retry limits.

## Learning objectives covered

| Step | LO sub-element | What proves it |
|------|----------------|----------------|
| 1 | EO2e, TO3, EO3d | A simulated incident surfaces an ordered alert timeline and an operator dashboard, all four dimensions breached |
| 2 | EO3a, EO3e | One trace clears queueing, retry, and fallback and pins the latency on the provider |
| 3 | TO2, EO2e | Admission control sheds the quota pressure with a 429 and a Retry-After |
| 4 | EO3b, EO3c | Cost drift reconciles to named drivers, and quality sampling confirms the regression — both on the provider |
| 5 | EO3e, TO2 | Four symptoms resolve to one root cause with an evidence-based action per dimension |

## What this demo proves — and each step is unique

| Step | Command | What it teaches (nothing repeats) |
|------|---------|-----------------------------------|
| 1 | `/incident/alerts` + `/incident/dashboard` | Which signal fired first, and all four dimensions red at once |
| 2 | `/incident/isolate` | The trace clears the innocent stages and names the culprit |
| 3 | `/incident/quota` | Load shedding is working, not failing |
| 4 | `/incident/cost` + `/incident/quality` | The extra dollars and the quality drop trace to one provider |
| 5 | `/incident/action` | One root cause, one coordinated decision |

## Prerequisites

### Software this clip needs — do you have it?

This clip uses **Docker Desktop** (with Compose), **curl**, **jq**, **python3**,
**psql**, and **tmux**, plus the observability stack — **Prometheus** and
**Grafana** — which come up as Compose services. Two commands cover every case:

```bash
bash scripts/ensure-ready.sh       # CHECK  — ✔ / ✗ for each tool, with a fix for anything missing
bash environment-setup/setup.sh    # INSTALL — one step: installs everything the course uses, then the pinned deps
```

- **First time on this Mac?** Run the install step once. When it prints `READY`,
  you have everything this clip needs.
- **Already set up?** The check confirms you're good in seconds.

### Start the stack

**Start the stack first.** This brings up FastAPI, Redis, and PostgreSQL and waits
until healthy:

```bash
bash module2/scripts/demo_up.sh
```

To bring up the observability servers too — Prometheus and Grafana — start the
`obs` profile:

```bash
docker compose --profile obs up -d
```

The terminal steps below read the same incident snapshot the service produces, so
they work with or without the browser tools open. Grafana provisions a live
**GenAI incident** dashboard at `http://localhost:3000` (anonymous access is on).
Reset before you start:

```bash
./scripts/module2-demo-reset.sh
```

## Demo steps

### Step 1: Read the alert timeline and open the dashboard

**Goal:** Trigger the controlled incident, read the alerts in the order they fired to
find the first bad signal, then open the operator dashboard to see all four
dimensions against their objectives.

```bash
curl -s -X POST http://localhost:8000/incident/run >/dev/null
curl -s http://localhost:8000/incident/alerts | python3 scripts/fmt.py --type incident-alerts \
  --title "Read the alert timeline and open the dashboard" \
  --why "Which signal fired first — the first alert is a symptom, not the root cause"
curl -s http://localhost:8000/incident/dashboard | python3 scripts/fmt.py --type incident-dashboard \
  --title "Read the alert timeline and open the dashboard" \
  --why "Four dimensions, baseline versus current against each objective — every panel red"
```

> The same metrics stream live to Grafana on the `obs` profile at
> `http://localhost:3000` — the terminal shows the incident snapshot; the browser
> shows it moving.

**Expected output:** first the timeline — ★ `first signal: LatencyP95AboveObjective`,
four alerts in fire order (`+00:30` latency `ticket`, `+01:10` quota `ticket`,
`+02:00` cost `ticket`, `+02:40` output quality `page`); then the dashboard —
★ `window requests: 40` and four breached panels: `latency_p95_ms` `950 → 3750`,
`quota_saturation_pct` `55 → 98`, `cost_per_request_usd` `$0.0120 → $0.0210`,
`quality_pass_rate_pct` `92.0 → 68.0`.

**What the learner should notice:** Four alerts in two minutes is the moment an
incident tempts you into the wrong move — splitting the team to chase all four. Read
the timeline instead: latency fired first at thirty seconds, and the quality breach —
the one that actually pages a human — fired last. The first signal is almost never
the root cause, it is just the fastest symptom to cross a threshold. Then the
dashboard turns each alert into a *movement*: latency nearly quadrupled, quota went
from comfortable to nearly exhausted, cost drifted up three quarters, quality fell
twenty-four points. Four dimensions moving together, in the same window, is itself
the biggest clue in the incident — independent problems do not politely arrive at
once. When everything breaks at the same instant, suspect one shared cause, and go
find it.

### Step 2: Isolate the latency from one trace

**Goal:** Open one slow request's trace and use the span timings to clear the
innocent stages and name the one that owns the latency.

```bash
curl -s http://localhost:8000/incident/isolate | python3 scripts/fmt.py --type incident-isolate \
  --title "Isolate the latency from one trace" \
  --why "Queueing, retry, and fallback are innocent — the degraded provider call owns the time"
```

**Expected output:** ★ a `trace id`, ★ `total: 3750 ms`, then the four
contributors with proportional bars — `queueing` `40ms` (`1.1%`, innocent),
`retry` `200ms` (`5.3%`, innocent), `fallback` `400ms` (`10.7%`, innocent), and
`provider call` `3100ms` (`82.7%`, root cause) — then ★ `provider: balanced-ai
(degraded_slow)` and ★ `root cause: provider latency on balanced-ai`.

**What the learner should notice:** This is where the guessing ends. The trace lays
the request out stage by stage, and the bars do the arguing for you: the provider
call alone is eighty-three percent of the time. Queueing is forty milliseconds —
present, because the backlog is real, but innocent. Retry and fallback together are
under half a second. If you had blamed your own queue or your retry logic, this
single trace just exonerated both. One degraded provider, `balanced-ai`, owns this
incident's latency. That is the root cause the four alerts were all pointing at,
and now you can prove it instead of suspecting it.

### Step 3: Prove the quota pressure and the shed

**Goal:** Read the admission-control accounting for the same window and confirm the
quota pressure was shed, not dropped on the floor.

```bash
curl -s http://localhost:8000/incident/quota | python3 scripts/fmt.py --type incident-quota \
  --title "Prove the quota pressure and the shed" \
  --why "Admission control sheds excess load with a 429 and a Retry-After, protecting the provider"
```

**Expected output:** ★ `provider: balanced-ai · balanced-std`, ★ `rate limit: 6
per 10s`, then the accounting — ★ `submitted: 40`, ★ `accepted: 34`, ★ `rejected
(429): 6` (shed with `Retry-After 10s`), ★ `quota utilization: 98%`, and ★
`provider status: quota_exceeded`.

**What the learner should notice:** Here is the counterintuitive part of the
incident: those six 429s are not a failure, they are the system working. The quota
alert looks alarming, but the accounting proves the admission control did its job —
forty requests arrived, thirty-four were served, and six were shed cleanly with a
`Retry-After` that tells each caller exactly when to come back. That shed is the
only reason `balanced-ai` sat at ninety-eight percent instead of falling over
entirely. A rejected request with a `Retry-After` is a promise kept; a provider
crashed under unshed load is an outage. Load shedding is a feature you are watching
succeed, and it buys you the time to fix the real fault.

### Step 4: Connect the cost drift and the quality regression to the provider

**Goal:** Reconcile the cost increase, to the cent, against the drivers that produced
it, then read the quality sampling — and see both land on the same degraded provider.

```bash
curl -s http://localhost:8000/incident/cost | python3 scripts/fmt.py --type incident-cost \
  --title "Connect the cost drift and the quality regression to the provider" \
  --why "The extra dollars tie to retries and failover on the degraded provider — reconciled to the cent"
curl -s http://localhost:8000/incident/quality | python3 scripts/fmt.py --type incident-quality \
  --title "Connect the cost drift and the quality regression to the provider" \
  --why "Grouped failure reasons that cluster on the degraded provider — every failure is a confident, wrong 200"
```

**Expected output:** first the cost — ★ `baseline: $0.0120 / request`, ★ `current:
$0.0210 / request` (`+75.0%`), drivers `retries on balanced-std` `+$0.0063` and
`fallback overhead` `+$0.0027`, ★ `reconciles to current: true`; then the quality —
★ `pass rate: 68.0% (17/25)` against `baseline 92.0%, objective >= 90%`, grouped
reasons (`hallucinated a policy number ×3`, `answer contradicts the source ×3`,
`off-format / schema invalid ×2`), and ★ `cluster: balanced-std (degraded window)`.

**What the learner should notice:** Cost drift is where teams wave their hands and
say "traffic must be up." Do not — reconcile it. The two drivers add up to exactly
the gap, and neither is more traffic: the slow primary gets retried before it fails
over, and every retry pays for a second call on the balanced tier; the failover adds
one more. The dollars did not leak, they went somewhere specific — `balanced-ai`.
Then the quality sample confirms the dimension your infrastructure dashboards can
never see: every one of the twenty-five responses returned a clean `200`, yet eight
were wrong anyway, and the failures *cluster* on `balanced-std` during its degraded
window rather than scattering at random. The same provider that owns the latency and
the cost is also handing back the bad answers. Model identity is where the evidence
converges — three symptoms, one name.

### Step 5: Choose the operator action from the evidence

**Goal:** Collapse the four symptoms into one root cause and assign a coordinated,
evidence-based action to each dimension.

```bash
curl -s http://localhost:8000/incident/action | python3 scripts/fmt.py --type incident-action \
  --title "Choose the operator action from the evidence" \
  --why "Four alerts, one provider fault, one evidence-based decision per dimension"
```

**Expected output:** ★ `root cause: balanced-ai (balanced-std) degraded`, then four
decisions, each with its evidence, action, and expected effect — fail over off
`balanced-std` for latency, keep the tighter rate limit for quota, cap retries for
cost, and sample-and-block the degraded provider for quality — then ★ `disposition:
ACT`.

**What the learner should notice:** This is the payoff, and it is why you did the
other four steps. Every alert traced back to one degraded provider, so you are not
making four decisions — you are making one, with four coordinated moves. Open the
circuit and fail `balanced-std` over to a healthy tier, and the latency, the retry
cost, and the quota pressure all fall together because they shared a cause. Sample
and block the degraded provider's output so a wrong answer never reaches a customer
or a training set. Notice that each action names the evidence that justifies it —
that is what makes it defensible in the postmortem. Four alerts, one root cause, one
decision. That is what operating a GenAI service under fire actually looks like.

## Preflight check

```bash
bash module2/scripts/m2-demo4-diagnose-latency-quota-cost-quality.preflight.sh
```

Runs every step above, captures each command and its output, maps each step to
TO2 / EO2e / TO3 / EO3a–e, and writes a readable log to
`preflight-logs/m2-demo4-diagnose-latency-quota-cost-quality.log`. Expect `PASS: 5  FAIL: 0`.

## Cleanup

```bash
./scripts/module2-demo-reset.sh
```

## Key files

- `app/main.py` — the `/incident/run`, `/incident/alerts`, `/incident/dashboard`,
  `/incident/isolate`, `/incident/quota`, `/incident/cost`, `/incident/quality`,
  and `/incident/action` endpoints
- `app/incident/diagnose.py` — the deterministic incident: alert timeline, operator
  dashboard, isolating trace, quota shed, cost reconciliation, quality regression,
  and the root-cause action
- `observability/grafana/` — the provisioned Prometheus datasource and the GenAI
  incident dashboard
- `docker-compose.yml` — the `prometheus` and `grafana` services (the `obs` profile)
- `scripts/fmt.py` — the `incident-alerts` / `incident-dashboard` /
  `incident-isolate` / `incident-quota` / `incident-cost` / `incident-quality` /
  `incident-action` views
