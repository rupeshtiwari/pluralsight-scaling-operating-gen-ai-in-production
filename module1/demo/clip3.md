# Module 1 — Demo: Weighted Routing Across Model Tiers

## What This Demo Proves

You will load a weighted routing policy that splits traffic **50 / 30 / 20**
across three model tiers — chosen by each tier's cost and latency target — then
run a controlled batch of 20 requests through one endpoint. You will read the
resulting distribution **straight from Redis** and confirm it against the
**PostgreSQL receipts**, proving the traffic landed exactly where the policy
declared: `econo-mini 10`, `balanced-std 6`, `premium-max 4`. This is weighted
load balancing you can configure, run, and verify end to end.

## Learning Objectives Covered

| LO | What You Will Be Able To Do After This Demo |
|----|---------------------------------------------|
| EO1b | Implement weighted load balancing across model tiers, distribute requests by cost and latency targets, and verify the split from the datastore (Redis) and durable receipts (PostgreSQL) |

## Architecture — One Endpoint, One Policy, Two Proofs

```
POST /route/batch (20 requests, same prompt)
   │
   ▼
┌──────────────────────────────────────────────────────────┐
│  FastAPI Orchestrator                                      │
│  ┌───────────────────┐     ┌──────────────────────────┐  │
│  │ Weighted policy    │────▶│ Adapter layer            │  │
│  │ 50 / 30 / 20       │     │ econo / balanced / premium│ │
│  └───────────────────┘     └──────────────────────────┘  │
│           │                          │                    │
│           ▼                          ▼                    │
│  ┌──────────────┐          ┌──────────────────┐          │
│  │ Redis counters│          │ PostgreSQL receipts│        │
│  │ (HINCRBY)     │          │ (cost + policy)    │        │
│  └──────────────┘          └──────────────────┘          │
└──────────────────────────────────────────────────────────┘
```

Redis is the live scoreboard (Step 4). PostgreSQL is the durable record
(Step 5). Both are checked against the configured weights (Step 6).

## Prerequisites

Complete the one-time setup in the [root README](../../README.md). Then start
the stack and reset to a clean, repeatable state:

```bash
bash module1/scripts/demo_up.sh    # readiness check (auto-starts Docker) → FastAPI, Redis, PostgreSQL, waits healthy
./scripts/module1-demo-reset.sh    # clears receipts AND routing counters — the batch starts from zero
```

To check the tools first without starting anything: `bash scripts/ensure-ready.sh`.

## Demo Steps

### Step 1: Load the Weighted Policy (EO1b)

**What we are doing:** Loading the policy — the per-tier weights, and the cost
and latency targets that justify them.

```bash
curl -s http://localhost:8000/routing/policy | python3 scripts/fmt.py --type policy \
  --title "Load the weighted routing policy" \
  --why "Weights are set by cost and latency target — most traffic to the cheapest, fastest tier; least to the most expensive one"
```

**Validate:**

| Field | Expected | What It Means |
|-------|----------|---------------|
| policy_name | `weighted` | The active traffic-splitting policy |
| weights | econo-mini 50% · balanced-std 30% · premium-max 20% | Half the traffic to the cheapest tier, by design |
| latency target | 400ms / 700ms / 1200ms | The configured target each weight was chosen against |
| cost estimate | $0.001350 / $0.008100 / $0.032400 | Comparable cost for one fixed reference prompt (not a universal price) |

**What you proved:** The weights are set against per-tier cost and latency
targets — most traffic to the cheapest, fastest tier; the least to the most
expensive one. That is the EO1b design rationale, visible on one screen.

### Step 2: Run a Controlled Traffic Batch (EO1b)

**What we are doing:** Sending a fixed batch of 20 requests through one endpoint
under the weighted policy.

```bash
curl -s -X POST http://localhost:8000/route/batch \
  -H "Content-Type: application/json" -d '{"count": 20}' \
  | python3 scripts/fmt.py --type batch \
  --title "Run a controlled traffic batch" \
  --why "One endpoint, many requests — the weighted policy decides each"
```

**Validate:**

| Field | Expected | What It Means |
|-------|----------|---------------|
| policy_name | `weighted` | Every request in the batch used the weighted policy |
| route_reason | `weighted_distribution` | Each receipt records *why* it was routed |
| requests routed | `20` | A controlled batch — 50/30/20 maps cleanly to 10/6/4 |

**What you proved:** One endpoint routed 20 requests under the weighted policy.
The split is **deterministic here** — a clean batch of 20 always lands 10/6/4,
which is what makes it CI-testable and repeatable on camera. A production
weighted router is **probabilistic**: it converges toward 50/30/20 over a large
sample rather than hitting an exact split on every small batch.

### Step 3: Inspect the Individual Routed Decisions (EO1b)

**What we are doing:** Looking at individual requests from the batch to see the
endpoint select different tiers.

```bash
curl -s "http://localhost:8000/routing/last-batch?limit=6" | python3 scripts/fmt.py --type samples \
  --title "Inspect the individual routed decisions" \
  --why "Requests entering the same endpoint are distributed across different model tiers"
```

**Validate:**

| Field | Expected | What It Means |
|-------|----------|---------------|
| model | econo-mini, balanced-std, premium-max all appear | The same endpoint distributes across tiers |
| latency target | 400ms / 700ms / 1200ms | The tier's *configured* target, not a measured runtime |
| cost | moves with the tier | A tenth of a cent on the low-cost tier, more on premium |

**What you proved:** Requests entering the same endpoint are distributed across
different model tiers — no caller asked for a specific model; the service
distributed them.

### Step 4: Read the Counters Straight From Redis (EO1b)

**What we are doing:** Reading the counters directly from the Redis datastore —
not through the application — to measure the actual spread.

```bash
docker compose exec -T redis redis-cli --json HGETALL routing:counters \
  | python3 scripts/fmt.py --type redis-counters \
  --title "Read the routing counters straight from Redis" \
  --why "The tally lives in the Redis datastore itself — read it directly, not through the application"
```

**Validate:**

| Field | Expected | What It Means |
|-------|----------|---------------|
| total requests | `20` | The batch size |
| econo-mini / balanced-std / premium-max | `10 / 6 / 4` | Exactly 50/30/20, read from the hash |
| source | `HGETALL routing:counters` | The datastore itself, not an app response |

**What you proved:** The batch incremented the Redis hash with `HINCRBY` on
every decision, and `HGETALL` reads it back as 10/6/4. Because we read Redis
directly, this is **independent** proof of the spread — the same running
scoreboard an operator watches in production. (`GET /routing/counters` exposes
the same numbers as an app view, but the datastore is the source of truth.)

### Step 5: Connect Each Choice to Cost and Policy (EO1b)

**What we are doing:** Querying PostgreSQL receipts to tie each model choice to
its cost and the routing policy.

```bash
docker compose exec -T postgres psql -U genai -d genai -tAc "SELECT row_to_json(r) FROM (
  SELECT DISTINCT ON (selected_model)
         selected_model, provider_tier, cost_estimate_usd, policy_name
  FROM receipts ORDER BY selected_model, created_at DESC) r" \
  | python3 scripts/fmt.py --type receipts \
  --title "Connect each model choice to cost and policy" \
  --why "Every tier lands in the same receipt columns — cost differs, the policy is identical"
```

**Validate:**

| Field | Expected | What It Means |
|-------|----------|---------------|
| selected_model / provider_tier | one row per tier | Every tier's choice persisted |
| cost_estimate_usd | differs by tier | The point of weighting toward the cheaper model |
| policy_name | `weighted` on every row | Durable record of which policy routed each request |

**What you proved:** The receipts are the durable record behind the counters.
Months later you can answer not just *which* model served a request and what it
cost, but *under which policy* — straight from PostgreSQL, no rerun needed.

### Step 6: Confirm Observed Matches Configured (EO1b)

**What we are doing:** Comparing the observed distribution against the configured
weights.

```bash
curl -s http://localhost:8000/routing/validate | python3 scripts/fmt.py --type validate \
  --title "Confirm the distribution matches the configured weights" \
  --why "Observed picks equal the configured weights — the balancing is intentional and repeatable"
```

**Validate:**

| Field | Expected | What It Means |
|-------|----------|---------------|
| total requests | `20` | The batch size |
| all_match | `true` | Observed == expected for every tier |
| per tier | expected == observed, ✓ | econo-mini 10/10, balanced-std 6/6, premium-max 4/4 |

**What you proved:** Policy, counters, and receipts agree. This exact match is a
**deterministic test guarantee** (what makes it CI-testable), not a claim that a
probabilistic production router hits 10/6/4 on every 20 requests. The property
proved is that the routing *honours the configured distribution*.

## Cleanup

```bash
./scripts/module1-demo-reset.sh
```

## Narration Notes

- Pronounce the `low_cost` tier as **"low-cost"** (read the underscore as a
  hyphen); the underscore is fine on screen, never spoken as "low underscore
  cost."
- Frame cost as **workload-dependent**: the dollar figures are a comparable
  estimate for one fixed 27-token reference prompt, not a universal request
  price — narrate them as relative (premium ≈ 24× the low-cost tier).
- State the **deterministic-vs-production** point at the 10/6/4 split: exact and
  repeatable by design for validation; production converges to 50/30/20 over a
  large sample.

## Preflight (Author Validation)

```bash
bash module1/scripts/clip3_preflight_check.sh
```

Runs every step, asserts EO1b, and writes `module1/clip3_preflight_log.txt`.
Expect `PASS: 6  FAIL: 0`.

## Summary — What You Learned

| Concept | What You Saw | Where |
|---------|--------------|-------|
| Weights are set by cost and latency target | Policy table: weight + latency target + cost per tier | Step 1 |
| One endpoint routes many requests by policy | 20 requests, `weighted_distribution` | Step 2 |
| The same endpoint distributes across tiers | econo / balanced / premium in the samples | Step 3 |
| The datastore itself holds the spread | `HGETALL routing:counters` → 10/6/4 | Step 4 |
| Each choice is tied to cost and policy | receipts: cost differs, `policy_name` identical | Step 5 |
| Observed equals configured | `all_match: true`, 10/6/4 == 50/30/20 | Step 6 |

## Key Files

| File | Purpose |
|------|---------|
| `app/main.py` | `/routing/policy`, `/route/batch`, `/routing/validate` endpoints |
| `app/providers/registry.py` | Weighted weights + the deterministic even-spread pick sequence |
| `app/routing/weighted.py` | The weighted routing decision |
| `app/db/redis_client.py` | The `routing:counters` hash (`HINCRBY` / `HGETALL`) |
| `app/db/postgres.py` | The receipts each batch persists |
| `scripts/fmt.py` | The `policy` / `batch` / `samples` / `redis-counters` / `receipts` / `validate` views |

## Next

Payload-based routing & deterministic overrides — route each request by its own
complexity, and pin specific classes to a tier on purpose.
