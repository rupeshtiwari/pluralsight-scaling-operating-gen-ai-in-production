# Module 1 — Demo: Payload-Based Routing & Deterministic Overrides

## What This Demo Proves

You will route requests to model tiers using three **separate** signals — prompt
**size** (evidence only), declared **complexity** (which selects the tier), and a
**risk / override** class (which pins the tier deterministically). You will prove
that length alone does not force premium and that complexity alone does — then
fire two overrides in opposite directions (bulk → economy, legal → premium),
tally the decisions in **Redis**, and read the per-request audit trail in
**PostgreSQL**. Every result shows its token estimate, complexity, and cost.

## Learning Objectives Covered

| LO | What You Will Be Able To Do After This Demo |
|----|---------------------------------------------|
| EO1c | Implement payload-based routing that sends each request to the appropriate tier for its **complexity** — a declared signal, kept separate from prompt length |
| EO1d | Contrast weighted, payload, and deterministic routing, and apply override rules that intentionally bypass the normal decision in both directions |

## Three Signals, Kept Separate

| Signal | Source | Role |
|--------|--------|------|
| **size** | token estimate of the prompt | Evidence and cost only — never selects the tier |
| **complexity** | declared `task_class` → simple / moderate / complex | Selects the tier (EO1c) |
| **risk / override** | declared `override_class` | Pins the tier, bypassing the decision (EO1d) |

> Length is not complexity. A long summary is simple; a short "find the
> concurrency bug" is complex. The router selects on declared complexity, not
> token count.

## Prerequisites

Complete the one-time setup in the [root README](../../README.md). Then start
the stack and reset to a clean state:

```bash
bash module1/scripts/demo_up.sh    # readiness check (auto-starts Docker) → FastAPI, Redis, PostgreSQL, waits healthy
./scripts/module1-demo-reset.sh    # clears receipts + all routing/smart counters
```

To check the tools first without starting anything: `bash scripts/ensure-ready.sh`.

## Demo Steps

### Step 1: Load the Routing Rules (EO1c, EO1d)

**What we are doing:** Showing the rule table across all three signals — the size
threshold (evidence), the task-class → complexity → tier map, and the override
classes with their direction and risk.

```bash
curl -s http://localhost:8000/routing/rules | python3 scripts/fmt.py --type rules \
  --title "Load the payload-based routing rules" \
  --why "Three separate signals — size is evidence, declared complexity picks the tier, overrides pin it"
```

**Validate:**

| Field | Expected | What It Means |
|-------|----------|---------------|
| policy_name | `payload_smart` | The active content-based policy |
| size | ≤ 60 tokens = short, else long | Size is labeled for cost, not used to pick the tier |
| task class → complexity → tier | ticket_tag/doc_summary → simple → econo-mini · bug_triage/incident_analysis → complex → premium-max | Complexity is declared, not derived from length |
| overrides | bulk_batch → econo-mini (economy) · legal_review → premium-max (risk) | Deterministic pins in both directions |

**What you proved:** The policy reads three separate signals. Complexity — a
declared task class — is what selects the tier; size is only evidence; overrides
pin a tier on purpose.

### Step 2: Length Alone Does Not Force Premium (EO1c)

**What we are doing:** Routing a **short-simple** request and a **long-simple**
request through the same endpoint. Both should land on the cheap tier.

```bash
curl -s -X POST http://localhost:8000/route/smart \
  -H "Content-Type: application/json" -d @data/payloads/smart_short_simple.json \
  | python3 scripts/fmt.py --type smart --title "Short + simple" \
  --why "Small prompt, simple task — routes to econo-mini"

curl -s -X POST http://localhost:8000/route/smart \
  -H "Content-Type: application/json" -d @data/payloads/smart_long_simple.json \
  | python3 scripts/fmt.py --type smart --title "Long + simple" \
  --why "Large prompt, still a simple task — length does not force premium"
```

**Validate:**

| Field | Short-simple | Long-simple | What It Means |
|-------|-------------|-------------|---------------|
| size | `short` | `long` | The prompts differ in length |
| token_estimate | small total | large total | Visible size evidence |
| complexity | `simple` | `simple` | Same declared complexity |
| selected_model | `econo-mini` | `econo-mini` | Both cheap — length did **not** escalate the tier |
| route_reason | `complexity_simple` | `complexity_simple` | The tier came from complexity |

**What you proved:** A long prompt and a short prompt with the same declared
complexity route to the same tier. Length alone does not force premium.

### Step 3: Complexity, Not Length, Changes the Tier (EO1c)

**What we are doing:** Routing a **short-complex** request and a **long-complex**
request. Both should land on premium — the short one proving complexity beats
length.

```bash
curl -s -X POST http://localhost:8000/route/smart \
  -H "Content-Type: application/json" -d @data/payloads/smart_short_complex.json \
  | python3 scripts/fmt.py --type smart --title "Short + complex" \
  --why "Small prompt, complex task — complexity routes it to premium-max"

curl -s -X POST http://localhost:8000/route/smart \
  -H "Content-Type: application/json" -d @data/payloads/smart_long_complex.json \
  | python3 scripts/fmt.py --type smart --title "Long + complex" \
  --why "Large prompt, complex task — also premium-max"
```

**Validate:**

| Field | Short-complex | Long-complex | What It Means |
|-------|--------------|--------------|---------------|
| size | `short` | `long` | The short one is small |
| complexity | `complex` | `complex` | Declared complex task |
| selected_model | `premium-max` | `premium-max` | Both premium — even the short one |
| route_reason | `complexity_complex` | `complexity_complex` | Tier came from complexity, not size |

**What you proved:** A short but complex request ("identify the concurrency bug")
routes to premium — the opposite of Step 2. Complexity, not length, changes the
tier. That is complexity-aware routing, not payload-size routing.

### Step 4: Deterministic Overrides — Both Directions (EO1d)

**What we are doing:** Firing two overrides that bypass the complexity decision —
one that forces **cheaper** (bulk economy) and one that forces **stronger**
(high-risk legal).

```bash
curl -s -X POST http://localhost:8000/route/smart \
  -H "Content-Type: application/json" -d @data/payloads/smart_bulk_override.json \
  | python3 scripts/fmt.py --type smart --title "Override: bulk batch → economy" \
  --why "A complex payload would pick premium; the bulk override forces econo-mini"

curl -s -X POST http://localhost:8000/route/smart \
  -H "Content-Type: application/json" -d @data/payloads/smart_legal_override.json \
  | python3 scripts/fmt.py --type smart --title "Override: legal review → premium (high risk)" \
  --why "A simple payload would pick econo-mini; the risk override forces premium-max"
```

**Validate:**

| Field | Bulk override | Legal override | What It Means |
|-------|--------------|----------------|---------------|
| complexity | `complex` | `simple` | What the payload actually is |
| would_have_selected | `premium-max` | `econo-mini` | What complexity routing *would* have picked |
| selected_model | `econo-mini` | `premium-max` | What the override forced instead |
| route_reason | `override_bulk_batch` | `override_legal_review` | The override fired, not complexity |
| override_direction / risk | economy / low | risk / **high** | Opposite directions |

**What you proved:** `would_have_selected` shows the override did not happen by
accident — it overrode a known decision. Bulk forces cheaper; high-risk legal
forces stronger. Deterministic overrides are policy enforcement, not just cost
control.

### Step 5: Aggregate Proof (Redis) + Per-Request Audit (PostgreSQL) (EO1c, EO1d)

**What we are doing:** Reading the Redis decision counters straight from the
datastore, then the durable per-request receipts from PostgreSQL.

```bash
docker compose exec -T redis redis-cli --json HGETALL smart:counters \
  | python3 scripts/fmt.py --type smart-counters \
  --title "Smart-routing counters in Redis" \
  --why "How each decision was made — complexity vs override — and weighted path bypassed"

docker compose exec -T postgres psql -U genai -d genai -tAc "SELECT row_to_json(r) FROM (
  SELECT request_id, total_tokens, complexity, selected_model, route_reason, override_class, cost_estimate_usd
  FROM receipts ORDER BY created_at DESC LIMIT 6) r" \
  | python3 scripts/fmt.py --type smart-receipts \
  --title "Per-request audit receipts in PostgreSQL" \
  --why "Durable per request: id, tokens, complexity, tier, reason, cost"
```

**Validate:**

| Source | Expected | What It Means |
|--------|----------|---------------|
| Redis `payload:simple` / `payload:complex` | 2 / 2 | Requests routed by complexity |
| Redis `override:bulk_batch` / `override:legal_review` | 1 / 1 | Requests pinned by override |
| Redis `weighted` | `0` | The weighted path was bypassed — cleanest proof |
| PostgreSQL rows | one per request, with `request_id` + `total_tokens` + `complexity` + `route_reason` | Durable, per-request audit trail |

**What you proved:** Redis gives the aggregate decision breakdown (and
`weighted: 0` proves smart routing never took the weighted path); PostgreSQL
gives the durable per-request record — token estimate, complexity, tier, reason,
and cost, keyed by request id.

### Step 6: Validate Every Payload Class (EO1c, EO1d)

**What we are doing:** Replaying all six canonical cases and confirming each
routes to the expected tier and reason.

```bash
curl -s http://localhost:8000/routing/smart-validate | python3 scripts/fmt.py --type smart-validate \
  --title "Validate that every payload lands where its rules dictate" \
  --why "Size, complexity, and overrides are deterministic and testable — same input, same tier, every run"
```

**Validate:**

| Field | Expected | What It Means |
|-------|----------|---------------|
| cases | `6` | short-simple, long-simple, short-complex, long-complex, high-risk override, bulk override |
| all_match | `true` | Every payload landed on its expected tier |
| per case | size + complexity shown, each ✓ | Size and complexity are independent and deterministic |

**What you proved:** All six approved payload forms — including both override
directions — match their expected tier. The classification and override logic is
deterministic for a given policy version, so it is testable in CI and safe to
change behind a guardrail.

## Cleanup

```bash
./scripts/module1-demo-reset.sh
```

## Narration Notes

- **Size ≠ complexity ≠ risk.** Say it explicitly: "Weighted routing controls
  aggregate distribution; payload routing selects a tier per request by declared
  complexity; deterministic overrides enforce exceptions." Do not group them.
- **Determinism scope.** The classification and override decision are
  deterministic *for a given policy version* — not a claim that the full runtime
  route ignores provider health, quota, or availability (those arrive in later
  modules).
- **Cost is synthetic.** `cost_estimate_usd` is a deterministic local estimate
  for comparing routes, not a provider invoice.
- **Override safety.** Pinning bulk traffic to the economy tier is safe only for
  evaluation-approved task classes with a bounded output and a quality/escalation
  path — say so, so learners don't copy an unsafe generalization.

## Preflight (Author Validation)

```bash
bash module1/scripts/clip5_preflight_check.sh
```

Runs every step, asserts EO1c and EO1d, and writes
`module1/clip5_preflight_log.txt`. Expect `PASS: 6  FAIL: 0`.

## Summary — What You Learned

| Concept | What You Saw | Where |
|---------|--------------|-------|
| Three separate signals: size, complexity, risk | `/routing/rules` table | Step 1 |
| Length alone does not force premium | long-simple → econo-mini | Step 2 |
| Complexity, not length, changes the tier | short-complex → premium-max | Step 3 |
| Overrides pin a tier in both directions | bulk → economy, legal → premium, with `would_have_selected` | Step 4 |
| Aggregate + per-request proof | Redis counters (`weighted: 0`) + PostgreSQL receipts | Step 5 |
| Deterministic across all six classes | `all_match: true` over 6 cases | Step 6 |

## Key Files

| File | Purpose |
|------|---------|
| `app/main.py` | `/routing/rules`, `/route/smart`, `/routing/smart-counters`, `/routing/smart-validate` |
| `app/providers/registry.py` | `TASK_COMPLEXITY`, `COMPLEXITY_TIERS`, `OVERRIDE_RULES` (direction + risk), size threshold, 6 validation cases |
| `app/routing/payload.py` | The pure `smart_decision` (size / complexity / override) and the smart route |
| `app/db/redis_client.py` | The `smart:counters` hash (`HINCRBY` / `HGETALL`) |
| `app/db/postgres.py` | Receipts with `complexity` and `override_class` columns |
| `data/payloads/` | `smart_short_simple`, `smart_long_simple`, `smart_short_complex`, `smart_long_complex`, `smart_legal_override`, `smart_bulk_override` |
| `scripts/fmt.py` | The `rules` / `smart` / `smart-counters` / `smart-receipts` / `smart-validate` views |

## Next

Validate routing receipts, counters, and disposition — tie the baseline,
weighted, and payload policies together into one audit.
