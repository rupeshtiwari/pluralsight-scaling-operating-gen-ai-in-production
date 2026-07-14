# Module 2 — Demo: Prove queues, rate limits, and fail-fast behavior

## Why this matters

**The problem:** Your routing layer works, but production traffic does not arrive
in a tidy stream — it arrives in **spikes**. When a burst hits, one of three
things has to happen to every request: serve it now, hold it briefly, or turn it
away. If you serve everything, you exhaust the model provider's quota and take the
whole service down with it. If you turn everything away, you drop work you could
have absorbed. The job is to admit what you can serve, queue what you can hold,
and **fail fast** on the rest with a clean error — and to be able to *prove*, per
request, which of the three happened. How do you show that under load your service
absorbs the burst, respects a configured limit, and sheds the overflow instead of
falling over?

**What you will see:** Six moments that turn "we handle load" into "we handle load
by a policy we can prove" — a controlled traffic spike against one tier; the queue
backlog rising in Redis; the rate-limit window sitting exactly at its threshold;
the same burst shedding at a different point on every tier because each provider
and class has its own limit; a single request that overflows the full queue and
comes back as a clean HTTP 429; and the durable receipts that let you tell every
accepted, delayed, and rejected request apart.

**What you walk away with:** A resilient front door for the AI service — a request
queue with a configurable rate limit that absorbs spikes without exhausting a
provider (EO2a), and a fail-fast path that rejects at capacity with a proper error
response (EO2b), both simulated in a controlled, repeatable environment (EO2e).
Every request's fate is measured live in Redis and recorded durably in PostgreSQL.
(This proves admission control under a burst — not automatic failover between
models, retry backoff, or long-run distribution behaviour.)

## Learning objectives covered

| LO | Description |
|----|-------------|
| TO2 | Build resilient GenAI integrations using queuing, rate limiting, and automatic fallback mechanisms |
| EO2a | Implement a request queue with configurable rate limits that absorbs traffic spikes and prevents downstream provider quota exhaustion |
| EO2b | Design a fail-fast pattern that rejects requests when queue capacity is exceeded, returning appropriate error responses to callers |
| EO2e | Test system resilience by simulating model failures, latency spikes, and quota exhaustion in a controlled environment |

## What this demo proves — and each step is unique

| Step | Endpoint | What it teaches (nothing repeats) |
|------|----------|-----------------------------------|
| 1 | `/load/spike` | One burst is split three ways: admitted now, queued, or shed |
| 2 | `resilience:queue` (redis) | The backlog is real — read the queue depth straight from the datastore |
| 3 | `resilience:ratelimit` (redis) | The admitted count sits exactly at the configured threshold |
| 4 | `/resilience/matrix` | The limit is per provider / tier / class — each sheds at a different point |
| 5 | `/load/submit` | One request over a full queue fails fast with HTTP 429 |
| 6 | `receipts` (psql) | Every accepted, delayed, and rejected request is a distinguishable receipt |

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
- Redis reachable (the queue depth and rate-limit window in Steps 2–3 live here)
- PostgreSQL reachable (every accepted, delayed, and rejected request persists a receipt for Step 6)

For a clean, repeatable run, reset **before** you start — this clears receipts
**and** the resilience state, so the spike starts from zero:

```bash
./scripts/module2-demo-reset.sh
```

## Demo steps

### Step 1: Run a controlled traffic spike

**Goal:** Send a fixed burst of requests at one tier and read how the service
split them across admit-now, queue, and shed.

```bash
curl -s -X POST http://localhost:8000/load/spike \
  -H "Content-Type: application/json" -d '{"model": "balanced-std", "count": 20}' \
  | python3 scripts/fmt.py --type spike \
  --title "Run a controlled traffic spike" \
  --why "A burst hits one tier — absorb what fits the rate limit, queue what fits the backlog, shed the rest"
```

**Expected output:** ★ `submitted requests: 20`, then the three outcomes —
★ `accepted: 6` (within the rate limit), ★ `delayed: 10` (queued), ★ `rejected: 4`
(shed) — and ★ `queue peak: 10 / 10 FULL`, ★ `rate limit: 6`.

**What the learner should notice:** One burst, three fates. The `balanced-std`
tier is configured with a **rate limit of 6** (how many it admits immediately) and
a **queue capacity of 10** (how many it can hold). Twenty requests arrive: the
first 6 are **accepted** and served now, the next 10 are **delayed** — parked in
the queue to be served as capacity frees — and the final 4 are **rejected**,
because the queue is already full. That is admission control doing its job: the
queue *absorbed* a spike more than triple the immediate limit instead of hammering
the provider with all twenty at once. The split is **deterministic** — a clean
burst of 20 against 6 + 10 always lands 6 / 10 / 4 — which is what makes it
testable in CI and repeatable on every run. A production limiter is usually
*probabilistic* under real concurrency; here we fix the arrival order so the proof
is exact.

### Step 2: Read the queue backlog straight from Redis

**Goal:** Query the queue depth directly from the Redis datastore — not through
the application — and confirm the backlog rose above zero under load.

```bash
docker compose exec -T redis redis-cli --json HGETALL resilience:queue \
  | python3 scripts/fmt.py --type queue \
  --title "Read the queue backlog straight from Redis" \
  --why "The datastore's live queue depth — proof the backlog rose above zero under load"
```

**Expected output:** ★ one row for `balanced-std` — `depth 10`, `peak 10`,
`capacity 10`, state `FULL`.

**What the learner should notice:** This is `HGETALL` against the Redis hash
`resilience:queue` — the datastore itself, with the application out of the
picture. The **depth of 10** is the backlog the spike left waiting, and because it
equals the **capacity of 10**, the queue is `FULL`. This is the running scoreboard
an operator watches live: depth climbing toward capacity is the early warning that
the service is about to start shedding. Redis is the right tool for this — a fast,
in-memory gauge — which is exactly why the next request over the line (Step 5) is
rejected without ceremony. It is *not* the durable audit record; that lives in
PostgreSQL (Step 6).

### Step 3: Compare the rate-limit count against its threshold

**Goal:** Read the rate-limit window from Redis and see the admitted count sitting
at the configured limit — the boundary between "serve now" and "queue".

```bash
docker compose exec -T redis redis-cli --json HGETALL resilience:ratelimit \
  | python3 scripts/fmt.py --type ratelimit \
  --title "Compare the rate-limit count against its threshold" \
  --why "The admitted count vs the configured limit — the window that decides accept-now or queue"
```

**Expected output:** ★ one row for `balanced-std` — `admitted 6`, `limit 6`,
state `AT LIMIT`.

**What the learner should notice:** The rate limit is the *first* gate, separate
from the queue. The window admitted exactly **6**, which is the configured
**limit of 6**, so it reads `AT LIMIT`. That is why requests 7 through 16 went to
the queue rather than straight through: the immediate-admit budget was already
spent. Rate limit and queue capacity are two independent knobs — the rate limit
caps how fast you hand work to the provider (protecting its quota), and the queue
capacity caps how much you're willing to hold before shedding. An operator tunes
them separately: raise the rate limit to push the provider harder, raise the queue
to absorb bigger spikes at the cost of added latency.

### Step 4: Trigger rate-limit decisions by provider, tier, and class

**Goal:** Send the *same* burst size at every tier and watch each one shed at a
different point, because each provider and request class has its own configured
limit.

```bash
curl -s "http://localhost:8000/resilience/matrix?count=20" | python3 scripts/fmt.py --type matrix \
  --title "Trigger rate-limit decisions by provider, tier, and class" \
  --why "The same burst against every tier — each provider and class has its own limit, so each sheds at a different point"
```

**Expected output:** ★ `burst size: 20`, then a row per tier — `econo-mini`
(class `bulk`, 10 / 20) accepts 10, delays 10, rejects 0; `balanced-std` (class
`interactive`, 6 / 10) accepts 6, delays 10, rejects 4; `premium-max` (class
`critical`, 3 / 4) accepts 3, delays 4, rejects 13.

**What the learner should notice:** The rate limit is not one global number — it is
configured **per provider, tier, and request class**, and this matrix proves it.
The identical 20-request burst lands three different ways: the shared `econo-mini`
tier has generous limits and absorbs it whole (nothing shed); the dedicated
`balanced-std` tier sheds a few; the reserved `premium-max` tier — deliberately
tight because its provider quota is scarce and expensive — sheds most of them.
That is intentional: you protect a costly reserved provider by admitting only what
it's provisioned for and shedding the rest early, while letting the cheap shared
tier soak up bulk traffic. Same policy, three configurations, three outcomes.

### Step 5: Exceed the queue and prove the fail-fast 429

**Goal:** With the queue already full from Step 1, submit one more request and show
the caller gets a clean HTTP 429 — plus a durable rejected receipt.

```bash
curl -s -X POST http://localhost:8000/load/submit \
  -H "Content-Type: application/json" -d '{"model": "balanced-std"}' \
  -w '\n{"http_status": %{http_code}}' \
  | python3 scripts/fmt.py --type failfast \
  --title "Exceed the queue and prove the fail-fast 429" \
  --why "With the queue full, one more request is rejected fast — a clean HTTP 429 and a durable rejected receipt"
```

**Expected output:** ★ `http status: 429` (Too Many Requests), ★ `admitted:
false`, ★ `disposition: rejected`, ★ `reason: Queue capacity exceeded`, ★ `queue:
10 / 10`, a ★ `request_id`, and ★ `receipt_persisted: true`.

**What the learner should notice:** This is the fail-fast contract from the
**caller's** side. The queue is full (Step 2 left it at 10 / 10), so this request
is not silently dropped and it does not hang waiting — it comes back immediately
with **HTTP 429** and a machine-readable reason, `Queue capacity exceeded`. That
status code matters: it tells a well-behaved client to back off and retry later
rather than retry instantly and make the pileup worse. And crucially, the reject is
**not invisible** — `receipt_persisted: true` means a durable receipt was written,
so a shed request is auditable after the fact. Fail-fast is a feature, not a
failure: refusing work you can't serve is how you keep the work you *can* serve
fast.

### Step 6: Distinguish every request's fate in the receipts

**Goal:** Query PostgreSQL receipts grouped by disposition and confirm every
accepted, delayed, and rejected request is a distinct, durable record.

```bash
curl -s http://localhost:8000/resilience/dispositions | python3 scripts/fmt.py --type dispositions \
  --title "Distinguish every request's fate in the receipts" \
  --why "Straight from PostgreSQL: accepted, delayed, and rejected — each a durable, distinguishable record"
```

**Expected output:** ★ `total requests: 21`, then the tally — ★ `accepted: 6`,
★ `delayed: 10`, ★ `rejected: 5` — and a few sample receipts whose `disposition`,
`tokens`, and `cost` columns show served requests carrying real tokens and cost
while rejected ones show `0` and `$0.000000`.

**What the learner should notice:** This is the durable, provider-agnostic record
behind the live counters — and it is where accepted, delayed, and rejected stop
being a live gauge and become an auditable ledger. The total is **21**: the 20 from
the spike plus the one you failed fast in Step 5, which is why `rejected` reads
**5** (4 + 1). Look at the sample rows: an **accepted** or **delayed** request
carries a real token estimate and cost, because it was (or will be) served; a
**rejected** request shows `0` tokens and `$0.000000` cost, because a shed request
consumes nothing. That single distinction — served work costs, shed work doesn't —
is what lets an operator answer, months later, exactly how much traffic the service
turned away and what it saved by doing so, straight from PostgreSQL.

## Preflight check

```bash
bash module2/scripts/clip2_preflight_check.sh
```

Runs every step above, captures each command and its output, maps each step to
TO2 and EO2a/b/e, and writes a readable log to `module2/clip2_preflight_log.txt`.
Expect `PASS: 6  FAIL: 0`.

## Cleanup

```bash
./scripts/module2-demo-reset.sh
```

## Key files

- `app/main.py` — the `/load/spike`, `/resilience/queue`,
  `/resilience/rate-limit`, `/resilience/matrix`, `/load/submit`, and
  `/resilience/dispositions` endpoints
- `app/providers/registry.py` — the per-tier `RATE_LIMITS` (rate limit + queue
  capacity + request class) and the deterministic `classify_arrival` decision
- `app/resilience/admission.py` — the pure admission logic and the spike runner
- `app/db/redis_client.py` — the `resilience:queue`, `resilience:ratelimit`, and
  `resilience:dispositions` hashes (read directly in Steps 2–3 via `HGETALL`)
- `app/db/postgres.py` — the disposition-tagged receipts and `count_by_disposition`
- `scripts/fmt.py` — the `spike` / `queue` / `ratelimit` / `matrix` / `failfast` /
  `dispositions` views
