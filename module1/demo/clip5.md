# Module 1 — Demo: Payload-Based Routing & Deterministic Overrides

## What This Demo Proves

Weighted routing splits traffic by a fixed percentage — good for aggregate cost,
but blind to what any single request needs. Here you will route each request by
its **own content**: a short "tag this ticket" lands on the cheap tier, a dense
multi-part analysis lands on premium — through the *same endpoint*. Then you will
apply a **deterministic override** that pins a class of traffic to a tier no
matter what the payload looks like, record every decision's reason in PostgreSQL,
and validate that every canonical payload lands exactly where its rules dictate.
This is payload-based routing you can reason about per request, plus overrides
for the traffic you refuse to leave to a policy.

## Learning Objectives Covered

| LO | What You Will Be Able To Do After This Demo |
|----|---------------------------------------------|
| EO1c | Implement payload-based routing that sends each request to the appropriate model tier for its complexity |
| EO1d | Contrast weighted and deterministic routing, and apply override rules that intentionally bypass weighted distribution |

## Architecture — Content Decides, Overrides Pin

```
POST /route/smart (prompt + optional request_class)
   │
   ▼
┌──────────────────────────────────────────────────────────┐
│  FastAPI Orchestrator                                      │
│  ┌────────────────────┐      ┌──────────────────────────┐│
│  │ Override rule?      │─yes─▶│ Pinned tier (bypass)      ││
│  │ (request_class)     │      │ e.g. bulk_batch→econo     ││
│  └─────────┬──────────┘      └──────────────────────────┘│
│         no │                                              │
│            ▼                                              │
│  ┌────────────────────┐      ┌──────────────────────────┐│
│  │ Complexity bucket   │────▶│ Tier by fit               ││
│  │ low / medium / high │      │ econo / balanced / premium││
│  └────────────────────┘      └──────────────────────────┘│
│                    │                                      │
│                    ▼                                      │
│           ┌──────────────────┐                            │
│           │ PostgreSQL receipt│ (route_reason per request)│
│           └──────────────────┘                            │
└──────────────────────────────────────────────────────────┘
```

## Prerequisites

Complete the one-time setup in the [root README](../../README.md). Then start
the stack and reset to a clean receipts table:

```bash
bash module1/scripts/demo_up.sh    # readiness check (auto-starts Docker) → FastAPI, Redis, PostgreSQL, waits healthy
./scripts/module1-demo-reset.sh    # clean receipts before you start
```

To check the tools first without starting anything: `bash scripts/ensure-ready.sh`.

## Demo Steps

### Step 1: Load the Payload-Based Routing Rules (EO1c, EO1d)

**What we are doing:** Showing the rule table — the complexity buckets that map to
tiers, plus the deterministic override classes.

```bash
curl -s http://localhost:8000/routing/rules | python3 scripts/fmt.py --type rules \
  --title "Load the payload-based routing rules" \
  --why "Content decides the tier — simple prompts go cheap, complex ones go premium, and override classes are pinned on purpose"
```

**Validate:**

| Field | Expected | What It Means |
|-------|----------|---------------|
| policy_name | `payload_smart` | The active content-based policy |
| complexity buckets | low ≤25 → econo-mini · medium 26–70 → balanced-std · high >70 → premium-max | The request's own size picks the tier |
| overrides | bulk_batch → econo-mini · code_generation → premium-max · legal_review → premium-max | Declared classes pinned on purpose |

**What you proved:** The whole policy on one screen, read two ways. Complexity
buckets handle the common case (content picks the tier); override classes handle
the exceptions. Weighted routing balanced *volume*; this balances *fit*.

### Step 2: Route a Simple Payload to the Low-Cost Tier (EO1c)

**What we are doing:** Sending a short, simple request and watching it land on the
cheap model on its own.

```bash
curl -s -X POST http://localhost:8000/route/smart \
  -H "Content-Type: application/json" -d @data/payloads/smart_simple.json \
  | python3 scripts/fmt.py --type smart \
  --title "Route a simple payload to the low-cost tier" \
  --why "A short request needs no premium model — the content picks econo-mini"
```

**Validate:**

| Field | Expected | What It Means |
|-------|----------|---------------|
| selected_model | `econo-mini` | The cheapest tier, chosen automatically |
| complexity | `low` | The prompt fell in the low bucket |
| route_reason | `payload_complexity_low` | Self-documenting: *why* it routed here |

**What you proved:** Nobody asked for `econo-mini`. The tiny prompt's token
estimate fell in the `low` bucket, and the service routed it to the cheapest tier
by itself.

### Step 3: Route a Complex Payload to the Premium Tier (EO1c)

**What we are doing:** Sending an involved, multi-part request through the **same
endpoint** and watching it land on premium.

```bash
curl -s -X POST http://localhost:8000/route/smart \
  -H "Content-Type: application/json" -d @data/payloads/smart_complex.json \
  | python3 scripts/fmt.py --type smart \
  --title "Route a complex payload to the premium tier" \
  --why "Same endpoint, heavier request — the content pushes it to premium-max"
```

**Validate:**

| Field | Expected | What It Means |
|-------|----------|---------------|
| selected_model | `premium-max` | The premium tier, chosen by content |
| complexity | `high` | The dense prompt fell in the high bucket |
| cost_estimate_usd | larger than Step 2 | Cost moves with the tier |

**What you proved:** Same endpoint as Step 2, opposite outcome. Payload-based
routing spends on the requests that need it and saves on the ones that don't — no
weights, no caller-specified model, just the content.

### Step 4: Force a Tier With a Deterministic Override (EO1d)

**What we are doing:** Sending that *same complex payload* but declared as a
`bulk_batch` class, and watching the override bypass payload routing.

```bash
curl -s -X POST http://localhost:8000/route/smart \
  -H "Content-Type: application/json" -d @data/payloads/smart_override.json \
  | python3 scripts/fmt.py --type smart \
  --title "Force a tier with a deterministic override" \
  --why "Some traffic must be pinned — the override wins over what the payload would pick"
```

**Validate:**

| Field | Expected | What It Means |
|-------|----------|---------------|
| selected_model | `econo-mini` | Pinned by the override |
| route_reason | `override_bulk_batch` | The override fired, not complexity routing |
| would_have_selected | `premium-max` (pink) | What payload routing *would* have chosen |

**What you proved:** The whole EO1d trade-off on one screen. The payload is
identical to Step 3 — still `high` — so payload routing would have chosen
`premium-max`. But the `bulk_batch` class pinned it to `econo-mini`. Overrides
give you a guaranteed tier for traffic you refuse to leave to a policy.

### Step 5: Record Each Decision's Reason in Receipts (EO1c, EO1d)

**What we are doing:** Querying PostgreSQL to see every routing reason persisted,
one row per request.

```bash
docker compose exec -T postgres psql -U genai -d genai -tAc "SELECT row_to_json(r) FROM (
  SELECT selected_model, provider_tier, route_reason, cost_estimate_usd, policy_name
  FROM receipts ORDER BY created_at DESC LIMIT 3) r" \
  | python3 scripts/fmt.py --type receipts \
  --title "Record each decision's reason in receipts" \
  --why "Every routed request persists its tier, cost, and the reason it was chosen"
```

**Validate:**

| Field | Expected | What It Means |
|-------|----------|---------------|
| rows | econo-mini, premium-max, econo-mini | The three decisions from Steps 2–4 |
| cost_estimate_usd | differs by tier | Cheap vs premium, per request |
| policy_name | `payload_smart` on every row | The durable audit trail |

**What you proved:** Because the `route_reason` was persisted, months later you
can answer not just *which* model served a request and what it cost, but *why the
router chose it* — its complexity bucket, or the override that pinned it.

### Step 6: Validate Every Payload Lands Where Its Rules Dictate (EO1c, EO1d)

**What we are doing:** Replaying the canonical cases and confirming each routes to
the expected tier and reason.

```bash
curl -s http://localhost:8000/routing/smart-validate | python3 scripts/fmt.py --type smart-validate \
  --title "Validate that every payload lands where its rules dictate" \
  --why "Same input, same tier, every run — payload routing and overrides are deterministic and testable"
```

**Validate:**

| Field | Expected | What It Means |
|-------|----------|---------------|
| cases | `4` | The canonical payload set |
| all_match | `true` | Every payload landed on its expected tier |
| per case | simple→econo, standard→balanced, complex→premium, override→econo, each ✓ | Deterministic decision logic |

**What you proved:** Four canonical payloads, four expected tiers, every one
matches — including the override. The decision logic is a pure function of the
payload, so it is deterministic, testable in CI, and safe to change behind a
guardrail.

## Cleanup

```bash
./scripts/module1-demo-reset.sh
```

## Preflight (Author Validation)

```bash
bash module1/scripts/clip5_preflight_check.sh
```

Runs every step, asserts EO1c and EO1d, and writes
`module1/clip5_preflight_log.txt`. Expect `PASS: 6  FAIL: 0`.

## Summary — What You Learned

| Concept | What You Saw | Where |
|---------|--------------|-------|
| Content-based rules, with override classes | `/routing/rules`: buckets + overrides | Step 1 |
| A simple payload self-routes cheap | `econo-mini`, `payload_complexity_low` | Step 2 |
| A complex payload self-routes premium | `premium-max`, `payload_complexity_high` | Step 3 |
| An override pins the tier on purpose | `override_bulk_batch`, `would_have_selected: premium-max` | Step 4 |
| Each decision's reason is durable | receipts with `route_reason` per row | Step 5 |
| The logic is deterministic and testable | `all_match: true` over 4 cases | Step 6 |

## Key Files

| File | Purpose |
|------|---------|
| `app/main.py` | `/routing/rules`, `/route/smart`, `/routing/smart-validate` endpoints |
| `app/providers/registry.py` | Complexity thresholds, complexity→tier map, override rules, validation cases |
| `app/routing/payload.py` | The pure payload decision and the smart route |
| `app/db/postgres.py` | The receipts each smart route persists |
| `data/payloads/` | `smart_simple.json`, `smart_complex.json`, `smart_override.json` |
| `scripts/fmt.py` | The `rules` / `smart` / `smart-validate` views |

## Next

Validate routing receipts, counters, and disposition — tie the baseline,
weighted, and payload policies together into one audit.
