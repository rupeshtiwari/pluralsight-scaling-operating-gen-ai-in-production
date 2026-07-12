# Module 1 — Clip 3: Demo: Prove weighted routing across model tiers (6 minutes)

## Why this matters

**The problem:** You now have three model tiers behind one adapter boundary, but
every request still goes to the same default model. That wastes money — most
requests are easy and could run on the cheap tier, while only a few need the
premium one. You want to send, say, half your traffic to the low-cost model, a
third to the balanced one, and the rest to premium — **on purpose, and provably**,
not by hoping a load balancer does something reasonable.

**What you will see:** Six moments that turn "we route traffic" into "we route
traffic by a policy we can prove" — the weighted policy itself, a controlled
batch of requests, the individual decisions the same endpoint makes, the Redis
counters that measure the spread, the PostgreSQL receipts that tie each choice
to its cost, and a final check that the observed distribution equals the
configured weights.

**What you walk away with:** Weighted load balancing across model tiers you can
configure, run, and verify end to end — distribution measured in Redis, cost tied
to each choice in PostgreSQL, and a proof that the split matches your weights.

## Learning objectives covered

| LO | Description |
|----|-------------|
| EO1b | Implement weighted load balancing across multiple AI models to distribute requests according to cost and latency targets |

## What this demo proves — and each step is unique

| Step | Endpoint | What it teaches (nothing repeats) |
|------|----------|-----------------------------------|
| 1 | `/routing/policy` | Weights are set against per-tier cost and latency targets (50 / 30 / 20) |
| 2 | `/route/batch` | One endpoint routes many requests under the weighted policy |
| 3 | `/routing/last-batch` | The same endpoint distributes requests across different tiers |
| 4 | `redis-cli HGETALL` | The Redis datastore itself holds the spread — read directly |
| 5 | `receipts` (psql) | Each model choice is tied to its cost and the routing policy |
| 6 | `/routing/validate` | The observed distribution equals the configured weights |

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
bash module1/scripts/demo_up.sh
```

Wait for `✔ stack healthy`. It then leaves you with a clean, reset stack.

Confirm the layers are up (this demo needs all three):

- Server running: `curl -s http://localhost:8000/health | python3 -m json.tool`
- Redis reachable (the routing counters in Step 4 live here)
- PostgreSQL reachable (each weighted decision persists a receipt for Step 5)

For a clean, repeatable distribution, reset **before** you run the batch — this
clears receipts **and** the routing counters, so the batch starts from zero:

```bash
./scripts/module1-demo-reset.sh
```

## Demo steps

### Step 1: Load the weighted routing policy

**Goal:** Show the policy itself — the per-tier weights, and the cost and latency
targets that justify them.

```bash
curl -s http://localhost:8000/routing/policy | python3 scripts/fmt.py --type policy \
  --title "Load the weighted routing policy" \
  --why "Weights are set by cost and latency target — most traffic to the cheapest, fastest tier; least to the most expensive one"
```

**Expected output:** ★ `policy_name: weighted`, then a row per tier showing
**weight**, **latency target**, and **cost estimate**:

```text
tier          weight   latency target   cost estimate
econo-mini    50%      400ms            $0.001350
balanced-std  30%      700ms            $0.008100
premium-max   20%      1200ms           $0.032400
```

**What the learner should notice:** This is a policy, not a guess — and the
policy shows *why* each weight was chosen. Half the traffic goes to
`econo-mini` because it is the cheapest and lowest-latency tier; thirty percent
to `balanced-std`; and only twenty percent to `premium-max`, whose cost and
latency target are the highest. The weight column and the cost/latency columns
side by side are the decision logic: spend the volume on the cheap, fast tier,
reserve the expensive one for the few requests that need it. The weights are a
config value; changing them re-shapes the traffic without touching a single
caller. (The cost estimate is a *comparable* figure for like-for-like reading,
priced on one fixed 27-token reference prompt — the prompt the batch routes — so
it lines up with the receipts in Step 5. It is not a universal request price:
real cost scales with the tokens in each request, so read these as *relative* —
premium is roughly 24× the low-cost tier — rather than a fixed charge.)

### Step 2: Run a controlled traffic batch

**Goal:** Send a fixed batch of requests through the same endpoint under the
weighted policy.

```bash
curl -s -X POST http://localhost:8000/route/batch \
  -H "Content-Type: application/json" -d '{"count": 20}' \
  | python3 scripts/fmt.py --type batch \
  --title "Run a controlled traffic batch" \
  --why "One endpoint, many requests — the weighted policy decides each"
```

**Expected output:** ★ `policy_name: weighted`, ★ `route_reason:
weighted_distribution`, ★ `requests routed: 20`.

**What the learner should notice:** Twenty requests just went through one
endpoint, each routed by the weighted policy — not the baseline default from the
previous clip. The `route_reason` says `weighted_distribution`, so every receipt
this batch wrote is stamped with *why* it was routed. We sent a controlled,
repeatable number so the distribution is easy to reason about: 20 requests
against 50/30/20 land as 10, 6, and 4.

> **Deterministic here, probabilistic in production.** This selector is
> *deterministic* — a clean batch of 20 always splits exactly 10/6/4, which is
> what makes it testable in CI and repeatable on camera. A production weighted
> router is usually *probabilistic*: it converges toward the configured ratio
> over a large sample rather than guaranteeing an exact split for every small
> batch. Same target distribution, different guarantee.

### Step 3: Inspect the individual routed decisions

**Goal:** Look at individual requests from the batch and see the endpoint pick
different tiers.

```bash
curl -s "http://localhost:8000/routing/last-batch?limit=6" | python3 scripts/fmt.py --type samples \
  --title "Inspect the individual routed decisions" \
  --why "Requests entering the same endpoint are distributed across different model tiers"
```

**Expected output:** a table of ★ rows — each with request id, `model`, `tier`,
`latency target`, and `cost` — showing `econo-mini`, `balanced-std`, and
`premium-max` all appearing.

**What the learner should notice:** Requests entering the same endpoint are
distributed across different model tiers. The first few already touch all three,
and the `cost` column moves with them: a tenth of a cent on the low-cost tier,
more on premium. The `latency target` column is the tier's *configured* target
(400 / 700 / 1200 ms), not a measured request time — it's the profile the weight
was chosen against. This is the weighted policy working per request: no caller
asked for a specific model; the service distributed them.

### Step 4: Read the routing counters straight from Redis

**Goal:** Read the counters directly from the Redis datastore — not through the
application — to measure the actual spread across tiers.

```bash
docker compose exec -T redis redis-cli --json HGETALL routing:counters \
  | python3 scripts/fmt.py --type redis-counters \
  --title "Read the routing counters straight from Redis" \
  --why "The tally lives in the Redis datastore itself — read it directly, not through the application"
```

**Expected output:** ★ `total requests: 20`, then the distribution read from the
hash — `econo-mini 10`, `balanced-std 6`, `premium-max 4`.

**What the learner should notice:** This is `HGETALL` against the Redis hash
`routing:counters` — the datastore itself, queried directly, with the
application out of the picture. The batch incremented these fields with
`HINCRBY` on every route decision, and here they are: ten, six, four out of
twenty, exactly 50/30/20. Because we read Redis directly (rather than an endpoint
that *reports* Redis), this is independent proof of the spread — the same running
scoreboard an operator can watch live in production. (The app also exposes this
at `GET /routing/counters` as a convenience view, but the datastore is the source
of truth.)

### Step 5: Connect each model choice to cost and policy

**Goal:** Query PostgreSQL receipts to tie each model choice to its cost and the
routing policy.

```bash
docker compose exec -T postgres psql -U genai -d genai -tAc "SELECT row_to_json(r) FROM (
  SELECT DISTINCT ON (selected_model)
         selected_model, provider_tier, cost_estimate_usd, policy_name
  FROM receipts ORDER BY selected_model, created_at DESC) r" \
  | python3 scripts/fmt.py --type receipts \
  --title "Connect each model choice to cost and policy" \
  --why "Every tier lands in the same receipt columns — cost differs, the policy is identical"
```

**Expected output:** one ★ row per tier — `selected_model`, `provider_tier`,
`cost` (differs by tier), and `policy_name: weighted` (identical on every row).

**What the learner should notice:** The receipts are the durable record behind
the counters. Each tier carries a different `cost_estimate_usd` — that is the
whole point of weighting toward the cheaper model — but every row shows the same
`policy_name: weighted`. So you can answer, months later, not just *which* model
served a request and what it cost, but *under which routing policy* — straight
from PostgreSQL, no rerun needed.

### Step 6: Confirm the distribution matches the configured weights

**Goal:** Compare the observed distribution against the configured weights.

```bash
curl -s http://localhost:8000/routing/validate | python3 scripts/fmt.py --type validate \
  --title "Confirm the distribution matches the configured weights" \
  --why "Observed picks equal the configured weights — the balancing is intentional and repeatable"
```

**Expected output:** ★ `total requests: 20`, ★ `all_match: true`, then a per-tier
line — weight %, expected, observed, and a ✓ — for `econo-mini`, `balanced-std`,
and `premium-max`.

**What the learner should notice:** This is the disposition: for every tier, the
observed count equals the expected count from its weight, and `all_match` is
true. Policy, counters, and receipts agree. Reset and run the batch again and you
get the exact same split — that exact match is a **test-mode deterministic
guarantee** (which is what makes it CI-testable and repeatable on demand), not a
claim that a probabilistic production router hits 10/6/4 on every 20 requests.
The property you're proving is that the routing *honours the configured
distribution* — provably, not just by assertion.

## Best-practice callout

**Make traffic distribution a declared policy, not an accident.** Weight your
tiers explicitly against cost and latency targets, route every request through
the policy, and keep two independent proofs — the counters in the Redis
datastore (read directly) and the durable receipts in PostgreSQL. If the
observed split doesn't match the configured weights, you have a routing bug, and
now you can see it. In production the split is usually probabilistic and
converges to the target over a large sample; here it is deterministic so it can
be validated exactly in CI.

## Narration notes

- **Pronounce identifiers, don't spell them.** Say the `low_cost` tier as
  **"low-cost"** (read the underscore as a hyphen), and read model ids naturally
  — "econo-mini", "balanced-std", "premium-max". The underscore is fine on
  screen; it should never be spoken as "low underscore cost."
- **Frame cost as workload-dependent.** The dollar figures are a *comparable*
  estimate for one fixed 27-token reference prompt, not a universal request
  price. Narrate them as relative — "premium costs roughly twenty-four times the
  low-cost tier for the same request" — so the learner hears that real cost
  scales with the tokens in each request.
- **Deterministic vs production.** When you reach the 10/6/4 split, say it is an
  exact, repeatable result *by design* for validation; a production weighted
  router converges to 50/30/20 over a large sample rather than hitting it on
  every twenty requests.

## Preflight check

```bash
bash module1/scripts/clip3_preflight_check.sh
```

Runs every step above, captures each command and its output, maps each step to
EO1b, and writes a readable log to `module1/clip3_preflight_log.txt`. Expect
`PASS: 6  FAIL: 0`.

## Cleanup

```bash
./scripts/module1-demo-reset.sh
```

## Key files

- `app/main.py` — the `/routing/policy`, `/route/batch`, `/routing/counters`,
  `/routing/validate` endpoints
- `app/providers/registry.py` — the weighted weights and the deterministic,
  evenly-spread pick sequence
- `app/routing/weighted.py` — the weighted routing decision
- `app/db/redis_client.py` — the routing sequence and the per-tier counter hash
  (`routing:counters`, incremented with `HINCRBY`, read in Step 4 via `HGETALL`)
- `app/db/postgres.py` — the receipts the batch persists
- `scripts/fmt.py` — the `policy` / `batch` / `samples` / `redis-counters` /
  `receipts` / `validate` views
