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

**What you will see:** Seven moves that take a four-alarm incident down to one root
cause — the alert timeline that shows which signal fired first; the operator
dashboard with all four dimensions red against their objectives; the single trace
that clears queueing, retry, and fallback and pins the latency on the provider;
the admission control that sheds the quota pressure with a 429 and a Retry-After;
the cost drift reconciled to the cent against its real drivers; the quality
sampling that confirms the regression and shows where it clusters; and the
root-cause decision that assigns one evidence-based action to each dimension.

**What you walk away with:** The ability to diagnose a production incident from
observability data (EO3e) — reading a simulated failure (EO2e) across tracing
(EO3a), structured evidence and cost (EO3b), quality sampling (EO3c), and SLO
alerting (EO3d), and resolving it with the resilience controls you built (TO2):
failover, load shedding, and retry limits.

## Learning objectives covered

| Step | LO sub-element | What proves it |
|------|----------------|----------------|
| 1 | EO2e, EO3d | A simulated incident surfaces an ordered alert timeline with a clear first signal |
| 2 | TO3, EO3d | An operator dashboard quantifies latency, quota, cost, and quality against objectives |
| 3 | EO3a, EO3e | One trace clears queueing, retry, and fallback and pins the latency on the provider |
| 4 | TO2, EO2e | Admission control sheds the quota pressure with a 429 and a Retry-After |
| 5 | EO3b | The cost drift reconciles to named drivers on the degraded provider |
| 6 | EO3c | Quality sampling confirms the regression and shows it clusters on the provider |
| 7 | EO3e, TO2 | Four symptoms resolve to one root cause with an evidence-based action per dimension |

## What this demo proves — and each step is unique

| Step | Command | What it teaches (nothing repeats) |
|------|---------|-----------------------------------|
| 1 | `/incident/alerts` | Which signal fired first — and why first is not root |
| 2 | `/incident/dashboard` | Four dimensions, red at once, against their objectives |
| 3 | `/incident/isolate` | The trace clears the innocent stages and names the culprit |
| 4 | `/incident/quota` | Load shedding is working, not failing |
| 5 | `/incident/cost` | The extra dollars reconcile to a cause, not a guess |
| 6 | `/incident/quality` | The regression clusters — it is not random noise |
| 7 | `/incident/action` | One root cause, one coordinated decision |

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

### Step 1: Read the alert timeline

**Goal:** Trigger the controlled incident and read the alerts in the order they
fired, so you know the first bad signal before you touch anything.

```bash
curl -s -X POST http://localhost:8000/incident/run >/dev/null
curl -s http://localhost:8000/incident/alerts | python3 scripts/fmt.py --type incident-alerts \
  --title "Read the alert timeline" \
  --why "Which signal fired first — the first alert is a symptom, not the root cause"
```

**Expected output:** ★ `first signal: LatencyP95AboveObjective`, then four alerts
in fire order — `+00:30` latency (`ticket`), `+01:10` quota (`ticket`), `+02:00`
cost (`ticket`), and `+02:40` output quality (`page`).

**What the learner should notice:** Four alerts in two minutes is the moment an
incident tempts you into the wrong move — splitting the team to chase all four.
Read the timeline instead. Latency fired first at thirty seconds, and the quality
breach — the one that actually pages a human — fired last. The order is a clue,
not a verdict: the first signal is almost never the root cause, it is just the
fastest symptom to cross a threshold. A page carries more weight than a ticket, so
the quality breach is where the customer pain is, but you do not fix four things.
You find the one fault underneath them.

### Step 2: Open the operator dashboard

**Goal:** Read all four dimensions at once — latency, quota saturation, cost per
request, and quality pass rate — each baseline against current against its
objective.

```bash
curl -s http://localhost:8000/incident/dashboard | python3 scripts/fmt.py --type incident-dashboard \
  --title "Open the operator dashboard" \
  --why "Four dimensions, baseline versus current against each objective — every panel red"
```

> The same metrics stream live to Grafana on the `obs` profile at
> `http://localhost:3000` — the terminal shows the incident snapshot; the browser
> shows it moving.

**Expected output:** ★ `window requests: 40`, then four breached panels —
`latency_p95_ms` `950 → 3750` (`<= 2500`), `quota_saturation_pct` `55 → 98`
(`<= 90`), `cost_per_request_usd` `$0.0120 → $0.0210` (`<= $0.0150`), and
`quality_pass_rate_pct` `92.0 → 68.0` (`>= 90.0`).

**What the learner should notice:** This is the board you actually stare at during
an incident, and every panel is red — which is exactly why raw dashboards panic
people. The value of the baseline column is that it turns each number into a
*movement*: latency nearly quadrupled, quota went from comfortable to nearly
exhausted, cost drifted up by three quarters, and quality fell twenty-four points.
Four dimensions moving together, in the same window, is itself the biggest clue in
the whole incident. Independent problems do not politely arrive at once. When
everything breaks at the same instant, suspect one shared cause — and go find it.

### Step 3: Isolate the latency from one trace

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

### Step 4: Prove the quota pressure and the shed

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

### Step 5: Trace the cost drift to its cause

**Goal:** Take the cost increase and reconcile it, to the cent, against the drivers
that actually produced it.

```bash
curl -s http://localhost:8000/incident/cost | python3 scripts/fmt.py --type incident-cost \
  --title "Trace the cost drift to its cause" \
  --why "The extra dollars tie to retries and failover on the degraded provider — reconciled to the cent"
```

**Expected output:** ★ `baseline: $0.0120 / request`, ★ `current: $0.0210 /
request` (`+75.0%`), ★ `objective: $0.0150 / request`, then the two drivers —
`retries on balanced-std` `+$0.0063` and `fallback overhead` `+$0.0027` — and ★
`reconciles to current: true`.

**What the learner should notice:** Cost drift is where teams wave their hands and
say "traffic must be up." Do not. Reconcile it. The baseline was one-point-two
cents a request; it is now two-point-one, a seventy-five percent jump. The two
drivers add up to exactly the gap, and neither of them is more traffic — they are
both the *same degraded provider*. The slow primary gets retried before it fails
over, and every retry pays for a second call on the balanced tier at thirty cents
per thousand tokens; the failover itself adds one more call. This is why model
identity belongs in your cost telemetry: the dollars did not leak, they went
somewhere specific, and that somewhere is `balanced-ai` again.

### Step 6: Confirm the quality regression from sampling

**Goal:** Read the output-quality sampling for the window and confirm the pass rate
dropped, and see where the failures cluster.

```bash
curl -s http://localhost:8000/incident/quality | python3 scripts/fmt.py --type incident-quality \
  --title "Confirm the quality regression from sampling" \
  --why "Grouped failure reasons that cluster on the degraded provider — every failure is a confident, wrong 200"
```

**Expected output:** ★ `pass rate: 68.0% (17/25)` against `baseline 92.0%,
objective >= 90%`, then the grouped failure reasons — `hallucinated a policy
number ×3`, `answer contradicts the source ×3`, `off-format / schema invalid ×2` —
and ★ `cluster: balanced-std (degraded window)`.

**What the learner should notice:** This is the dimension your infrastructure
dashboards can never see, and it is the one that pages. Every one of these
twenty-five responses returned a clean `200`; eight of them were wrong anyway —
hallucinated numbers, answers that contradict their own source, broken formats.
The pass rate fell from ninety-two to sixty-eight. But the real tell is that the
failures *cluster*: they are not scattered randomly across the fleet, they land on
`balanced-std` during its degraded window. Grouping the reasons is what turns a bad
number into a diagnosis. The same provider that owns the latency and the cost is
also handing back the bad answers. Three symptoms, one name.

### Step 7: Choose the operator action from the evidence

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
other six steps. Every alert traced back to one degraded provider, so you are not
making four decisions — you are making one, with four coordinated moves. Open the
circuit and fail `balanced-std` over to a healthy tier, and the latency, the retry
cost, and the quota pressure all fall together because they shared a cause. Sample
and block the degraded provider's output so a wrong answer never reaches a customer
or a training set. Notice that each action names the evidence that justifies it —
that is what makes it defensible in the postmortem. Four alerts, one root cause, one
decision. That is what operating a GenAI service under fire actually looks like.

## Preflight check

```bash
bash module2/scripts/clip6_preflight_check.sh
```

Runs every step above, captures each command and its output, maps each step to
TO2 / EO2e / TO3 / EO3a–e, and writes a readable log to
`module2/clip6_preflight_log.txt`. Expect `PASS: 7  FAIL: 0`.

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
