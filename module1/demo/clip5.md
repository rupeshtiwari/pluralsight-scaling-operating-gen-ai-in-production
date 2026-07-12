# Module 1 — Clip 5: Demo: Payload-based routing & deterministic overrides (6 minutes)

## Why this matters

**The problem:** Weighted routing (Clip 3) splits traffic by a fixed
percentage, which is great for controlling aggregate cost — but it doesn't look
at what any single request actually *needs*. A one-line "tag this ticket" and a
dense multi-part analysis get treated the same, decided by a dice roll against
the weights. You want the opposite: route each request to the tier its
**content** calls for — cheap models for simple work, premium for the hard
requests — and still keep the ability to **force** a tier when a class of
traffic demands it, no matter what the payload looks like.

**What you will see:** Six moments that turn "we split traffic by weight" into
"we route each request by what it needs, and we can override that on purpose" —
the rule table, a simple payload landing on the cheap tier, a complex payload
landing on premium through the *same endpoint*, a deterministic override that
bypasses payload routing, the receipts that record every decision's reason, and
a final check that every payload lands where its rules dictate.

**What you walk away with:** Payload-based routing you can reason about per
request, plus deterministic overrides for the traffic that must not be left to a
policy — the weighted-versus-deterministic trade-off made explicit, measured in
PostgreSQL receipts, and proven repeatable.

## Learning objectives covered

| LO | Description |
|----|-------------|
| EO1c | Implement payload-based routing that sends each request to the appropriate model tier for its complexity |
| EO1d | Contrast weighted and deterministic routing, and apply override rules that intentionally bypass weighted distribution |

## What this demo proves — and each step is unique

| Step | Endpoint | What it teaches (nothing repeats) |
|------|----------|-----------------------------------|
| 1 | `/routing/rules` | The tier is decided by payload complexity, with named override classes |
| 2 | `/route/smart` (simple) | A simple payload routes to the low-cost tier on its own |
| 3 | `/route/smart` (complex) | The same endpoint sends a complex payload to premium |
| 4 | `/route/smart` (override) | A deterministic override pins the tier, bypassing payload routing |
| 5 | `receipts` (psql) | Each decision's route reason is recorded durably, per request |
| 6 | `/routing/smart-validate` | Every payload lands on the tier its rules dictate — repeatably |

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
- Redis reachable (live provider conditions)
- PostgreSQL reachable (each smart decision persists a receipt for Step 5)

For a clean receipts table before you start:

```bash
./scripts/module1-demo-reset.sh
```

**If a step shows `None` everywhere, or `curl` says connection refused:** the API
isn't running the current code. Bring it up fresh — the container mounts the
source and reloads, so this always serves the latest:

```bash
bash module1/scripts/demo_up.sh          # or, if you changed dependencies:
docker compose up -d --build
```

## Demo steps

### Step 1: Load the payload-based routing rules

**Goal:** Show the rule table — the complexity buckets that map to tiers, plus
the deterministic override classes.

```bash
curl -s http://localhost:8000/routing/rules | python3 scripts/fmt.py --type rules \
  --title "Load the payload-based routing rules" \
  --why "Content decides the tier — simple prompts go cheap, complex ones go premium, and override classes are pinned on purpose"
```

**Expected output:** ★ `policy_name: payload_smart`, three complexity buckets
(`low ≤ 25 tokens → econo-mini`, `medium 26–70 → balanced-std`, `high > 70 →
premium-max`), and the override classes (`bulk_batch → econo-mini`,
`code_generation → premium-max`, `legal_review → premium-max`).

**What the learner should notice:** This is the whole policy on one screen, and
it reads two ways. Complexity buckets handle the common case — the request's own
size picks the tier, so the caller never names a model. The override classes
handle the exceptions — a declared class pins the tier no matter what the payload
would have chosen. Weighted routing balanced *volume*; this balances *fit*.

### Step 2: Route a simple payload to the low-cost tier

**Goal:** Send a short, simple request and watch it land on the cheap model on
its own.

```bash
curl -s -X POST http://localhost:8000/route/smart \
  -H "Content-Type: application/json" -d @data/payloads/smart_simple.json \
  | python3 scripts/fmt.py --type smart \
  --title "Route a simple payload to the low-cost tier" \
  --why "A short request needs no premium model — the content picks econo-mini"
```

**Expected output:** ★ `selected_model: econo-mini`, ★ `complexity: low`, ★
`route_reason: payload_complexity_low`, with a small `cost_estimate_usd`.

**What the learner should notice:** Nobody asked for `econo-mini`. The prompt is
tiny, its token estimate falls in the `low` bucket, and the service routed it to
the cheapest tier by itself. The `route_reason` records *why* — `payload_complexity_low`
— so this decision is self-documenting.

### Step 3: Route a complex payload to the premium tier

**Goal:** Send an involved, multi-part request through the **same endpoint** and
watch it land on premium.

```bash
curl -s -X POST http://localhost:8000/route/smart \
  -H "Content-Type: application/json" -d @data/payloads/smart_complex.json \
  | python3 scripts/fmt.py --type smart \
  --title "Route a complex payload to the premium tier" \
  --why "Same endpoint, heavier request — the content pushes it to premium-max"
```

**Expected output:** ★ `selected_model: premium-max`, ★ `complexity: high`, ★
`route_reason: payload_complexity_high`, with a larger `cost_estimate_usd` than
Step 2.

**What the learner should notice:** Same endpoint as Step 2, opposite outcome.
The dense, multi-part prompt lands in the `high` bucket and routes to the premium
tier — and the cost moves with it. This is payload-based routing doing its job:
spend on the requests that need it, save on the ones that don't. No weights, no
caller-specified model, just the content.

### Step 4: Force a tier with a deterministic override

**Goal:** Send that *same complex payload* but declared as a `bulk_batch` class,
and watch the override bypass payload routing.

```bash
curl -s -X POST http://localhost:8000/route/smart \
  -H "Content-Type: application/json" -d @data/payloads/smart_override.json \
  | python3 scripts/fmt.py --type smart \
  --title "Force a tier with a deterministic override" \
  --why "Some traffic must be pinned — the override wins over what the payload would pick"
```

**Expected output:** ★ `selected_model: econo-mini`, ★ `complexity: high`, ★
`route_reason: override_bulk_batch`, and ★ `would_have_selected: premium-max`
(shown in pink).

**What the learner should notice:** This is the whole EO1d trade-off in one
screen. The payload is identical to Step 3 — still `high` complexity — so
payload routing *would* have chosen `premium-max`, and the response says so in
`would_have_selected`. But the request declared the `bulk_batch` class, and the
override pinned it to `econo-mini` anyway. Weighted and payload routing optimize
for the average request; a deterministic override gives you a guaranteed tier for
the traffic you refuse to leave to a policy — bulk jobs to the cheap model, or
(the other rules) legal and code straight to premium.

### Step 5: Record each decision's reason in receipts

**Goal:** Query PostgreSQL and see every routing reason persisted, one row per
request.

```bash
docker compose exec -T postgres psql -U genai -d genai -tAc "SELECT row_to_json(r) FROM (
  SELECT selected_model, provider_tier, route_reason, cost_estimate_usd, policy_name
  FROM receipts ORDER BY created_at DESC LIMIT 3) r" \
  | python3 scripts/fmt.py --type receipts \
  --title "Record each decision's reason in receipts" \
  --why "Every routed request persists its tier, cost, and the reason it was chosen"
```

**Expected output:** three ★ rows — `econo-mini`, `premium-max`, `econo-mini` —
each with its `provider_tier`, `cost` (differs by tier), and `policy_name:
payload_smart`.

**What the learner should notice:** The three requests from Steps 2–4 are all
here, each a durable row. Same policy name on every row, but different tiers and
different costs — and because the `route_reason` was persisted too, months later
you can answer not just *which* model served a request and what it cost, but
*why the router chose it*: its complexity bucket, or the override that pinned it.
That is the audit trail behind payload-based routing.

### Step 6: Validate that every payload lands where its rules dictate

**Goal:** Replay the canonical cases and confirm each one routes to the expected
tier and reason.

```bash
curl -s http://localhost:8000/routing/smart-validate | python3 scripts/fmt.py --type smart-validate \
  --title "Validate that every payload lands where its rules dictate" \
  --why "Same input, same tier, every run — payload routing and overrides are deterministic and testable"
```

**Expected output:** ★ `cases: 4`, ★ `all_match: true`, then a row per case —
`simple_payload → econo-mini`, `standard_payload → balanced-std`,
`complex_payload → premium-max`, `override_bulk → econo-mini` — each with a ✓.

**What the learner should notice:** This is the disposition. Four canonical
payloads, four expected tiers, and every one matches — including the override.
Run it again and you get the same result: the decision logic is a pure function
of the payload, so it is deterministic, testable in CI, and safe to change with
a guardrail. Payload routing you can prove, and overrides you can trust.

## Best-practice callout

**Route by fit, override by exception.** Let each request's own characteristics
pick the tier for the common case, so you spend premium only where it's earned.
Reserve deterministic overrides for the classes of traffic that must not be left
to a policy — bulk work to the cheap tier, high-stakes work to the best one — and
persist the route reason so every decision is auditable after the fact.

## Preflight check

```bash
bash module1/scripts/clip5_preflight_check.sh
```

Runs every step above, captures each command and its output, maps each step to
EO1c and EO1d, and writes a readable log to `module1/clip5_preflight_log.txt`.
Expect `PASS: 6  FAIL: 0`.

## Cleanup

```bash
./scripts/module1-demo-reset.sh
```

## Key files

- `app/main.py` — the `/routing/rules`, `/route/smart`, `/routing/smart-validate`
  endpoints
- `app/providers/registry.py` — the complexity thresholds, the complexity→tier
  map, the override rules, and the canonical validation cases
- `app/routing/payload.py` — the pure payload decision and the smart route
- `app/db/postgres.py` — the receipts each smart route persists
- `data/payloads/` — `smart_simple.json`, `smart_complex.json`,
  `smart_override.json`
- `scripts/fmt.py` — the `rules` / `smart` / `smart-validate` views
