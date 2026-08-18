# Module 3 — Demo: Run readiness audit and finalize the operational runbook

## Why this matters

**The problem:** Every control you have built — routing, queues, circuit breakers,
tracing, SLOs, prompt versioning, baseline gates, canaries — is a part, and parts do
not add up to a production system on their own. The last question before you put a
GenAI service in front of real users is not "does the code work," it is "are we
actually ready?" That question has a specific shape: can we retire a model the
provider is sunsetting without breaking callers; does the architecture hold up across
scalability, observability, security, cost, and reliability; is the deployment pattern
the right one for this workload; is there a runbook an on-call engineer can follow at
2am; and honestly, how mature is this operation? A readiness review that scores
everything green is a rubber stamp. A useful one names the gap. How do you assess a
GenAI system against production readiness criteria and decide, on evidence, how ready
it really is?

**What you will see:** Four moves that turn a pile of controls into a graded, operable
system — a deprecated model retired through a replacement adapter with compatibility
receipts; a readiness audit that scores five dimensions and names the one real gap; a
deployment decision driven by the workload's latency and throughput and confirmed against
a side-by-side comparison of serverless, containers, and dedicated GPU; and an
operational runbook wired to concrete production controls, closed by an
evidence-based maturity decision that places the system on the ladder from prototype to
scale-ready.

**What you walk away with:** The ability to manage a model deprecation (EO4d) and
assess a GenAI system against production readiness criteria — architecture (EO5a),
deployment pattern (EO5b), operational runbook (EO5c), and maturity (EO5d) — the
capstone of assessing and operating a production GenAI system (TO5).

## Learning objectives covered

| Step | LO sub-element | What proves it |
|------|----------------|----------------|
| 1 | EO4d | A deprecated model retires through a replacement adapter with compatibility receipts |
| 2 | EO5a | The audit scores scalability, observability, security, cost efficiency, and reliability |
| 3 | EO5b, EO5c | A workload profile drives a *derived* deployment decision, the patterns are compared, the runbook exposes executable operator controls, and an injected breach fires the mapped alert *live* |
| 4 | EO5d, TO5 | The maturity level is computed from the audit evidence, with each gap to scale-ready naming its investment |

## What this demo proves — and each step is unique

| Step | Command | What it teaches (nothing repeats) |
|------|---------|-----------------------------------|
| 1 | `/lifecycle/readiness/deprecation` | The adapter contract absorbs a deprecation |
| 2 | `/lifecycle/readiness/audit` | A readiness score that names the gap |
| 3 | `/workload` + `/decision` + `/patterns` + `/runbook` + `/inject-breach` → `/alert` | Evidence → a derived pattern choice, then the runbook controls proven live by an injected breach |
| 4 | `/lifecycle/readiness/maturity` | Maturity as computed evidence, with each gap naming its investment |

## Prerequisites

### Software this clip needs — do you have it?

This clip uses **Docker Desktop** (with Compose), **curl**, **jq**, **python3**,
**psql**, and **tmux**. Two commands cover every case:

```bash
bash scripts/ensure-ready.sh       # CHECK  — ✔ / ✗ for each tool, with a fix for anything missing
bash environment-setup/setup.sh    # INSTALL — one step: installs everything the course uses, then the pinned deps
```

- **First time on this Mac?** Run the install step once. When it prints `READY`,
  you have everything this clip needs.
- **Already set up?** The check confirms you're good in seconds.

### Start the stack

**Start the stack first.** This brings up FastAPI, Redis, and PostgreSQL and waits
until healthy:

```bash
bash module3/scripts/demo_up.sh
```

The readiness audit, runbook, and maturity decision are deterministic — the same
scores and the same gap reproduce every time. Reset before you start:

```bash
./scripts/module3-demo-reset.sh
```

## Demo steps

### Step 1: Migrate off the deprecated model

**Goal:** Retire a deprecated model by routing its traffic through a replacement
adapter, and prove the swap is safe with compatibility receipts.

```bash
curl -s -X POST http://localhost:8000/lifecycle/readiness/run >/dev/null
curl -s http://localhost:8000/lifecycle/readiness/deprecation | python3 scripts/fmt.py --type readiness-deprecation \
  --title "Migrate off the deprecated model" \
  --why "A deprecated model retires behind the uniform adapter contract — traffic routes to a replacement with compatibility receipts"
```

**Expected output:** ★ `deprecated: balanced-std@2026-04` (`sunset 2026-09-30`), ★
`replacement: balanced-std@2026-06`, ★ `migrated: 12 requests` (`disruption: none`),
then a concrete **compatibility receipt · `dep-0012`** that names the routed identity —
★ `deprecated_model: balanced-std@2026-04`, ★ `replacement_model: balanced-std@2026-06`
— and its four checks all `pass` (`output_contract`, `latency_within_slo`,
`cost_within_budget`, `quality_within_bar`), and ★ `disposition: MIGRATED`.

**What the learner should notice:** This is where the very first design decision of
the course pays off. Because every model sits behind one uniform adapter contract,
retiring a deprecated model is a routing change, not a code change — callers never
touch their integration. The compatibility receipt is the proof, and it is a named
artifact you can point at: receipt `dep-0012` records the routed identity — deprecated
`balanced-std@2026-04` to replacement `balanced-std@2026-06` — with output contract,
latency, cost, and quality all still passing on the replacement, so you are not hoping
the swap is safe, you are asserting it with evidence. Keep the claim honest and scoped:
across these twelve controlled migration requests the replacement preserved the tested
contract without observed disruption — that is what `disruption: none` reports here, not
a universal guarantee. Providers sunset models on their schedule, not yours, and an
architecture that turns that into a receipt-backed migration behind a uniform contract
is one that can survive the real world.

### Step 2: Run the production readiness audit

**Goal:** Score the system across the five readiness dimensions and see where it stands
— including where it does not.

```bash
curl -s http://localhost:8000/lifecycle/readiness/audit | python3 scripts/fmt.py --type readiness-audit \
  --title "Run the production readiness audit" \
  --why "Score scalability, observability, security, cost efficiency, and reliability against readiness criteria"
```

**Expected output:** ★ `readiness score: 17/20` (`4 of 5 dimensions ready`), then the
five rows — scalability `4/4 ready`, observability `4/4 ready`, security `2/4 gap`,
cost_efficiency `3/4 ready`, reliability `4/4 ready` — and ★ `open gaps: security`. Then,
under **security gap — PII redaction sample**, a concrete example of what that gap means:
★ `field: customer_ref`, ★ `raw: cust-102317` (`carries PII`), ★ `redacted: cust-XXX317`
(`last 3 kept for support lookup, the rest masked`), and ★ `coverage: 62% of requests
sampled` — the other 38% unverified, which is the gap.

**What the learner should notice:** The most valuable number on this screen is the one
that is not green. Four dimensions are production-ready, and they are backed by real
controls you built — the queue and rate limits for scalability, the traces and SLO
alerts for observability, the circuit breaker and fallback for reliability. But
security scores a two, and the audit does not leave that abstract — it shows you exactly
what the gap is. Look at the PII redaction sample: a raw `customer_ref` of `cust-102317`
carries personally identifiable information, and the redaction rule masks it to
`cust-XXX317`, keeping only the last three characters so support can still reference a
ticket while the identity is hidden. That part works. The gap is `coverage: 62%` — only
sixty-two percent of requests are sampled and verified, so the other thirty-eight percent
could be leaking unredacted PII and nobody would know. That is a real, nameable task, not
a vibe. That honesty is the entire point of a readiness review: an audit that scores
everything green is worthless because it tells you nothing to do; an audit that shows you
`cust-102317 → cust-XXX317` at 62% coverage gives you a task and a reason. A seventeen out
of twenty with a known gap beats a fake twenty every single time.

### Step 3: Derive the deployment pattern, then prove the runbook fires

**Goal:** Start from evidence — read the workload profile, let the deployment decision be
*derived* from it, and compare the three patterns. Then read the operational runbook as
concrete `trigger → action` controls and *prove one fires*: inject a latency breach and
watch the mapped scale-out action trigger live.

```bash
curl -s http://localhost:8000/lifecycle/readiness/workload | python3 scripts/fmt.py --type readiness-workload \
  --title "Read the workload profile" \
  --why "The workload profile inputs — steady RPS, latency target, and cold-start penalty — the decision is derived from"
curl -s http://localhost:8000/lifecycle/readiness/decision | python3 scripts/fmt.py --type readiness-decision \
  --title "Choose the deployment pattern" \
  --why "The cloud-native pattern the workload profile calls for — by latency, throughput, and warm-start"
curl -s http://localhost:8000/lifecycle/readiness/patterns | python3 scripts/fmt.py --type readiness-patterns \
  --title "Compare the deployment patterns" \
  --why "Serverless, containers, and dedicated GPU on latency, throughput, warm start, and ownership"
curl -s http://localhost:8000/lifecycle/readiness/runbook | python3 scripts/fmt.py --type readiness-runbook \
  --title "Inspect the operational runbook" \
  --why "Deploy, monitoring, incident response, rollback, and capacity — each an executable trigger → action control"
# Now BREAK IT: inject a p95 breach above the 2500ms SLO, then read the alert the runbook fired
curl -s -X POST "http://localhost:8000/lifecycle/readiness/inject-breach?p95_ms=2600" >/dev/null
curl -s http://localhost:8000/lifecycle/readiness/alert | python3 scripts/fmt.py --type readiness-alert \
  --title "Prove the runbook fires" \
  --why "The injected breach is evaluated against the SLO — the mapped scale-out action fires only on a real breach"
```

**Expected output:** first the **workload profile** — three signals, each `sample →
reading`: traffic `9.8 RPS avg · 11.2 peak → steady ~10 RPS`, latency `p95 420ms vs 500ms
target → latency-sensitive`, cold_start `1800ms penalty vs 500ms target → cold starts
unacceptable`, and ★ `cold start tolerable: false`. Then the decision, ★ `derived from:
/lifecycle/readiness/workload` → ★ `recommended pattern: containers`. Then the comparison —
`serverless` (ruled out), `containers` (`chosen`), `dedicated_gpu` (`unnecessary cost at 10
RPS`) — with ★ `chosen: containers`. Then the **runbook** — five sections (`deploy`,
`monitoring`, `incident_response`, `rollback`, `capacity`) and, under **operator controls
(trigger → action)**, executable rules including ★ `queue_depth > 20 OR p95 > 2000ms →
scale out` and ★ `availability < 99% OR quality_pass < 90% → page`. Finally, after the
injected breach, the alert — ★ `ALERT FIRED: p95_latency_breach`, ★ `measured: 2600ms`
(`threshold 2500ms — breached`), ★ `action taken: scale_out_triggered (target 30 RPS)`,
with the escalation, diagnosis, and rollback path.

**What the learner should notice:** Watch the order — the inputs come first, and the
decision falls out of them. The workload profile supplies the numbers — 9.8 RPS, a p95 of
420ms against a 500ms *deployment target* (distinct from the wider 2500ms operational SLO
in the runbook), and an 1800ms cold-start penalty — so `recommended pattern: containers` is
a computed result, not an opinion: `derived from: /lifecycle/readiness/workload`. The fact
that decides the most is `cold start tolerable: false` — an 1800ms cold start against a
500ms target eliminates scale-to-zero serverless before the conversation starts. Then the
runbook, and it earns its keep in the **operator controls** block: those are not prose,
they are executable `trigger → action` rules an on-call engineer runs at 2am without a
meeting. And here is the part most demos skip — proving it. Injecting a p95 of `2600ms`
pushes latency past the `2500ms` SLO, and the alert fires *live*: `ALERT FIRED`, `action
taken: scale_out_triggered`. That is not a canned response — inject `2400ms` instead and
nothing fires, because the control is a real threshold, not a screenshot. A runbook that
executes in front of you is a runbook; a document nobody opens during an incident is not.

### Step 4: Decide the operational maturity

**Goal:** Place the system on the maturity ladder — prototype, managed production, or
scale-ready — with a level *computed* from the audit evidence, and name the exact gaps to
the next level, each with the investment required to close it.

```bash
curl -s http://localhost:8000/lifecycle/readiness/maturity | python3 scripts/fmt.py --type readiness-maturity \
  --title "Decide the operational maturity" \
  --why "Prototype, managed production, or scale-ready — an evidence-based decision with the gaps to the next level"
```

**Expected output:** the maturity ladder with `managed_production` marked `← current`, ★
`derived from: /lifecycle/readiness/audit (open gaps) + capacity evidence`, the proven
evidence, and the gaps to scale-ready **each naming its investment**: the security audit
gap (PII `62% → 95%`), the load-test ceiling (`30 RPS proven → prove 100 RPS`), and
multi-region failover — with ★ `disposition: MANAGED_PRODUCTION`.

**What the learner should notice:** This is the honest close. The maturity decision says
`derived from: /lifecycle/readiness/audit` — the level is *computed*, not awarded. The
system is not a prototype: observability, resilience, versioning, canary releases, cost
tracking, model migration, and the runbook you just fired are all proven. But it is not
scale-ready either, and the decision proves why by reading straight from the audit — the
same security gap you saw scored `2/4` in Step 2 leads the list. And each gap names the
*investment*, not just the shortfall: PII redaction `62% → 95%` (switch to inline redaction
or double the sample rate), `30 RPS proven → prove 100 RPS` (a four-hour soak test), and a
replica region with a failover drill. That is what operational maturity actually is — not
a badge you award yourself, but a position you can defend with evidence, plus a costed list
of what comes next. You now have a GenAI service you can scale, observe, release, and
operate — and, just as importantly, an honest account of exactly how ready it is.

## Preflight check

```bash
bash module3/scripts/m3-demo6-readiness-audit-runbook.preflight.sh
```

Runs every step above, captures each command and its output, maps each step to EO4d /
TO5 / EO5a–d, and writes a readable log to `preflight-logs/m3-demo6-readiness-audit-runbook.log`. Expect
`PASS: 4  FAIL: 0`.

## Cleanup

```bash
./scripts/module3-demo-reset.sh
```

## Key files

- `app/lifecycle/readiness.py` — the deterministic deprecation migration, readiness
  audit, deployment decision, pattern comparison, operational runbook, and maturity
  decision
- `app/main.py` — the `/lifecycle/readiness/run`, `/lifecycle/readiness/deprecation`,
  `/lifecycle/readiness/audit`, `/lifecycle/readiness/workload`,
  `/lifecycle/readiness/decision`, `/lifecycle/readiness/patterns`,
  `/lifecycle/readiness/runbook`, `/lifecycle/readiness/inject-breach`,
  `/lifecycle/readiness/alert`, and `/lifecycle/readiness/maturity` endpoints
- `scripts/fmt.py` — the `readiness-deprecation` / `readiness-audit` /
  `readiness-workload` / `readiness-decision` / `readiness-patterns` /
  `readiness-runbook` / `readiness-alert` / `readiness-maturity` views
