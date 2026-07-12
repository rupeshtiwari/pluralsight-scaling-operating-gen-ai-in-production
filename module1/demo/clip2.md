# Module 1 — Demo: The FastAPI Provider Adapter Layer

## What This Demo Proves

You will stand up a dedicated AI service layer and prove it decouples
application code from any model provider. Across six steps you will see the
stack come up healthy, one uniform adapter contract spanning three model tiers,
a deterministic local provider simulation with **zero external API calls**, the
repeatable condition matrix, one baseline routing decision, and the normalized
receipt persisted in PostgreSQL. By the end you can point to exactly where the
decoupling lives — and the single decision + receipt that weighted and
payload-based routing build on later.

## Learning Objectives Covered

| LO | What You Will Be Able To Do After This Demo |
|----|---------------------------------------------|
| TO1 | Implement load balancing and intelligent request routing for multi-model GenAI service architectures |
| EO1a | Design a dedicated AI service layer that decouples application logic from model provider dependencies and enables independent scaling |

## Architecture — The Adapter Boundary

```
Application code
   │  (never imports a provider SDK)
   ▼
┌──────────────────────────────────────────────────────────┐
│  FastAPI AI service layer                                  │
│  ┌────────────────┐   ┌──────────────┐   ┌─────────────┐ │
│  │ Uniform adapter │──▶│ Baseline      │──▶│ Normalized  │ │
│  │ contract (×3)   │   │ routing       │   │ receipt     │ │
│  └────────────────┘   └──────────────┘   └─────────────┘ │
│    econo / balanced / premium      Redis          Postgres│
│    (deterministic stubs)      (conditions)      (receipts) │
└──────────────────────────────────────────────────────────┘
```

Application code reads the identical contract and one receipt shape regardless
of which provider is behind it. That is the decoupling this demo proves.

## Prerequisites

Complete the one-time setup in the [root README](../../README.md). Then start
the stack — this runs the readiness check (which **auto-starts Docker Desktop**
if it's installed but not open), brings up FastAPI, Redis, and PostgreSQL, waits
until healthy, and leaves you with a clean, reset stack:

```bash
bash module1/scripts/demo_up.sh
```

To check the tools first: `bash scripts/ensure-ready.sh`. Reset any time with
`./scripts/module1-demo-reset.sh`.

## Demo Steps

### Step 1: Prove Every Layer Is Healthy (EO1a)

**What we are doing:** Confirming the dedicated service and each dependency it
owns are live before a single request is routed.

```bash
curl -s http://localhost:8000/health | python3 scripts/fmt.py --type health \
  --title "Bring the stack up and prove every layer is healthy (LO EO1a)" \
  --why "Every layer of the dedicated AI service must be live before we route"
```

**Validate:**

| Field | Expected | What It Means |
|-------|----------|---------------|
| status | `healthy` | The dedicated service layer is live |
| fastapi / redis / postgres / provider_stubs | `healthy` | All four dependencies up before any routing |

**What you proved:** This is the service layer — not the app, not a provider SDK
— and it owns Redis (live conditions), PostgreSQL (durable receipts), and the
in-process stubs. All local, no paid model touched.

### Step 2: Inspect the Uniform Adapter Contract (TO1, EO1a)

**What we are doing:** Showing the decoupling boundary itself — one identical
shape describing three different model tiers.

```bash
curl -s http://localhost:8000/providers | python3 scripts/fmt.py --type providers \
  --title "Inspect the uniform adapter contract across three tiers (LO TO1, EO1a)" \
  --why "The decoupling boundary: identical fields across every model"
```

```
  ★ default_model: balanced-std

    model         tier      latency  quota      cost/1k  quality  status
  ★ econo-mini    low_cost  400ms    shared     $0.05    0.82     healthy
  ★ balanced-std  balanced  700ms    dedicated  $0.30    0.90     healthy
  ★ premium-max   premium   1200ms   reserved   $1.20    0.97     healthy
```

**Validate:**

| Field | Expected | What It Means |
|-------|----------|---------------|
| default_model | `balanced-std` | The baseline tier |
| every column | identical across all three rows | One uniform contract — only the numbers differ |
| economics | cost/latency/quality differ per tier | Low-cost vs premium trade-offs |

**What you proved:** Every model exposes the same fields; application code reads
the identical contract no matter which provider is behind it. Adding a fourth
model adds a row here and touches no caller.

### Step 3: Prove the Adapter Is a Deterministic Local Simulation (EO1a)

**What we are doing:** Probing a tier to prove the provider is simulated
deterministically — same input, same result, no external call.

```bash
curl -s http://localhost:8000/providers/balanced-std/probe | python3 scripts/fmt.py --type probe \
  --title "Prove the adapter is a deterministic local simulation (LO EO1a)" \
  --why "Zero external calls — same input, same result, every run"
```

**Validate:**

| Field | Expected | What It Means |
|-------|----------|---------------|
| external_api_calls | `0` | No network, no API key, no cost, no rate limit |
| deterministic | `true` | Same input → byte-for-byte identical result |
| model / condition / status / simulated_latency_ms | balanced-std, healthy | A fixed, reproducible probe |

**What you proved:** Provider behavior is a deterministic local simulation —
which is what lets this whole course run in CI and on a laptop while exercising
real routing, fallback, and readiness logic.

### Step 4: Show the Repeatable Condition Matrix (EO1a)

**What we are doing:** Showing every simulated condition so failure scenarios are
reproducible on demand rather than waiting for a real outage.

```bash
curl -s http://localhost:8000/providers/conditions | python3 scripts/fmt.py --type conditions \
  --title "Show the repeatable provider condition matrix (LO EO1a)" \
  --why "Six named conditions make every scenario repeatable"
```

**Validate:**

| Field | Expected | What It Means |
|-------|----------|---------------|
| active (per model) | `healthy` | Every model starts healthy |
| supported | healthy, slow, error, quota, quality, deprecation | Six named, switchable scenarios |

**What you proved:** Because each condition is named and switchable, the failure
demos later in the course are repeatable — you reproduce a quota exhaustion the
same way every time instead of hoping a provider misbehaves on camera.

### Step 5: Send a Baseline Request Through the Boundary (TO1)

**What we are doing:** Triggering one routing decision and reading the normalized
response the caller receives.

```bash
curl -s -X POST http://localhost:8000/route \
  -H "Content-Type: application/json" \
  -d @data/payloads/baseline_request.json | python3 scripts/fmt.py --type route \
  --title "Send a baseline request through the boundary (LO TO1)" \
  --why "One normalized decision the caller can trust"
```

**Validate:**

| Field | Expected | What It Means |
|-------|----------|---------------|
| selected_model | `balanced-std` | The baseline default tier |
| token_estimate | prompt=17 completion=10 total=27 | The basis for every cost/capacity decision |
| cost_estimate_usd | `$0.008100` | Estimated cost of this decision |
| route_reason | `baseline_default_tier` | Why the request was routed here |

**What you proved:** One request comes back as a decision, not a raw model
payload. The caller sees this normalized shape — the single decision that
weighted and payload-based load balancing build on.

### Step 6: Read the Normalized Receipt in PostgreSQL (TO1, EO1a)

**What we are doing:** Reading the persisted receipt itself — proof the decision
is durable and provider-agnostic.

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

> Runs `psql` **inside the Postgres container**, so you don't need a host `psql`
> and there's no socket/host to configure — it just works while the stack is up.

**Validate:**

| Field | Expected | What It Means |
|-------|----------|---------------|
| selected_model / provider_tier / provider_status | balanced-std, balanced, healthy | The persisted decision |
| token + cost + quality columns | present | Provider-agnostic receipt columns |
| policy_name | `baseline` | The routing policy that made the decision |
| request_id | same as Step 5 | The decision → record chain is complete |

**What you proved:** A real row in PostgreSQL, queried directly, with the same
`request_id` from Step 5. Every column is provider-agnostic — the application and
every dashboard downstream read one stable receipt shape and never depend on a
vendor's response.

## Cleanup

```bash
./scripts/module1-demo-reset.sh
```

## Preflight (Author Validation)

```bash
bash module1/scripts/preflight_check.sh
```

Runs every step, maps each to its LO, and writes
[`module1/preflight_log.txt`](../preflight_log.txt). Expect `PASS: 6  FAIL: 0`.

## Summary — What You Learned

| Concept | What You Saw | Where |
|---------|--------------|-------|
| The service layer owns its dependencies | `/health`: fastapi, redis, postgres, stubs all healthy | Step 1 |
| One uniform contract spans every tier | `/providers`: identical fields, different economics | Step 2 |
| Provider behavior is a deterministic local sim | `external_api_calls: 0`, `deterministic: true` | Step 3 |
| Failure scenarios are named and repeatable | Six conditions in the matrix | Step 4 |
| The boundary returns a normalized decision | `/route`: selected model, tokens, cost, reason | Step 5 |
| The decision persists provider-agnostically | PostgreSQL receipt with matching `request_id` | Step 6 |

## Key Files

| File | Purpose |
|------|---------|
| `app/main.py` | The FastAPI AI service layer and all demo endpoints |
| `app/providers/registry.py` | The three model tiers and six named conditions |
| `app/providers/adapter.py` | Deterministic simulation, token and cost estimation |
| `app/routing/router.py` | The baseline routing decision |
| `app/db/postgres.py` | The normalized `receipts` schema and writes |
| `app/db/redis_client.py` | Live provider conditions |
| `scripts/fmt.py` | Compact colored formatter (`--title` / `--why`) |
| `data/payloads/baseline_request.json` | The baseline request used in Step 5 |

## Next

Weighted routing across model tiers — split traffic 50/30/20 by cost and
latency target, and prove the distribution from Redis and PostgreSQL.
