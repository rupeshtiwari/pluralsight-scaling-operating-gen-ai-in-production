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

**What you will see:** Six moves that turn a pile of controls into a graded, operable
system — a deprecated model retired through a replacement adapter with compatibility
receipts; a readiness audit that scores five dimensions and names the one real gap; a
deployment decision driven by the workload's latency and throughput; a side-by-side
comparison of serverless, containers, and dedicated GPU; an operational runbook wired
to the controls the earlier demos built; and an evidence-based maturity decision that
places the system on the ladder from prototype to scale-ready.

**What you walk away with:** The ability to manage a model deprecation (EO4d) and
assess a GenAI system against production readiness criteria — architecture (EO5a),
deployment pattern (EO5b), operational runbook (EO5c), and maturity (EO5d) — the
capstone of assessing and operating a production GenAI system (TO5).

## Learning objectives covered

| Step | LO sub-element | What proves it |
|------|----------------|----------------|
| 1 | EO4d | A deprecated model retires through a replacement adapter with compatibility receipts |
| 2 | EO5a | The audit scores scalability, observability, security, cost efficiency, and reliability |
| 3 | EO5a, EO5b | The audit drives a deployment decision matched to the workload |
| 4 | EO5b | Serverless, containers, and dedicated GPU are compared on the deciding factors |
| 5 | EO5c | The operational runbook covers deploy, monitoring, incident response, rollback, capacity |
| 6 | EO5d, TO5 | The system is placed on the maturity ladder on evidence, with the gaps named |

## What this demo proves — and each step is unique

| Step | Command | What it teaches (nothing repeats) |
|------|---------|-----------------------------------|
| 1 | `/lifecycle/readiness/deprecation` | The adapter contract absorbs a deprecation |
| 2 | `/lifecycle/readiness/audit` | A readiness score that names the gap |
| 3 | `/lifecycle/readiness/decision` | The pattern follows the workload |
| 4 | `/lifecycle/readiness/patterns` | Why serverless and GPU lose here |
| 5 | `/lifecycle/readiness/runbook` | A runbook wired to real controls |
| 6 | `/lifecycle/readiness/maturity` | Maturity is evidence, not opinion |

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
four compatibility checks all `pass`, and ★ `disposition: MIGRATED`.

**What the learner should notice:** This is where the very first design decision of
the course pays off. Because every model sits behind one uniform adapter contract,
retiring a deprecated model is a routing change, not a code change — callers never
touch their integration. The compatibility receipts are the proof: output contract,
latency, cost, and quality all still pass on the replacement, so you are not hoping the
swap is safe, you are asserting it with evidence. `disruption: none` is the whole goal
of managing a deprecation. Providers sunset models on their schedule, not yours, and an
architecture that turns that into a twelve-request migration with zero caller impact is
one that can survive the real world.

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
cost_efficiency `3/4 ready`, reliability `4/4 ready` — and ★ `open gaps: security`.

**What the learner should notice:** The most valuable number on this screen is the one
that is not green. Four dimensions are production-ready, and they are backed by real
controls you built — the queue and rate limits for scalability, the traces and SLO
alerts for observability, the circuit breaker and fallback for reliability. But
security scores a two, because PII redaction sampling is not finished, and the audit
says so out loud. That honesty is the entire point of a readiness review. An audit that
scores everything green is worthless, because it tells you nothing to do; an audit that
names one concrete gap gives you a task and a reason. A seventeen out of twenty with a
known gap beats a fake twenty every single time.

### Step 3: Choose the deployment pattern

**Goal:** Turn the workload profile into a deployment decision — the cloud-native
pattern that fits the latency and throughput this service actually needs.

```bash
curl -s http://localhost:8000/lifecycle/readiness/decision | python3 scripts/fmt.py --type readiness-decision \
  --title "Choose the deployment pattern" \
  --why "The cloud-native pattern the workload calls for — by latency, throughput, and warm-start requirements"
```

**Expected output:** ★ `workload: steady ~10 RPS, latency-sensitive, cold start
unacceptable`, ★ `recommended pattern: containers`, and the reasons — cold start rules
out serverless, steady load does not need burst scaling, 10 RPS does not justify a
dedicated GPU, containers stay warm with headroom.

**What the learner should notice:** The lesson here is that the deployment pattern is
an output of the workload, not a matter of taste or whatever is trendy. Start from the
facts: the traffic is steady at about ten requests per second, it is latency-sensitive,
and cold starts are unacceptable. Those three facts do the deciding. Cold-start
sensitivity eliminates scale-to-zero serverless before you even discuss it. Steady load
means you are not paying for burst scaling you will never use. And ten RPS is nowhere
near enough to justify the cost and operational weight of a dedicated GPU. The decision
writes itself once you let the workload lead — which is exactly how these choices should
be made.

### Step 4: Compare the deployment patterns

**Goal:** See the three patterns side by side on the factors that decide, and confirm
why the two you did not pick lose.

```bash
curl -s http://localhost:8000/lifecycle/readiness/patterns | python3 scripts/fmt.py --type readiness-patterns \
  --title "Compare the deployment patterns" \
  --why "Serverless, containers, and dedicated GPU on latency, throughput, warm start, and ownership"
```

**Expected output:** three rows — `serverless` (`cold starts`, ruled out), `containers`
(`always warm`, `chosen`), `dedicated_gpu` (`overkill at 10 RPS`) — compared on latency,
throughput, warm start, and ownership, with ★ `chosen: containers`.

**What the learner should notice:** A good decision shows its work, and this table is
the work behind the last step. Seeing all three options next to each other makes the
trade-offs concrete instead of abstract: serverless has the lowest ownership burden but
loses on cold starts; a dedicated GPU has the best raw latency and throughput but brings
an operational burden and a price tag that ten RPS cannot justify; containers sit in the
middle and win precisely because they match this workload — always warm, high enough
throughput, and autoscaling headroom. The point is not that containers are always right.
It is that the right pattern is the one whose strengths line up with your requirements
and whose weaknesses you can live with.

### Step 5: Inspect the operational runbook

**Goal:** Read the operational runbook and confirm every section is concrete and wired
to a control the system actually has.

```bash
curl -s http://localhost:8000/lifecycle/readiness/runbook | python3 scripts/fmt.py --type readiness-runbook \
  --title "Inspect the operational runbook" \
  --why "Deploy, monitoring thresholds, incident response, rollback, and capacity planning — each wired to a real control"
```

**Expected output:** five sections — `deploy` (canary ramp, health-gated),
`monitoring` (the SLO thresholds), `incident_response` (page, diagnose, fail over),
`rollback` (revert to the approved release id), `capacity` (10 RPS baseline, scale
triggers) — and ★ `runbook complete: true`.

**What the learner should notice:** Read this runbook and notice that nothing in it is
aspirational. Every section points at a control you have already seen work. The deploy
section is the canary ramp. The monitoring thresholds are the exact SLOs the alerts
evaluate. Incident response is the trace-to-logs-to-receipts path with the circuit
breaker as the escape hatch. Rollback is the approved-release-id revert. Capacity names
the scale triggers — queue depth and p95. That is what separates a real runbook from a
document nobody trusts: it is not a wish list of practices you intend to adopt, it is a
description of the machinery that already exists. An on-call engineer can follow this at
2am because every line maps to a button that actually exists.

### Step 6: Decide the operational maturity

**Goal:** Place the system on the maturity ladder — prototype, managed production, or
scale-ready — on evidence, and name the gaps that separate it from the next level.

```bash
curl -s http://localhost:8000/lifecycle/readiness/maturity | python3 scripts/fmt.py --type readiness-maturity \
  --title "Decide the operational maturity" \
  --why "Prototype, managed production, or scale-ready — an evidence-based decision with the gaps to the next level"
```

**Expected output:** the maturity ladder with `managed_production` marked `← current`,
the evidence, the gaps to scale-ready (complete PII redaction, load-test to 30 RPS,
add multi-region capacity), and ★ `disposition: MANAGED_PRODUCTION`.

**What the learner should notice:** This is the honest close to the whole course. The
system is not a prototype — it has observability, resilience, versioning, canary
releases, and cost tracking, all proven in the earlier demos, and that evidence puts it
firmly at managed production. But it is not scale-ready either, and the decision says so
by naming exactly what stands in the way: finish the security gap, load-test to the
capacity ceiling, and add multi-region failover. That is what operational maturity
actually is — not a badge you award yourself, but a position you can defend with
evidence, plus a concrete list of what comes next. You now have a GenAI service you can
scale, observe, release, and operate — and, just as importantly, an honest account of
exactly how ready it is.

## Preflight check

```bash
bash module3/scripts/clip6_preflight_check.sh
```

Runs every step above, captures each command and its output, maps each step to EO4d /
TO5 / EO5a–d, and writes a readable log to `module3/clip6_preflight_log.txt`. Expect
`PASS: 6  FAIL: 0`.

## Cleanup

```bash
./scripts/module3-demo-reset.sh
```

## Key files

- `app/lifecycle/readiness.py` — the deterministic deprecation migration, readiness
  audit, deployment decision, pattern comparison, operational runbook, and maturity
  decision
- `app/main.py` — the `/lifecycle/readiness/run`, `/lifecycle/readiness/deprecation`,
  `/lifecycle/readiness/audit`, `/lifecycle/readiness/decision`,
  `/lifecycle/readiness/patterns`, `/lifecycle/readiness/runbook`, and
  `/lifecycle/readiness/maturity` endpoints
- `scripts/fmt.py` — the `readiness-deprecation` / `readiness-audit` /
  `readiness-decision` / `readiness-patterns` / `readiness-runbook` /
  `readiness-maturity` views
