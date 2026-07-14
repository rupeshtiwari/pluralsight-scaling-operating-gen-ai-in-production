# Module 2 — Demo: Prove circuit breaker fallback and retry backoff

## Why this matters

**The problem:** A model provider will fail — it will error, slow to a crawl, or
run out of quota. When it does, two naive reactions both make things worse. If you
keep sending every request to the failing provider, you pile latency and cost onto
calls that are doomed. If you retry each failure hard, you turn one sick provider
into a **retry storm** that guarantees it never recovers. What you want instead is
a control that *notices* the provider is unsafe, stops hammering it, sends traffic
to a healthy alternative, and carefully tests whether the original has come back —
all without a human watching. How do you prove that control works, deterministically,
without waiting for a real outage?

**What you will see:** Five moments that turn "the provider failed" into "the caller
never noticed" — the breaker's configured thresholds and fallback routes; a single
drill that walks the circuit through **closed → open → half-open → recovered** with
every transition visible; the fallback routing that keeps the caller whole while the
primary is unsafe; the retry attempts spaced by exponential backoff and capped so
they never storm; and a reconciliation that confirms the caller response, the durable
receipt, and the retry log all agree.

**What you walk away with:** A circuit breaker that detects a failing or slow provider
and automatically fails over to a healthy model (EO2c), retry logic with exponential
backoff tuned so a struggling provider is retried and then abandoned rather than
stormed (EO2d), and a controlled way to simulate failures and prove the whole thing
recovers (EO2e). Every decision is measured in Redis and recorded in PostgreSQL.
(This proves failover and recovery for one primary against one healthy alternative —
using deterministic provider stubs, not a live outage.)

## Learning objectives covered

| Step | LO sub-element | What proves it |
|------|----------------|----------------|
| 1 | EO2e | Slow, error, and quota failures are deterministic provider stubs; thresholds are explicit |
| 2 | EO2c, EO2e | The circuit moves through closed, open, half-open, recovered, driven by all three failure modes |
| 3 | EO2c | Fallback routes traffic to a healthy alternative; the caller sees no failure |
| 4 | EO2d | Retries use exponential backoff, capped — and an open circuit makes zero attempts |
| 5 | EO2e | Caller response, fallback receipt, and retry log reconcile to one confirmed outcome |

## What this demo proves — and each step is unique

| Step | Endpoint | What it teaches (nothing repeats) |
|------|----------|-----------------------------------|
| 1 | `/resilience/circuit-config` | The thresholds, fallback routes, and backoff schedule that govern the breaker |
| 2 | `/resilience/circuit` | One drill walks every circuit state, each transition tagged |
| 3 | `/resilience/fallback` | A healthy alternative keeps the caller whole while the primary is unsafe |
| 4 | `/resilience/retry-log` | Backoff spaces the retries and an open circuit prevents the storm |
| 5 | `/resilience/failover-reconcile` | Caller response, fallback receipt, and retry log agree — and the circuit recovered |

## Prerequisites

### Software this clip needs — do you have it?

This clip uses **Docker Desktop** (with Compose), **curl**, **jq**, **python3**,
**psql**, and **tmux**. Two commands cover every case:

```bash
bash scripts/ensure-ready.sh       # CHECK  — ✔ / ✗ for each tool, with a fix for anything missing
bash environment-setup/setup.sh    # INSTALL — one step: installs everything the course uses, then the pinned deps
```

- **First time on this Mac?** Run the install step once. It installs Homebrew,
  Docker Desktop, Python 3.13, tmux, jq, curl, and psql — then builds the Python
  environment. When it prints `READY`, you have everything this clip needs.
- **Already set up?** The check confirms you're good in seconds. (`demo_up.sh`
  below runs it for you anyway, so you can skip straight to starting the stack.)

### Start the stack

**Start the stack first.** This runs the environment readiness check
(`scripts/ensure-ready.sh`) — which **auto-starts Docker Desktop** if it's
installed but not open — then brings up FastAPI, Redis, and PostgreSQL and waits
until healthy:

```bash
bash module2/scripts/demo_up.sh
```

Wait for `✔ stack healthy`. It then leaves you with a clean, reset stack.

Confirm the layers are up (this demo needs all three):

- Server running: `curl -s http://localhost:8000/health | python3 -m json.tool`
- Redis reachable (the circuit state, timeline, and retry log live here)
- PostgreSQL reachable (every primary and fallback decision persists a receipt)

For a clean, repeatable run, reset **before** you start:

```bash
./scripts/module2-demo-reset.sh
```

## Demo steps

### Step 1: Load the circuit-breaker configuration

**Goal:** Show the failure modes the breaker defends against and the thresholds,
fallback routes, and backoff schedule that govern it.

```bash
curl -s http://localhost:8000/resilience/circuit-config | python3 scripts/fmt.py --type circuit-config \
  --title "Load the circuit-breaker configuration" \
  --why "The thresholds that trip and recover the circuit, the fallback routes, and the retry backoff schedule"
```

**Expected output:** ★ `failure modes: error, quota, slow`, then the thresholds —
★ `failure_threshold: 3`, ★ `cooldown_probes: 1`, ★ `success_threshold: 1`,
★ `max_attempts: 3` — the fallback routes (`balanced-std → econo-mini`, and the
others), and a three-row backoff schedule (`0ms`, `430ms`, `870ms`).

**What the learner should notice:** Every number here is a deliberate operator
choice, and every failure is simulated. The failure modes — `error`, `quota`,
`slow` — come from deterministic provider stubs, so the same fault reproduces on
demand with no real outage and no external call. The `failure_threshold` of 3 is
the patience budget: three consecutive failures and the breaker trips open. The
`cooldown_probes` of 1 says how long to wait before testing recovery, and
`success_threshold` of 1 says one good probe is enough to close it again. The
fallback routes name the healthy alternative for each tier — `balanced-std` fails
over to `econo-mini`. And the backoff schedule is the retry spacing: a first
attempt immediately, then waits that double each time with a little jitter so a
fleet of callers does not retry in lockstep. These are the knobs; the next steps
run them.

### Step 2: Walk the circuit through its states

**Goal:** Run one deterministic drill and watch the circuit move through closed,
open, half-open, and recovered — with the state that handled each request visible.

```bash
curl -s -X POST http://localhost:8000/resilience/drill >/dev/null
curl -s http://localhost:8000/resilience/circuit | python3 scripts/fmt.py --type circuit \
  --title "Walk the circuit through its states" \
  --why "One drill drives the primary from healthy to open to half-open to recovered — every transition visible"
```

**Expected output:** ★ `primary: balanced-std`, ★ `fallback: econo-mini`,
★ `tripped: true`, ★ `recovered: true`, then an eight-row journey whose `primary
cond` column spans all three failure modes — `slow`, `error`, `quota` — whose
`circuit` column shows `closed`, then `open`, then `half_open`, then back to
`closed`, and whose `transition` column reads `failover`, `trip`, `shed`,
`probe_failed`, `recovered`, `healthy`.

**What the learner should notice:** This is the state machine doing its whole job in
one pass, against all three deterministic failure modes. Read the `primary cond`
column: the first three requests hit the primary while it returns a **slow**
response, then a hard **error**, then a **quota** exhaustion — three different faults,
each simulated by a provider stub, and each counting equally as a failure. Every one
is retried, fails, and **fails over** to the alternative; on the third, the failure
count reaches the threshold and the circuit **trips** to `open`. What matters is that
the breaker does not care *which* fault occurred — slow, error, or quota, a failure
is a failure, and three in a row is enough to stop trusting the provider. While
`open`, requests are **shed** straight to the fallback with zero primary attempts.
After the cooldown, one request is handled in `half_open` — a single probe — and
because the primary is still failing (a `quota` fault this time), the probe fails and
the circuit reopens. Later, once the primary is healthy again, the next `half_open`
probe succeeds and the circuit is **recovered** to `closed`. The `circuit` column is
the key: it shows the exact state each request was handled under, so `half_open` is
not a hidden internal detail — it is a visible, thresholded step between failing and
trusting the provider again.

### Step 3: Prove fallback routing keeps the caller whole

**Goal:** Show that while the primary was unsafe, a healthy alternative served the
traffic — so none of the primary's failures reached the caller.

```bash
curl -s http://localhost:8000/resilience/fallback | python3 scripts/fmt.py --type fallback \
  --title "Prove fallback routing keeps the caller whole" \
  --why "While the primary is unsafe, a healthy alternative serves — so primary failures never reach the caller"
```

**Expected output:** ★ `primary (failed): balanced-std`, ★ `fallback (healthy):
econo-mini`, ★ `requests answered: 8 / 8`, ★ `caller errors: 0`, ★ `served by
primary: 2`, ★ `served by fallback: 6`.

**What the learner should notice:** This is the payoff of the breaker, stated in the
only terms the caller cares about. Eight requests arrived while the primary provider
was erroring for six of them — and yet **every single request was answered**, and
**zero errors reached the caller**. Six were quietly rerouted to the healthy
`econo-mini` fallback while the primary was unsafe; two were served by the primary
once it recovered. The provider had a bad day; the caller never found out. That is
the difference between a failure that becomes an incident and a failure that becomes
a footnote — the fallback absorbed the blast so the user-facing contract held.

### Step 4: Inspect retry backoff and prove no storm

**Goal:** Show the retry attempts spaced by exponential backoff and capped, and
prove that opening the circuit stopped the retries instead of multiplying them.

```bash
curl -s http://localhost:8000/resilience/retry-log | python3 scripts/fmt.py --type retry-log \
  --title "Inspect retry backoff and prove no storm" \
  --why "Retries are capped and spaced by exponential backoff; once the circuit opens, the primary is not retried at all"
```

**Expected output:** ★ `retry cap: 3 attempts`, the backoff schedule (`0ms`,
`430ms`, `870ms`), then the storm check — ★ `primary attempts WITH breaker: 12`,
★ `primary attempts WITHOUT breaker: 18`, ★ `retries avoided by opening: 6`.

**What the learner should notice:** Retries are necessary but dangerous, and this is
how you make them safe. Each failing request is retried at most **3** times, and the
attempts are spaced by exponential backoff — an immediate try, then roughly 430ms,
then 870ms — with jitter so many callers do not retry on the same beat. Backoff is
tuned to LLM latency: waits long enough to matter for a slow inference call, not so
long the caller gives up. The decisive number is the comparison: without a breaker,
every one of the failing requests would retry to the cap — **18** primary attempts
pounding a provider that is already down. With the breaker, once it opens the primary
gets **zero** further attempts, cutting that to **12**. Those six avoided retries are
the retry storm that never happened — recovery logic that reduces pressure instead of
adding to it.

### Step 5: Reconcile caller response, receipt, and retry log

**Goal:** Line up the three sources of truth for the drill and read the single
confirmed outcome an operator can trust.

```bash
curl -s http://localhost:8000/resilience/failover-reconcile | python3 scripts/fmt.py --type failover-reconcile \
  --title "Reconcile caller response, receipt, and retry log" \
  --why "CONFIRMED only when the caller response, the PostgreSQL fallback receipt, and the retry log agree and the circuit recovered"
```

**Expected output:** ★ `disposition: CONFIRMED`, ★ `counts_agree: true`,
★ `recovered: true`, ★ `receipts_complete: true`, then a per-role row with three
columns — `caller`, `receipt`, `retry log` — reading `primary 2 / 2 / 2 ✓` and
`fallback 6 / 6 / 6 ✓`.

**What the learner should notice:** A resilience control you cannot audit is a
resilience control you cannot trust, so this step reconciles the drill across the
three independent records the outline calls for — and they are genuinely independent.
The **caller response** is what each request returned to its caller: two served by the
primary, six by the fallback. The **fallback receipt** is the durable PostgreSQL
record — one row per request, each tagged with the model it fell back from — and it
says the same two and six. The **retry log** is the separate attempt record, derived
from what the retry machinery actually did rather than from the summary, and it counts
the same split again. Three records, built by three different parts of the system,
and every one agrees: two primary, six fallback. Because they agree **and** the circuit
`recovered`, the disposition reads `CONFIRMED`. If a fallback had been miscounted, a
receipt lost, or the retry log disagreed — or if the circuit had never closed — one
check would fail and the disposition would read `BLOCKED`, pointing at the exact role
to investigate. This is the difference between *hoping* failover worked and *proving*
it did: the caller, the ledger, and the retry log all tell the identical story. Reset
and run the drill again and you get the same `CONFIRMED` — failover and recovery,
validated end to end, repeatably.

## Preflight check

```bash
bash module2/scripts/clip3_preflight_check.sh
```

Runs every step above, captures each command and its output, maps each step to
EO2c/d/e, and writes a readable log to `module2/clip3_preflight_log.txt`. Expect
`PASS: 5  FAIL: 0`.

## Cleanup

```bash
./scripts/module2-demo-reset.sh
```

## Key files

- `app/main.py` — the `/resilience/circuit-config`, `/resilience/drill`,
  `/resilience/circuit`, `/resilience/fallback`, `/resilience/retry-log`, and
  `/resilience/failover-reconcile` endpoints
- `app/providers/registry.py` — the breaker thresholds, `FALLBACK_ROUTES`, the
  `backoff_schedule`, and the deterministic drill sequence
- `app/resilience/circuit.py` — the state machine, retry/backoff logic, and drill runner
- `app/db/redis_client.py` — the `circuit:state`, `circuit:timeline`, `circuit:retrylog`,
  and role-tally hashes
- `app/db/postgres.py` — the circuit-breaker receipts tagged with `fallback_from`
- `scripts/fmt.py` — the `circuit-config` / `circuit` / `fallback` / `retry-log` /
  `failover-reconcile` views
