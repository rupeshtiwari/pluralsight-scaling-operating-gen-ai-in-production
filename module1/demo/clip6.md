# Module 1 — Demo: Validate routing receipts, counters, and final disposition

## Why this matters

**The problem:** You have three routing policies now — baseline, weighted, and
payload-based with deterministic overrides. Each one proved itself in isolation.
But in production a single service runs *all* of them at once, and an operator has
to trust the whole thing. The API says one request went to premium; the live
counters say the spread is 5/3/2; the database holds a receipt for every call.
What happens when those three records *disagree*? A routing bug, a dropped
receipt, or a miscounted tier is exactly the kind of silent drift you must catch
before you sign off. How do you confirm the routing is correct — not for one
policy, but for the mixed traffic the service actually sees?

**What you will see:** Six moments that turn three separate proofs into one
operator sign-off — a mixed batch of weighted, payload, and override requests
through one service; the individual decisions each tagged with its policy; the
aggregate spread in the Redis datastore; the full per-request receipts in
PostgreSQL with the operator field set; a reconciliation that lines the three
records up side by side; and a final disposition that reads **CONFIRMED** only
when the API, the counters, and the receipts all agree.

**What you walk away with:** A repeatable way to validate the whole routing layer
at once — three independent records (API, Redis, PostgreSQL) reconciled per
routing kind, plus a single go/no-go disposition an operator can act on. Policy,
receipt, and model behavior must agree, or the disposition blocks.

## Learning objectives covered

| LO | Description |
|----|-------------|
| TO1 | Implement load balancing and intelligent request routing for multi-model GenAI service architectures |
| EO1a | Design a dedicated AI service layer that decouples application logic from model provider dependencies |
| EO1b | Implement weighted load balancing across multiple AI models |
| EO1c | Apply payload-based routing to direct requests to appropriate model tiers |
| EO1d | Evaluate the trade-offs between weighted distribution and deterministic routing |

## What this demo proves — and each step is unique

| Step | Endpoint | What it teaches (nothing repeats) |
|------|----------|-----------------------------------|
| 1 | `/route/mixed` | One service runs weighted, payload, and override traffic together |
| 2 | `/routing/mixed-batch` | Each request is tagged with its policy and route reason |
| 3 | `mixed:counters` (redis) | The datastore's aggregate spread matches the API summary |
| 4 | `receipts` (psql) | Every request carries the full operator field set, quality included |
| 5 | `/routing/disposition` | API, Redis, and receipts reconcile per routing kind |
| 6 | `/routing/disposition` | The operator decision is CONFIRMED only when all three agree |

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
- Redis reachable (the mixed-batch counters in Step 3 live here)
- PostgreSQL reachable (the receipts in Step 4 live here)

For a clean state before you start — clears receipts **and** all routing counters:

```bash
./scripts/module1-demo-reset.sh
```

## Demo steps

### Step 1: Run the mixed routing batch

**Goal:** Send one batch of weighted, payload-based, and override-driven requests
through the same service and read the summary.

```bash
curl -s -X POST http://localhost:8000/route/mixed | python3 scripts/fmt.py --type mixed \
  --title "Run a mixed routing batch" \
  --why "Weighted, payload, and override requests through one service"
```

**Expected output:** ★ `total requests: 16`, then the breakdown by routing kind —
`weighted 10`, `payload 4`, `override 2` — and ★ `policies: payload_smart,
weighted`.

**What the learner should notice:** This is the whole routing layer working at
once, not one policy at a time. Sixteen requests: ten routed by the weighted
policy, four by payload complexity, two pinned by a deterministic override. Two
policy names appear because weighted and payload are different policies, and the
overrides ride on the payload policy. Everything that follows checks this one
batch three independent ways.

### Step 2: Inspect the individual mixed decisions

**Goal:** Look at individual requests and see each one tagged with its kind,
policy, model, and route reason.

```bash
curl -s "http://localhost:8000/routing/mixed-batch?limit=6" | python3 scripts/fmt.py --type mixed-samples \
  --title "Inspect the individual mixed decisions" \
  --why "Each request tagged with its kind, policy, model, and route reason"
```

**Expected output:** a table of ★ rows — each with request id, `kind`, `model`,
`tier`, and `route_reason` — showing `weighted` (`weighted_distribution`),
`payload` (`complexity_*`), and `override` (`override_*`) requests.

**What the learner should notice:** Every decision is self-describing. The `kind`
column tells you *which policy* handled the request, and the `route_reason` says
*why* — `weighted_distribution`, `complexity_complex`, `override_bulk_batch`.
Same service, same batch, three different routing paths, each one leaving a clear
trail. That trail is what makes the reconciliation possible.

### Step 3: Prove the aggregate spread in Redis

**Goal:** Read the per-kind counters straight from the Redis datastore and check
they match the batch summary from Step 1.

```bash
docker compose exec -T redis redis-cli --json HGETALL mixed:counters \
  | python3 scripts/fmt.py --type mixed-counters \
  --title "Aggregate routing kinds in Redis" \
  --why "The datastore's per-kind tally — reconciles against the batch summary"
```

**Expected output:** ★ `total: 16`, then `weighted 10`, `payload 4`, `override 2`
— the same numbers the API reported in Step 1.

**What the learner should notice:** These counts come straight from the Redis
hash `mixed:counters`, read with `HGETALL` — the datastore, not the API. They
match Step 1 exactly: ten, four, two. That is the first reconciliation — the
service's own summary and the independent datastore agree on how the mixed
traffic was routed.

### Step 4: Read the full per-request receipts in PostgreSQL

**Goal:** Query the receipts for the operator field set — the record an operator
actually investigates.

```bash
docker compose exec -T postgres psql -U genai -d genai -tAc "SELECT row_to_json(r) FROM (
  SELECT request_id, policy_name, provider_tier, latency_target_ms,
         total_tokens, cost_estimate_usd, quality_score
  FROM receipts ORDER BY created_at DESC LIMIT 6) r" \
  | python3 scripts/fmt.py --type mixed-receipts \
  --title "Full per-request receipts in PostgreSQL" \
  --why "The operator field set: id, policy, provider, latency, tokens, cost, quality"
```

**Expected output:** one ★ row per request with `request_id`, `policy_name`,
`provider_tier`, `latency` target, `tokens`, `cost`, and `quality` — different
policies and providers, each with its own cost and quality score.

**What the learner should notice:** This is the durable record behind the
counters, and it carries everything an operator needs months later: which policy
routed the request, which provider tier served it, its latency target, token
count, cost, and quality score — all keyed by request id. Cost and quality move
with the tier: the premium rows cost more and score higher. Nothing here is
provider-specific; every policy lands in the same columns.

### Step 5: Reconcile the three sources of truth

**Goal:** Line the three independent records — API summary, Redis counters, and
PostgreSQL receipts — up side by side, per routing kind.

```bash
curl -s http://localhost:8000/routing/disposition | python3 scripts/fmt.py --type disposition \
  --title "Reconcile the three sources of truth" \
  --why "API, Redis, and receipts must agree per routing kind"
```

**Expected output:** ★ `sources_agree: true`, then a per-kind row showing `api`,
`redis`, and `receipts` counts with a ✓ — `weighted 10/10/10`, `payload 4/4/4`,
`override 2/2/2`.

**What the learner should notice:** Three records that were written independently
— the API summary as the batch ran, the Redis counters incremented per decision,
and the PostgreSQL receipts persisted per request — and for every routing kind
they hold the same number. That is the proof that no request was miscounted,
dropped, or misrouted. If one column disagreed, its ✓ would be an ✗ and you would
know exactly which kind to investigate.

### Step 6: Confirm the final operator disposition

**Goal:** Read the single go/no-go verdict that an operator acts on.

```bash
curl -s http://localhost:8000/routing/disposition | python3 scripts/fmt.py --type disposition \
  --title "Confirm the final operator disposition" \
  --why "CONFIRMED only when API, Redis, and receipts agree and every policy is consistent"
```

**Expected output:** ★ `disposition: CONFIRMED`, ★ `sources_agree: true`, ★
`policies_consistent: true`.

**What the learner should notice:** This is the disposition — the operator's
single decision. It reads `CONFIRMED` only when two things hold: the three sources
agree on the counts (`sources_agree`), and every receipt's policy name is
consistent with its route reason (`policies_consistent`) — a weighted decision
carries the weighted policy, an override carries the payload policy. If either
check failed, the disposition would read `BLOCKED` and the operator would not sign
off. Reset and run the batch again and you get the same `CONFIRMED` — the whole
routing layer, validated end to end, repeatably.

## Preflight check

```bash
bash module1/scripts/clip6_preflight_check.sh
```

Runs every step above, asserts TO1 and EO1a–d, and writes a readable log to
`module1/clip6_preflight_log.txt`. Expect `PASS: 6  FAIL: 0`.

## Cleanup

```bash
./scripts/module1-demo-reset.sh
```

## Key files

- `app/main.py` — the `/route/mixed`, `/routing/mixed-batch`,
  `/routing/mixed-counters`, `/routing/disposition` endpoints
- `app/routing/weighted.py`, `app/routing/payload.py` — the policies the mixed
  batch composes
- `app/db/redis_client.py` — the `mixed:counters` hash (`HINCRBY` / `HGETALL`)
- `app/db/postgres.py` — `count_by_kind` and `inconsistent_receipts`, the receipt
  reconciliation queries
- `scripts/fmt.py` — the `mixed` / `mixed-samples` / `mixed-counters` /
  `mixed-receipts` / `disposition` views
