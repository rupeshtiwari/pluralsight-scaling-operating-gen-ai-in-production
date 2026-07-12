# Module 1 — Demo: Validate routing receipts, counters, and final disposition

## Why this matters

**The problem:** You have three routing policies now — baseline, weighted, and
payload-based with deterministic overrides. Each one proved itself in isolation.
But in production a single service runs *all* of them at once, and an operator has
to trust the whole thing. The API reports one decision; the live counters report
an aggregate; the database keeps a receipt for every call. What happens when those
records *disagree*? A routing bug, a dropped receipt, or a miscounted tier is
exactly the kind of silent drift you must catch before you sign off. How do you
confirm the routing is correct — not for one policy, but for the mixed traffic the
service actually sees?

**What you will see:** Five moments that turn three separate proofs into one
operator sign-off — a mixed batch of weighted, payload, and override requests
through one service; the individual decisions each tagged with its policy and
route reason; the aggregate spread in the Redis datastore; the durable per-request
receipts in PostgreSQL with the operator field set; and a reconciliation that
lines the three views up and reads **CONFIRMED** only when they agree.

**What you walk away with:** A repeatable way to validate the routing evidence for
a mixed batch at once — three operational views (the API result, the Redis
aggregate, and the durable PostgreSQL receipts) reconciled per routing kind, plus
a single **accept-or-investigate** disposition an operator can act on. Counts,
receipts, and policies must all agree, or the disposition blocks. (This confirms
internal consistency for the batch — not provider health under load, failure
recovery, or long-run distribution accuracy, which later modules cover.)

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
| 2 | `/routing/mixed-batch` | Each request is tagged with its kind, policy, model, and route reason |
| 3 | `mixed:counters` (redis) | The fast operational aggregate matches the batch |
| 4 | `receipts` (psql) | Every routing kind has a durable receipt with the full operator field set |
| 5 | `/routing/disposition` | The views reconcile and the operator decision reads CONFIRMED only when they agree |

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
policy, four by payload complexity, two pinned by a deterministic override. The
10 / 4 / 2 split is the **declared test population** — a controlled mix that lets
us exercise all three paths through one service. It is *not* a statistical claim
that weighted routing converges to a target over ten requests; that proof lives in
the weighted-routing clip. Here the batch exists so the next four steps can check
it three ways.

### Step 2: Inspect representative routing decisions

**Goal:** Look at individual requests and see each one tagged with its kind,
policy, model, and route reason — with all three kinds visible.

```bash
curl -s "http://localhost:8000/routing/mixed-batch?limit=6" | python3 scripts/fmt.py --type mixed-samples \
  --title "Inspect representative routing decisions" \
  --why "Each request tagged with its kind, policy, model, and route reason"
```

**Expected output:** a table of ★ rows spanning all three kinds — `weighted`
(policy `weighted`, reason `weighted_distribution`), `payload` (policy
`payload_smart`, reason `complexity_*`), and `override` (policy `payload_smart`,
reason `override_*`) — each with its `model` and `tier`.

**What the learner should notice:** Every decision is self-describing, and this
step proves *semantic* correctness, not just counts. The `kind` column tells you
which routing path handled the request; `policy` tells you which policy owns it
(weighted requests carry the `weighted` policy, payload and override requests
carry `payload_smart`); and `route_reason` says exactly why —
`weighted_distribution`, `complexity_complex`, `override_bulk_batch`. The
`override_bulk_batch` row lands on `econo-mini` on purpose: bulk work prioritizes
cost and throughput, so the override sends it to the economy tier — not because a
large payload always belongs on the cheapest model. Same service, one batch, three
paths, each leaving a clear trail. That trail is what makes the reconciliation in
Step 5 meaningful.

### Step 3: Verify the fast aggregate in Redis

**Goal:** Read the per-kind counters straight from the Redis datastore and check
they match the batch summary from Step 1.

```bash
docker compose exec -T redis redis-cli --json HGETALL mixed:counters \
  | python3 scripts/fmt.py --type mixed-counters \
  --title "Verify the fast aggregate in Redis" \
  --why "The datastore's per-kind tally — reconciles against the batch summary"
```

**Expected output:** ★ `total: 16`, then `weighted 10`, `payload 4`, `override 2`
— the same numbers the API reported in Step 1.

**What the learner should notice:** These counts come straight from the Redis hash
`mixed:counters`, read with `HGETALL` — the datastore, not the API. They match
Step 1 exactly. Redis is the **fast operational aggregate**: the right tool for
dashboards, rate and distribution monitoring, and quick health checks. It is *not*
the permanent audit ledger — Redis data can expire, be evicted, or be rebuilt — so
the durable record belongs in PostgreSQL, which is the next step.

### Step 4: Verify the durable receipts in PostgreSQL

**Goal:** Query the receipts across every routing kind for the operator field set —
the durable record an operator actually investigates.

```bash
docker compose exec -T postgres psql -U genai -d genai -tAc "SELECT row_to_json(r) FROM (
    (SELECT 'weighted' AS kind, policy_name,provider_tier,latency_target_ms,total_tokens,cost_estimate_usd,quality_score
       FROM receipts WHERE route_reason='weighted_distribution' LIMIT 2)
  UNION ALL
    (SELECT 'payload' AS kind, policy_name,provider_tier,latency_target_ms,total_tokens,cost_estimate_usd,quality_score
       FROM receipts WHERE route_reason LIKE 'complexity_%' LIMIT 2)
  UNION ALL
    (SELECT 'override' AS kind, policy_name,provider_tier,latency_target_ms,total_tokens,cost_estimate_usd,quality_score
       FROM receipts WHERE route_reason LIKE 'override_%' LIMIT 2)
  ) r" \
  | python3 scripts/fmt.py --type mixed-receipts \
  --title "Verify the durable receipts in PostgreSQL" \
  --why "Every routing kind has a durable receipt with the full operator field set"
```

**Expected output:** six ★ rows deliberately spanning every kind — the `kind`
column shows `weighted`, `payload`, and `override` — each with `policy_name`
(`weighted` or `payload_smart`), `provider_tier`, `latency target`, `tokens`,
`cost`, and `quality`.

**What the learner should notice:** This is the durable record behind the
counters. The `kind` column proves every routing path has a persisted receipt —
weighted, payload, *and* override — not just the aggregate count. Note that
override rows carry the `payload_smart` policy (an override is a deterministic
exception *within* payload routing), so the `kind` column, not policy alone, is
what proves the override path is durable. `latency target` is the tier's
*configured* target (400 / 700 / 1200 ms), not a measured request latency.
Likewise `quality` is the tier's *configured capability score* — provider
metadata, not a live judgment of this individual response. Cost and quality move
with the tier: premium rows cost more and carry a higher capability score.

### Step 5: Reconcile the evidence and confirm the disposition

**Goal:** Line the three views up per routing kind and read the single
accept-or-investigate verdict an operator acts on.

```bash
curl -s http://localhost:8000/routing/disposition | python3 scripts/fmt.py --type disposition \
  --title "Reconcile the evidence and confirm the disposition" \
  --why "CONFIRMED only when the views agree, every request has a receipt, and every policy fits its route reason"
```

**Expected output:** ★ `disposition: CONFIRMED`, ★ `counts_agree: true`, ★
`receipts_complete: true`, ★ `policies_consistent: true`, then a per-kind row
showing `api`, `redis`, and `receipts` counts with a ✓ — `weighted 10/10/10`,
`payload 4/4/4`, `override 2/2/2`.

**What the learner should notice:** This is the disposition — the operator's single
decision — and `CONFIRMED` has an explicit, machine-checkable contract. It reads
`CONFIRMED` only when **all** of these hold:

- **counts_agree** — the API summary, the Redis counters, and the PostgreSQL
  receipt counts are equal for every routing kind;
- **receipts_complete** — there is exactly one durable receipt per routed request,
  none missing and none extra;
- **policies_consistent** — every receipt's policy matches its route reason
  (`weighted_distribution` → the `weighted` policy; `complexity_*` and `override_*`
  → the `payload_smart` policy), so an override is never miscounted as a weighted
  selection.

If any check failed, the disposition would read `BLOCKED` and the ✗ would point at
the routing kind to investigate. Reset and run the batch again and you get the same
`CONFIRMED` — the mixed routing run, validated end to end for this batch,
repeatably.

## Preflight check

```bash
bash module1/scripts/clip6_preflight_check.sh
```

Runs every step above, asserts TO1 and EO1a–d, and writes a readable log to
`module1/clip6_preflight_log.txt`. Expect `PASS: 5  FAIL: 0`.

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
