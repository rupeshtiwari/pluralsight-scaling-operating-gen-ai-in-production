# Module 1 — Demo: Prove payload-based routing and deterministic overrides

## Why this matters

**The problem:** Weighted routing splits traffic by a fixed percentage, which is
great for controlling aggregate cost — but it is blind to what any single request
actually *needs*. A one-line "tag this ticket" and a dense multi-part analysis
get treated the same. You want the opposite: route each request to the tier its
**content** calls for — and do it on the right signal, because *length is not
complexity*. A long summary can be simple; a short "find the concurrency bug" can
be hard. And for the traffic you refuse to leave to a policy, you want to **force**
a tier on purpose, regardless of what the payload looks like.

**What you will see:** Six moments that separate three signals and prove each one
— the rule table across size, complexity, and risk; a short-simple and a
long-simple request that both stay cheap (length alone does not force premium); a
short-complex and a long-complex request that both go premium (complexity, not
length, decides); two deterministic overrides in opposite directions; the Redis
counters that break the decisions down and prove the weighted path was bypassed;
and a validation that all six payload classes land where their rules dictate.

**What you walk away with:** Payload-based routing you can reason about per
request — driven by declared complexity, not prompt length — plus deterministic
overrides for the traffic that must not be left to a policy. The
weighted-versus-deterministic trade-off made explicit, measured in Redis, backed
by PostgreSQL receipts, and proven repeatable.

## Learning objectives covered

| LO | Description |
|----|-------------|
| EO1c | Apply payload-based routing to direct requests to appropriate model tiers based on input characteristics such as length or complexity |
| EO1d | Evaluate the trade-offs between weighted distribution and deterministic routing strategies for different traffic patterns and cost profiles |

## What this demo proves — and each step is unique

| Step | Endpoint | What it teaches (nothing repeats) |
|------|----------|-----------------------------------|
| 1 | `/routing/rules` | Three separate signals — size (evidence), declared complexity (selects the default tier), override (replaces it) |
| 2 | `/route/smart` (simple ×2) | Length alone does not force premium — short and long both stay cheap |
| 3 | `/route/smart` (complex ×2) | Complexity, not length, changes the tier — a short complex ask goes premium |
| 4 | `/route/smart` (override ×2) | Deterministic overrides pin a tier both ways — economy and risk |
| 5 | `smart:counters` + `receipts` | Aggregate decision counts (weighted bypassed) plus the durable per-request audit |
| 6 | `/routing/smart-validate` | All six payload classes match their expected tier, repeatably |

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
- Redis reachable (the smart-routing counters in Step 5 live here)
- PostgreSQL reachable (each smart decision persists a receipt for Step 5)

For a clean state before you start — clears receipts **and** all routing counters:

```bash
./scripts/module1-demo-reset.sh
```

## Demo steps

### Step 1: Load the payload-based routing rules

**Goal:** Show the rule table across all three signals — the size threshold
(evidence), the task-class → complexity → tier map, and the override classes with
their direction and risk.

```bash
curl -s http://localhost:8000/routing/rules | python3 scripts/fmt.py --type rules \
  --title "Load the payload-based routing rules" \
  --why "Three separate signals — size is evidence, declared complexity picks the tier, overrides pin it"
```

**Expected output:** ★ `policy_name: payload_smart`, a `size` note (`≤ 60 tokens =
short, else long`), the task-class → complexity → tier map (`ticket_tag` /
`doc_summary` → simple → `econo-mini`, `bug_triage` / `incident_analysis` →
complex → `premium-max`), and the override classes (`bulk_batch → econo-mini`,
economy; `legal_review → premium-max`, risk).

**What the learner should notice:** The policy reads three separate signals, and
the screen keeps them apart on purpose. **Complexity** — a *declared task class* —
selects the *default* tier; **size** is only evidence for cost; and an
**override** can intentionally replace that default. That separation is the whole
point: length is not complexity, so the router must not decide on token count
alone.

### Step 2: Size influences cost, not capability

**Goal:** Route a short-simple request and a long-simple request through the same
endpoint and watch both land on the cheap tier.

```bash
{ curl -s -X POST http://localhost:8000/route/smart -H "Content-Type: application/json" -d @data/payloads/smart_short_simple.json
  echo
  curl -s -X POST http://localhost:8000/route/smart -H "Content-Type: application/json" -d @data/payloads/smart_long_simple.json
} | python3 scripts/fmt.py --type smart-pair \
  --title "Size influences cost, not capability" \
  --why "Two prompts, very different length, same simple task — both stay on econo-mini"
```

**Expected output:** a two-row table — `short` (small `tokens`) and `long` (large
`tokens`) — both showing `complexity: simple`, `selected: econo-mini`, and
`route_reason: complexity_simple`. Only `tokens` and `cost` differ between the rows.

**What the learner should notice:** Two prompts of very different length, same
declared complexity, same cheap tier. The token estimate is right there on screen,
so you can see the second request is genuinely large — a bigger prompt costs more
tokens, but it does not need a more capable model. **Size influences cost, not
capability:** length did not escalate the tier. That is the first half of the
"size is not complexity" proof.

### Step 3: Prove complexity, not length, changes the tier

**Goal:** Route a short-complex request and a long-complex request, and watch both
land on premium — the short one proving complexity beats length.

```bash
{ curl -s -X POST http://localhost:8000/route/smart -H "Content-Type: application/json" -d @data/payloads/smart_short_complex.json
  echo
  curl -s -X POST http://localhost:8000/route/smart -H "Content-Type: application/json" -d @data/payloads/smart_long_complex.json
} | python3 scripts/fmt.py --type smart-pair \
  --title "Complexity, not length, changes the tier" \
  --why "A short complex task and a long complex task both route to premium-max"
```

**Expected output:** a two-row table — `short` (small `tokens`) and `long` (large
`tokens`) — both showing `complexity: complex`, `selected: premium-max`, and
`route_reason: complexity_complex`. The `short` row proves complexity, not length,
drives the tier.

**What the learner should notice:** The short request — "identify the concurrency
bug in this transaction protocol" — is tiny by token count, yet it routes to
premium because its declared complexity is high. Compare it to Step 2's long-simple
request that stayed cheap. This is the opposite outcome from the same endpoint:
complexity, not length, drives the tier. That is complexity-aware routing, not
payload-size routing.

### Step 4: Force a tier with deterministic overrides — both directions

**Goal:** Fire two overrides that bypass the complexity decision — one forcing
*cheaper* (bulk economy), one forcing *stronger* (high-risk legal).

```bash
{ curl -s -X POST http://localhost:8000/route/smart -H "Content-Type: application/json" -d @data/payloads/smart_bulk_override.json
  echo
  curl -s -X POST http://localhost:8000/route/smart -H "Content-Type: application/json" -d @data/payloads/smart_legal_override.json
} | python3 scripts/fmt.py --type smart-pair \
  --title "Deterministic overrides — both directions" \
  --why "would→ shows the tier complexity routing would have chosen before the override"
```

**Expected output:** a two-row table with a `would→` column. The **bulk** row —
`complex`, `selected: econo-mini`, `would→ premium-max`, `route_reason:
override_bulk_batch` (forced *cheaper*). The **legal** row — `simple`, `selected:
premium-max`, `would→ econo-mini`, `route_reason: override_legal_review` (forced
*stronger*).

**What the learner should notice:** `would_have_selected` is the proof the
override did not happen by accident — it overrode a *known* decision. The bulk job
was complex and would have gone premium, but the economy override forced it cheap.
The legal request was simple and would have gone cheap, but the risk override
forced it premium. Two overrides, opposite directions: deterministic overrides are
policy *enforcement*, not just cost control.

### Step 5: Prove aggregate behavior in Redis and per-request audit in PostgreSQL

**Goal:** Read the smart-routing counters straight from Redis, then the durable
per-request receipts from PostgreSQL.

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

**Expected output:** the Redis counters show ★ `payload:simple 2`,
★ `payload:complex 2`, ★ `override total: 2` (then ★ `override:bulk_batch 1`,
★ `override:legal_review 1`), and ★ `weighted path (bypassed): 0`. The receipts
show six ★ rows, each with `request_id`, `total_tokens`, `complexity`,
`selected_model`, `route_reason`, and `cost`.

**What the learner should notice:** Redis breaks the six decisions down by
dimension — routed by complexity vs pinned by override — read straight from the
datastore. The `weighted` field is `0`: smart routing never took the weighted path,
which is the cleanest proof the override bypassed it. PostgreSQL is the durable
side: every request keyed by id, with its token estimate, complexity, tier,
reason, and cost — the audit trail you can query months later to answer not just
*which* model served a request, but *why the router chose it*.

### Step 6: Validate that every payload class lands where its rules dictate

**Goal:** Replay all six canonical cases and confirm each routes to the expected
tier and reason.

```bash
curl -s http://localhost:8000/routing/smart-validate | python3 scripts/fmt.py --type smart-validate \
  --title "Validate that every payload lands where its rules dictate" \
  --why "Size, complexity, and overrides are deterministic and testable — same input, same tier, every run"
```

**Expected output:** ★ `cases: 6`, ★ `all_match: true`, ★ `policy_name:
payload_smart`, then a row per case with its `size` and `complexity` and a ✓ —
`short_simple` / `long_simple` → econo-mini, `short_complex` / `long_complex` →
premium-max, `high_risk_override` → premium-max, `bulk_override` → econo-mini.

**What the learner should notice:** Six payload forms — short and long, simple and
complex, plus both override directions — and every one matches its expected tier.
Run it again and you get the same result: the classification and override logic is
deterministic for a given policy version, so it is testable in CI and safe to
change behind a guardrail.

## Preflight check

```bash
bash module1/scripts/clip5_preflight_check.sh
```

Runs every step above, asserts EO1c and EO1d, and writes a readable log to
`module1/clip5_preflight_log.txt`. Expect `PASS: 6  FAIL: 0`.

## Cleanup

```bash
./scripts/module1-demo-reset.sh
```

## Key files

- `app/main.py` — the `/routing/rules`, `/route/smart`, `/routing/smart-counters`,
  `/routing/smart-validate` endpoints
- `app/providers/registry.py` — `TASK_COMPLEXITY`, `COMPLEXITY_TIERS`,
  `OVERRIDE_RULES` (direction + risk), the size threshold, and the six validation cases
- `app/routing/payload.py` — the pure `smart_decision` (size / complexity / override)
- `app/db/redis_client.py` — the `smart:counters` hash (`HINCRBY` / `HGETALL`)
- `app/db/postgres.py` — receipts with `complexity` and `override_class` columns
- `data/payloads/` — `smart_short_simple`, `smart_long_simple`, `smart_short_complex`,
  `smart_long_complex`, `smart_legal_override`, `smart_bulk_override`
- `scripts/fmt.py` — the `rules` / `smart-pair` / `smart-counters` /
  `smart-receipts` / `smart-validate` views
