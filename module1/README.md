# Module 1 — Clip 2: Demo: Build the FastAPI provider adapter layer (6 minutes)

## Why this matters

**The problem:** Your team wants to add a second and third model to a GenAI
feature — cheaper for easy work, premium for hard work, a fallback when one is
down. But the prototype calls a provider SDK **directly** from application code.
The day you add a model, absorb an outage, or split traffic by cost, every
caller has to change, and there is no single place to see *which* model served a
request or *what* it cost. How do you put a whole fleet of models behind your
application without coupling your code to any one of them?

**What you will see:** Six distinct moments in the AI service layer — the stack
coming up healthy, the uniform adapter contract across three model tiers, a
deterministic provider simulation with zero external calls, the repeatable
condition matrix, one baseline routing decision, and the normalized receipt in
PostgreSQL. Each step shows a different surface of the boundary, so by the end
you can point to exactly where the decoupling lives.

**What you walk away with:** A dedicated AI service layer that decouples
application logic from every model provider and can scale on its own (EO1a), and
the routing foundation — one decision, one receipt — that intelligent routing is
built on (TO1). This clip builds that foundation; weighted and payload-based
routing are proven later on this same adapter boundary.

## Learning objectives covered

| LO | Description |
|----|-------------|
| TO1 | Implement load balancing and intelligent request routing for multi-model GenAI service architectures |
| EO1a | Design a dedicated AI service layer that decouples application logic from model provider dependencies and enables independent scaling |

## What this demo proves — and each step is unique

| Step | Endpoint | What it teaches (nothing repeats) | LO |
|------|----------|-----------------------------------|-----|
| 1 | `/health` | The dedicated service and every dependency are live before any request is routed | EO1a |
| 2 | `/providers` | One uniform adapter contract spans three model tiers — identical fields, different economics | TO1, EO1a |
| 3 | `/providers/{model}/probe` | Provider behavior is a deterministic local simulation — zero external API calls | EO1a |
| 4 | `/providers/conditions` | Six named conditions make healthy/slow/error/quota/quality/deprecation repeatable | EO1a |
| 5 | `/route` | One baseline decision returns selected model, token estimate, cost, and status | TO1 |
| 6 | `receipts` (psql) | The decision persists in a normalized, provider-agnostic receipt | TO1, EO1a |

## Prerequisites

**Start the stack first.** This runs the environment readiness check
(`scripts/ensure-ready.sh`) — which **auto-starts Docker Desktop** if it's
installed but not open — then brings up FastAPI, Redis, and PostgreSQL and waits
until healthy:

```bash
bash module1/scripts/demo_up.sh
```

Wait for `✔ stack healthy`. It then leaves you with a clean, reset stack.

Confirm the layers are up (Step 1 shows this on screen too):

- Server running: `curl -s http://localhost:8000/health | python3 -m json.tool`
- Redis reachable (live provider conditions)
- PostgreSQL reachable (the `backend: postgres` receipt proof in Step 6)

To return to a clean state at any time while the stack is up:

```bash
./scripts/module1-demo-reset.sh
```

## Demo steps

### Step 1: Bring the stack up and prove every layer is healthy (LO EO1a)

**Goal:** Make the service boundary concrete — the dedicated AI service and each
dependency it owns are live before a single request is routed.

```bash
curl -s http://localhost:8000/health | python3 scripts/fmt.py --type health \
  --title "Bring the stack up and prove every layer is healthy (LO EO1a)" \
  --why "Every layer of the dedicated AI service must be live before we route"
```

**Expected output:** `status: healthy`, then four ★ components — `fastapi`,
`redis`, `postgres`, `provider_stubs` — each `healthy`.

**What the learner should notice:** This is the dedicated service layer, not the
application and not a provider SDK. It owns three dependencies: Redis for live
provider conditions, PostgreSQL for durable receipts, and the in-process
provider stubs. All four report healthy, so every guarantee the rest of the demo
makes has a live foundation. Nothing here reaches out to a paid model — the
whole boundary runs locally.

### Step 2: Inspect the uniform adapter contract across three tiers (LO TO1, EO1a)

**Goal:** Show the decoupling boundary itself — one identical shape describing
three different model tiers.

```bash
curl -s http://localhost:8000/providers | python3 scripts/fmt.py --type providers \
  --title "Inspect the uniform adapter contract across three tiers (LO TO1, EO1a)" \
  --why "The decoupling boundary: identical fields across every model"
```

**Expected output:** a one-screen table — `default_model: balanced-std` above
one ★ row per adapter (`econo-mini`, `balanced-std`, `premium-max`) with the
columns `model`, `tier`, `latency`, `quota`, `cost/1k`, `quality`, `status`.
Every column is identical across the rows; only the numbers differ.

```
  ★ default_model: balanced-std

    model         tier      latency  quota      cost/1k  quality  status

  ★ econo-mini    low_cost  400ms    shared     $0.05    0.82     healthy

  ★ balanced-std  balanced  700ms    dedicated  $0.30    0.90     healthy

  ★ premium-max   premium   1200ms   reserved   $1.20    0.97     healthy
```

**What the learner should notice:** Every model exposes the **same fields** —
`tier`, `latency_target_ms`, `quota_mode`, `cost_per_1k_usd`, `quality_score`,
`status`. The tiers differ in their numbers (a low-cost tier versus a premium
one), but application code reads the identical contract no matter which provider
is behind it. That is the adapter boundary: adding a fourth model adds a row
here and touches no caller. This uniform set of tiers is the foundation the
later routing clips distribute traffic across.

### Step 3: Prove the adapter is a deterministic local simulation (LO EO1a)

**Goal:** Prove the provider is simulated deterministically — the same input
always produces the same result, with no external API call.

```bash
curl -s http://localhost:8000/providers/balanced-std/probe | python3 scripts/fmt.py --type probe \
  --title "Prove the adapter is a deterministic local simulation (LO EO1a)" \
  --why "Zero external calls — same input, same result, every run"
```

**Expected output:** ★ `model`, `condition`, `status`, `simulated_latency_ms`,
and the two proof fields ★ `external_api_calls: 0` and ★ `deterministic: true`.

**What the learner should notice:** Probing the balanced tier returns a fixed,
reproducible result — and `external_api_calls` is zero. Run it again and the
output is byte-for-byte identical. No network, no API key, no cost, no rate
limit. That determinism is what lets this entire course run in CI and on your
laptop while still exercising real routing, fallback, and readiness logic. The
provider is a simulation, but the service layer around it is the real thing.

### Step 4: Show the repeatable provider condition matrix (LO EO1a)

**Goal:** Show every simulated condition on screen so failure scenarios are
reproducible on demand rather than waiting for a real outage.

```bash
curl -s http://localhost:8000/providers/conditions | python3 scripts/fmt.py --type conditions \
  --title "Show the repeatable provider condition matrix (LO EO1a)" \
  --why "Six named conditions make every scenario repeatable"
```

**Expected output:** an active condition per model (all ★ `healthy`), then the
six ★ supported conditions — `healthy`, `slow`, `error`, `quota`, `quality`,
`deprecation` — each with its meaning.

**What the learner should notice:** Every model starts `healthy`. Below that are
the six conditions this system can simulate on command: a slow provider, a hard
error, an exhausted quota, degraded output quality, a deprecated model. Because
each one is named and switchable, the failure demos later in the course are
**repeatable** — you reproduce a quota exhaustion the same way every time,
instead of hoping a provider misbehaves on camera. This matrix is the control
panel for the whole reliability story.

### Step 5: Send a baseline request through the boundary (LO TO1)

**Goal:** Trigger one routing decision and read the normalized response the
caller receives.

```bash
curl -s -X POST http://localhost:8000/route \
  -H "Content-Type: application/json" \
  -d @data/payloads/baseline_request.json | python3 scripts/fmt.py --type route \
  --title "Send a baseline request through the boundary (LO TO1)" \
  --why "One normalized decision the caller can trust"
```

**Expected output:** ★ `selected_model: balanced-std`, ★ `provider_tier`,
★ `provider_status: healthy`, ★ `token_estimate: prompt=17 completion=10
total=27`, ★ `cost_estimate_usd: $0.008100`, ★ `latency_target_ms`, ★
`route_reason: baseline_default_tier`.

**What the learner should notice:** One request goes through the boundary and
comes back as a decision, not a raw model payload. The service selected the
balanced tier, estimated the cost at just over eight-tenths of a cent, and broke
the tokens out as **prompt, completion, and total** — the numbers every cost and
capacity decision later depends on. The caller never sees a provider-specific
response; it sees this normalized shape. This is the single decision that
weighted and payload-based load balancing will build on.

### Step 6: Read the normalized receipt in PostgreSQL (LO TO1, EO1a)

**Goal:** Look at the persisted receipt itself — proof the decision is durable
and provider-agnostic.

```bash
docker compose exec -T postgres psql -U genai -d genai -tAc "SELECT row_to_json(r) FROM (
  SELECT selected_model, provider_tier, provider_status,
         prompt_tokens, completion_tokens, total_tokens,
         cost_estimate_usd, quality_score, policy_name, request_id
  FROM receipts ORDER BY created_at DESC LIMIT 1) r" \
  | python3 scripts/fmt.py --type receipt \
  --title "Read the normalized receipt in PostgreSQL (LO TO1, EO1a)" \
  --why "The decision persists in one shape regardless of provider"
```

> Runs `psql` **inside the Postgres container**, so you don't need a host
> `psql` and there's no socket/host to configure — it just works while the
> stack is up. If you prefer a host `psql`, pass the connection explicitly:
> `PGHOST=localhost PGPORT=5432 PGDATABASE=genai PGUSER=genai psql -tA -c "…"`
> (a bare `psql` fails because it defaults to a local Unix socket).

**Expected output:** one ★ receipt row — `selected_model: balanced-std`,
`provider_tier`, `provider_status`, `token_estimate` (prompt/completion/total),
`cost_estimate_usd`, `quality_score`, `policy_name: baseline` — with the same `request_id` as
Step 5.

**What the learner should notice:** This is a real row in PostgreSQL, queried
directly — the same `request_id` you just saw in Step 5, so the chain from
decision to record is complete. Every column here is provider-agnostic: whether
the request had gone to `econo-mini` or `premium-max`, it would land in these
exact columns. That is the decoupling you set out to build — the application, and
every dashboard downstream, reads one stable receipt shape and never depends on
a vendor's response. Six months from now you can answer "which model served
request X, and what did it cost" without re-running anything.

## Best-practice callout

**Put a dedicated service layer between your application and your models.**
Application code should depend on a uniform adapter contract and a normalized
receipt — never on a provider's SDK or response shape. That one boundary is what
lets you add models, fail over, and scale the service independently.

## Preflight check

```bash
bash module1/scripts/preflight_check.sh
```

Runs every step above, captures each command and its output, maps each step to
its LO, and writes the log to
[`module1/preflight_log.txt`](preflight_log.txt) so you can confirm alignment
with the outline. Expect `PASS: 6  FAIL: 0`.

## Cleanup

```bash
./scripts/module1-demo-reset.sh
```

## Key files

- `app/main.py` — the FastAPI AI service layer and all demo endpoints
- `app/providers/registry.py` — the three model tiers and six named conditions
- `app/providers/adapter.py` — deterministic simulation, token and cost estimation
- `app/routing/router.py` — the baseline routing decision
- `app/db/postgres.py` — the normalized `receipts` schema and writes
- `app/db/redis_client.py` — live provider conditions
- `scripts/fmt.py` — Pluralsight-branded output formatter (`--title` / `--why`)
- `data/payloads/baseline_request.json` — the baseline request used in Step 5
