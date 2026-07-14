# Module 2 — Demo: Prove queues, rate limits, and fail-fast behavior

## Why this matters

**The problem:** Production traffic does not arrive in a tidy stream — it arrives
in **spikes**. When a burst hits, one of three things has to happen to every
request: serve it now, hold it briefly, or turn it away. Serve everything and you
exhaust the model provider's quota and take the whole service down. Turn everything
away and you drop work you could have absorbed. The job is to admit what you can
serve, queue what you can hold, and **fail fast** on the rest with a clean error —
correctly, even when hundreds of requests arrive at the same instant and race each
other. How do you prove, under real concurrent load, that the service absorbs the
burst, respects its limits, and sheds the overflow instead of falling over?

**What you will see:** Seven moments that turn "we handle load" into "we handle load
provably, under real traffic" — a live **k6** spike and its HTTP outcome
distribution; the actual queued request IDs in Redis; the rate-limit window sitting
at its threshold; the same burst shedding at a different point on every provider key;
one request that overflows the full queue and comes back as a clean HTTP 429 with a
`Retry-After`; the durable receipts that tell every disposition apart; and a single
request ID correlated across the structured log and the PostgreSQL receipt.

**What you walk away with:** A resilient front door for the AI service — a request
queue with a configurable rate limit that absorbs spikes without exhausting a
provider (EO2a), and a fail-fast path that rejects at capacity with a proper error
response (EO2b), both driven by real k6 load in a controlled environment. Clip 2
contributes the controlled-load and overload half of resilience testing (EO2e);
model failures, latency spikes, and quota exhaustion are separate scenarios.

## Learning objectives covered

| Step | LO sub-element | What proves it |
|------|----------------|----------------|
| 1 | TO2, EO2a, EO2e | Real concurrent k6 load is admitted, queued, or shed with no failures |
| 2 | EO2a | The queue holds actual request IDs — real parked work, not a counter |
| 3 | EO2a | The rate limit caps immediate admits per window and gates the queue |
| 4 | EO2a | Limits are keyed per provider, tier, and request class — each sheds differently |
| 5 | EO2b | A full queue rejects with HTTP 429, `Retry-After`, and a durable receipt |
| 6 | EO2b | Accepted, delayed, and rejected are distinguishable durable receipts |
| 7 | EO2b, EO2e | One request ID reconciles across the structured log and the receipt |

## What this demo proves — and each step is unique

| Step | Command | What it teaches (nothing repeats) |
|------|---------|-----------------------------------|
| 1 | `k6 run clip2_spike.js` | Real concurrent traffic splits into 200s and 429s with zero failures |
| 2 | `LRANGE resilience:queue:*` | The backlog is a real list of queued request IDs |
| 3 | `/resilience/rate-limit` | The admitted count sits at the limit, with its window duration |
| 4 | `/resilience/matrix` | The limit is per provider / tier / class — each sheds at its own point |
| 5 | `/load/submit` | One request over a full queue fails fast with 429 + `Retry-After` |
| 6 | `/resilience/dispositions` | Every disposition is a distinct receipt; rejected cost is zero |
| 7 | `/resilience/admission-logs` | One request ID ties the log and the receipt together |

## Prerequisites

### Software this clip needs — do you have it?

This clip uses **Docker Desktop** (with Compose), **k6**, **curl**, **jq**,
**python3**, **psql**, and **tmux**. Two commands cover every case:

```bash
bash scripts/ensure-ready.sh       # CHECK  — ✔ / ✗ for each tool, with a fix for anything missing
bash environment-setup/setup.sh    # INSTALL — one step: installs everything the course uses, then the pinned deps
```

- **First time on this Mac?** Run the install step once. It installs Homebrew,
  Docker Desktop, Python 3.13, tmux, jq, curl, psql, and **k6** — then builds the
  Python environment. When it prints `READY`, you have everything this clip needs.
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
- Redis reachable (the queue list, rate-limit counter, and logs live here)
- PostgreSQL reachable (every accepted, delayed, and rejected request persists a receipt)

For a clean, repeatable run, reset **before** the spike — this clears receipts,
the queue, the rate-limit counter, and the logs, so the spike starts from zero:

```bash
./scripts/module2-demo-reset.sh
```

## Demo steps

### Step 1: Run the k6 spike and read the HTTP outcomes

**Goal:** Drive 20 concurrent requests at the service with k6 and read the HTTP
status distribution — proof the burst produced mixed outcomes with no failures.

```bash
API_BASE=http://localhost:8000 k6 run --quiet module2/k6/clip2_spike.js
python3 scripts/fmt.py --type k6-summary < module2/k6/last_summary.json \
  --title "Run the k6 spike and read the HTTP outcomes" \
  --why "Real concurrent k6 traffic against the service — the HTTP status distribution proves mixed outcomes with no failures"
```

**Expected output:** ★ `requests submitted: 20`, then the HTTP outcomes —
★ `HTTP 200: 16`, ★ `HTTP 429: 4`, ★ `HTTP 500: 0`, ★ `connection failures: 0` —
and the admission split ★ `accepted: 6`, ★ `delayed: 10`, ★ `rejected: 4`.

**What the learner should notice:** This is real traffic, not a calculation. k6
fired twenty requests concurrently across ten virtual users, and they *raced* each
other into the same service. The service admitted exactly **6**, queued **10**, and
rejected **4** — and it did so atomically, so no two racing requests both slipped
past a full queue. The HTTP view is the proof a caller cares about: **16** got
`HTTP 200` (admitted or queued), **4** got `HTTP 429` (rejected at capacity), and
critically there were **zero** `HTTP 500`s and **zero** connection failures. The
service stayed responsive and correct under contention — it shed load on purpose,
it did not fall over. The split is repeatable because admission is decided by one
atomic Redis step keyed on capacity, not by timing.

### Step 2: Inspect the real queue in Redis

**Goal:** Read the actual queued request IDs directly from the Redis list — proof
the backlog is real parked work, not just a depth number.

```bash
docker compose exec -T redis redis-cli --json LRANGE resilience:queue:balanced-std 0 -1 \
  | python3 scripts/fmt.py --type queue-list \
  --title "Inspect the real queue in Redis" \
  --why "The actual list of queued request IDs — real parked work, not just a depth counter"
```

> The demo also exposes this as `GET /resilience/queue` (used by the preflight),
> which returns the same request IDs plus the depth against capacity.

**Expected output:** ★ `depth: 10 / 10 FULL`, then ten ★ lines, each a real queued
`request_id` (`req-…`).

**What the learner should notice:** The queue is a **real Redis LIST**, and here are
its contents — ten actual request IDs, parked and waiting for capacity to free up.
This matters: a depth counter can be faked, but a list of IDs is the real work
itself, each one dequeuable and traceable to its receipt. The depth is `10` against
a capacity of `10`, so the queue is `FULL` — which is exactly why the next request
over the line will be rejected. This is the running backlog an operator watches:
when depth climbs toward capacity, the service is about to start shedding.

### Step 3: Compare the rate-limit count against its threshold

**Goal:** Read the rate-limit window and see the admitted count at the configured
limit — with the window duration that makes the limit meaningful.

```bash
curl -s http://localhost:8000/resilience/rate-limit | python3 scripts/fmt.py --type ratelimit \
  --title "Compare the rate-limit count against its threshold" \
  --why "The admitted count vs the configured limit and window — the gate that decides accept-now or queue"
```

**Expected output:** ★ `limiter key: balanced-ai:balanced:interactive`,
★ `admitted: 6 / 6 AT LIMIT`, ★ `window: 6 requests per 10s`.

**What the learner should notice:** The rate limit is the *first* gate, separate
from the queue. The window admitted exactly **6**, which is the configured limit, so
it reads `AT LIMIT` — that is why the seventh request onward went to the queue rather
than straight through. And a limit is only meaningful with its **window**: `6 per
10s` is a throughput budget you can reason about and reproduce, where a bare `6`
cannot be. The `limiter key` — `balanced-ai:balanced:interactive` — is the exact
composite the limiter buckets on, which the next step compares across providers.

### Step 4: Compare policies by provider, tier, and request class

**Goal:** Send the *same* burst size at every provider key and watch each shed at a
different point, because each has its own configured limit.

```bash
curl -s "http://localhost:8000/resilience/matrix?count=20" | python3 scripts/fmt.py --type matrix \
  --title "Compare policies by provider, tier, and request class" \
  --why "The same burst against every provider key — each has its own limit, so each sheds at a different point"
```

**Expected output:** ★ `burst size: 20`, then a row per key — `econo-ai` (low_cost,
batch, 10/20) accepts 10 / delays 10 / rejects 0; `balanced-ai` (balanced,
interactive, 6/10) accepts 6 / delays 10 / rejects 4; `premium-ai` (premium,
premium, 3/4) accepts 3 / delays 4 / rejects 13.

**What the learner should notice:** The rate limit is not one global number — it is
keyed **per provider, tier, and request class**, and this matrix proves it by
showing the provider identity, not just the model. The identical 20-request burst
lands three different ways because each provider key has its own budget: the shared
`econo-ai` provider has generous limits and absorbs the burst whole; the dedicated
`balanced-ai` provider sheds a few; the reserved `premium-ai` provider sheds most.
That last one is deliberate, not a bug — a reserved provider's capacity is scarce
and expensive, so it is **intentionally bounded** to a small budget. You protect a
reserved reservation by admitting only what it is provisioned for and shedding a
bulk spike early, rather than letting one burst exhaust the quota everyone else
depends on. Same policy, three keys, three outcomes.

### Step 5: Exceed the queue and prove the fail-fast 429

**Goal:** With the queue full from Step 1, submit one more request and show the
caller gets a clean HTTP 429 with a `Retry-After` — plus a durable rejected receipt.

```bash
curl -s -X POST http://localhost:8000/load/submit \
  -H "Content-Type: application/json" -d '{"model": "balanced-std"}' \
  -w '\n{"http_status": %{http_code}}' \
  | python3 scripts/fmt.py --type failfast \
  --title "Exceed the queue and prove the fail-fast 429" \
  --why "With the queue full, one more request is rejected fast — a clean HTTP 429 with Retry-After and a durable rejected receipt"
```

**Expected output:** ★ `http status: 429`, ★ `admitted: false`, ★ `disposition:
rejected`, ★ `reason: Queue capacity exceeded`, ★ `queue: 10 / 10`, ★ `retry_after:
10s`, a ★ `request_id`, and ★ `receipt_persisted: true`.

**What the learner should notice:** This is the fail-fast contract from the
**caller's** side. The queue is full, so this request is not silently dropped and it
does not hang — it returns immediately with **HTTP 429** and a machine-readable
reason. Crucially, it also returns **`Retry-After: 10`**, telling a well-behaved
client exactly when to try again rather than retrying instantly and making the
pileup worse. And the reject is **not invisible** — `receipt_persisted: true` means a
durable receipt was written, so a shed request is auditable. Refusing work you
cannot serve, quickly and politely, is how you keep the work you *can* serve fast.

### Step 6: Distinguish every request's fate in the receipts

**Goal:** Query PostgreSQL receipts grouped by disposition and confirm every
accepted, delayed, and rejected request is a distinct, durable record.

```bash
curl -s http://localhost:8000/resilience/dispositions | python3 scripts/fmt.py --type dispositions \
  --title "Distinguish every request's fate in the receipts" \
  --why "Straight from PostgreSQL: accepted, delayed, and rejected — each a durable, distinguishable record"
```

**Expected output:** ★ `total requests: 21`, then ★ `accepted: 6`, ★ `delayed: 10`,
★ `rejected: 5`, and sample receipts whose `est tokens` and `est cost` columns show
served requests carrying an estimate while rejected ones show `0` and `$0.000000`.

**What the learner should notice:** This is the durable ledger behind the live
counters. The total is **21** — the 20 from the spike plus the one you failed fast in
Step 5, which is why `rejected` reads **5**. Read the columns carefully: they are
labelled **`est tokens`** and **`est cost`** on purpose. An accepted or delayed
request carries an *estimate* for capacity planning; the **actual** provider cost is
still zero until the request executes, because a queued request may yet expire, be
cancelled, or be rerouted. A **rejected** request shows `0` estimate because it never
reaches the model at all. That distinction — estimate versus incurred, and served
versus shed — is what lets an operator account for cost and traffic honestly.

### Step 7: Correlate one request across logs and receipts

**Goal:** Inspect the structured admission logs, one per disposition, and correlate a
single request ID across the log stream and the PostgreSQL receipt.

```bash
docker compose logs api --since 5m --no-log-prefix \
  | grep '"event":"admission_decision"' | tail -n 200 > /tmp/admission.log
curl -s http://localhost:8000/resilience/admission-logs | python3 scripts/fmt.py --type admission-logs \
  --title "Correlate one request across logs and receipts" \
  --why "Structured admission logs distinguish every disposition, and one request ID ties the caller, the log, and the receipt together"
```

**Expected output:** one structured log per disposition (`accepted`, `delayed`,
`rejected`, each with request ID, queue depth, rate-limit count, HTTP status, and
reason), then the correlation — ★ `request_id`, ★ `in structured log: true`,
★ `in PostgreSQL receipt: true`, ★ `dispositions match: true`.

**What the learner should notice:** Receipts prove *what* happened; structured logs
prove it *as it happened*, in the operator's live stream. Each log line is a complete
admission decision — the request ID, which provider key it hit, the queue depth and
rate-limit count at that instant, the disposition, and the HTTP status — so you can
tell an accepted, delayed, and rejected request apart at a glance. The payoff is the
correlation: take one rejected request ID and it appears in **three** places — the
caller's 429 response, the structured log, and the durable PostgreSQL receipt — all
agreeing on the same outcome. That three-way trace is what turns "the request was
rejected" into production-grade evidence an operator can stand behind in an incident
review.

## Preflight check

```bash
bash module2/scripts/clip2_preflight_check.sh
```

Runs every step above, captures each command and its output, maps each step to TO2
and EO2a/b/e, and writes a readable log to `module2/clip2_preflight_log.txt`. It runs
the real k6 spike when k6 is installed and otherwise drives the same atomic path with
a concurrent-`curl` burst, so the validated outcome matches the live demo. Expect
`PASS: 7  FAIL: 0`.

## Cleanup

```bash
./scripts/module2-demo-reset.sh
```

## Key files

- `app/main.py` — the `/load/submit`, `/load/spike`, `/resilience/queue`,
  `/resilience/rate-limit`, `/resilience/matrix`, `/resilience/dispositions`, and
  `/resilience/admission-logs` endpoints
- `app/providers/registry.py` — the per-provider `RATE_LIMITS`, the window, and the
  `limiter_key`
- `app/resilience/admission.py` — the admission logic, structured logging, and spike runner
- `app/db/redis_client.py` — the atomic admission Lua script, the queue LIST, and the log LIST
- `app/db/postgres.py` — the disposition-tagged receipts and `count_by_disposition`
- `module2/k6/clip2_spike.js` — the k6 spike that drives the demo
- `scripts/fmt.py` — the `k6-summary` / `queue` / `ratelimit` / `matrix` / `failfast`
  / `dispositions` / `admission-logs` views
