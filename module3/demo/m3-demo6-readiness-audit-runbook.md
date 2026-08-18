# Module 3 — Demo: Run readiness audit and finalize the operational runbook

## Why this matters

**The problem:** Every control you have built — routing, queues, circuit breakers,
tracing, SLOs, prompt versioning, baseline gates, canaries — is a part, and parts do
not add up to a production system on their own. The last question before you put a
GenAI service in front of real users is not "does the code work," it is "are we
actually ready?" That question has a specific shape: can we retire a model the provider
is sunsetting without breaking callers; does the architecture hold up across
scalability, observability, security, cost, and reliability; is the deployment pattern
right for this workload; does the runbook actually *fire* when conditions go bad; and
honestly, how mature is this operation? A readiness review that scores everything green
is a rubber stamp. A useful one names the gap. How do you assess a GenAI system against
production readiness criteria and prove, on live evidence, how ready it really is?

**What you will see:** Four hands-on moves — you cause something and watch the system
react. A deprecated model retired through a replacement adapter, with twelve live
requests aggregated into a compatibility receipt; a readiness audit that scores five
dimensions and quantifies the one real gap; a deployment decision derived from a measured
workload, then a runbook you *break on purpose* to watch its alert fire; and an
evidence-based maturity decision that names the investment behind every gap.

**What you walk away with:** The ability to manage a model deprecation (EO4d) and assess
a GenAI system against production readiness criteria — architecture (EO5a), deployment
pattern (EO5b), operational runbook (EO5c), and maturity (EO5d) — the capstone of
assessing and operating a production GenAI system (TO5).

## Learning objectives covered

| Step | LO sub-element | What proves it |
|------|----------------|----------------|
| 1 | EO4d | A deprecated model retires through a replacement adapter; twelve live requests aggregate into a compatibility receipt with four checks |
| 2 | TO5, EO5a | The audit scores scalability, observability, security, cost efficiency, and reliability, and quantifies the security gap (verified vs unverified requests, the 95% requirement, the action) |
| 3 | EO5b, EO5c | A measured workload derives the deployment pattern; the runbook is inspected as a real artifact and *fires live* when an injected breach exceeds the SLO |
| 4 | EO5d | The maturity level is computed from the evidence — seven proven capabilities and three gaps, each naming its investment |

## What this demo proves — and each step is unique

| Step | Command | What it teaches (nothing repeats) |
|------|---------|-----------------------------------|
| 1 | `/admin/deprecate` → k6 traffic → `/receipts/migration` | A receipt proves migration, not just a route swap |
| 2 | `scripts/readiness_audit.py` | Sampled evidence is not system-wide proof — the gap is quantified |
| 3 | `scripts/workload_decision.py` + `docs/runbook.yaml` + `/admin/inject-latency` → `/admin/alerts` | Measured workload picks deployment; a live breach proves the runbook fires |
| 4 | `scripts/maturity_check.py` | Maturity is evidence, not aspiration; each gap names its investment |

## Prerequisites

### Software this clip needs — do you have it?

This clip uses **Docker Desktop** (with Compose), **curl**, **jq**, **k6**, and the
project **virtualenv** (`.venv`, which `setup.sh` builds with the pinned `rich`). Two
commands cover every case:

```bash
bash scripts/ensure-ready.sh       # CHECK  — ✔ / ✗ for each tool, with a fix for anything missing
bash environment-setup/setup.sh    # INSTALL — installs everything the course uses, then the pinned deps into .venv
```

> **Why the CLIs run as `.venv/bin/python scripts/…`:** the rich terminal tables use the
> `rich` package, which `setup.sh` installs into the project virtualenv — not your system
> Python. Invoking `.venv/bin/python` runs the pinned `rich` regardless of what `python3`
> resolves to. No host `pip install` needed. `k6` is used for the Step 1 traffic; if you
> don't have host k6, the compose fallback is `docker compose run --rm k6 run …`.

### Start the stack

**Start the stack first.** This brings up FastAPI, Redis, and PostgreSQL and waits until
healthy:

```bash
bash module3/scripts/demo_up.sh
```

Everything is deterministic — the same receipt, the same audit score, the same decision,
and the same maturity reproduce on every take. Reset before you start:

```bash
./scripts/module3-demo-reset.sh
```

## Demo steps

### Step 1: Prove the deprecation migration with receipt evidence

**Goal:** Retire a deprecated model by activating a replacement adapter, send twelve live
requests through the migrated path, and pull the compatibility receipt that aggregates
them — auditable proof the swap preserved the caller contract, not just a route change.

```bash
docker compose ps                                   # services are already up from earlier clips
curl -s -X POST "http://localhost:8000/admin/deprecate?model=balanced-std@2026-04&replacement=balanced-std@2026-06" | jq .
k6 run --quiet scripts/migration-traffic.js         # 12 requests through the adapter
curl -s http://localhost:8000/receipts/migration | .venv/bin/python scripts/ops_view.py --type receipt
```

**Expected output:** the `/admin/deprecate` call returns `status: adapter_active`; k6
sends twelve requests; then the **MIGRATION COMPATIBILITY RECEIPT** — ★ `Receipt ID:
mig-2026-06-30-001`, retiring `balanced-std@2026-04`, replacement `balanced-std@2026-06`,
`Requests Migrated: 12`, and four checks all `✅ PASS` (`output_contract 12/12`,
`latency_within_slo P95: 52ms`, `cost_within_budget $0.24/1K`, `quality_above_baseline
94.2%`), closing on ★ `DISPOSITION: ✅ MIGRATED`.

**What the learner should notice:** This is where the very first design decision of the
course pays off. Because every model sits behind one uniform adapter contract, retiring a
deprecated model is a routing change — you activated it with one call, and caller code
never moved. But the receipt is the point, not the swap. Twelve requests routed through
the replacement, and the receipt aggregates them into four measurable checks tied to one
id, `mig-2026-06-30-001`. That id survives an audit long after the migration is forgotten.
If a check failed — say the replacement returned a 600ms P95 — that row would flip red and
the disposition would block, and traffic would stay on the old model until you fixed it.
Keep the claim honest and scoped: across these twelve controlled requests the replacement
preserved the tested contract without observed disruption — that is what the receipt
proves, not a universal guarantee. This receipt says the swap is safe. It says nothing yet
about whether your *wider service* is ready to scale.

### Step 2: Score readiness with a production audit

**Goal:** Migration proved the replacement path; now score the whole service across five
dimensions and quantify exactly where readiness is weak — not a gut feel, scored evidence
with the gap counted.

```bash
.venv/bin/python scripts/readiness_audit.py --format rich
```

**Expected output:** the **PRODUCTION READINESS AUDIT** table — scalability `4/4 READY`,
observability `4/4 READY`, security `2/4 🔴 GAP`, cost_efficiency `3/4 READY`, reliability
`4/4 READY`, `TOTAL 17/20  4/5 READY`. Then the **⚠️ BLOCKING GAP DETAIL** box: security
PII redaction covers `62%` — `Verified 1,240 / 2,000`, `Unverified 760 / 2,000 (38%) ← NO
REDACTION PROOF`, the example `cust-102317 → cust-XXX317`, `Required ≥ 95%`, `Gap +33
percentage points`, and the `ACTION: scale blocked until sampling coverage reaches 95%+`.

**What the learner should notice:** The most valuable number on this screen is the one that
is not green. Four dimensions are production-ready, backed by real controls you built. But
security scores a two, and the audit does not leave that abstract — it counts it.
Twelve-hundred-forty requests out of two thousand have verified redaction; seven-hundred-
sixty do not. That thirty-eight percent has no proof sensitive data was caught. Here is the
trap teams fall into: a passing *sample* feels like a passing *system*, but sampled evidence
only covers sampled traffic. The other thirty-eight percent could be clean, or leaking PII
on every request — you do not know. The audit does not guess. It quantifies the gap (`+33
points`) and names the action (reach 95% coverage, via inline redaction or a higher sample
rate). A seventeen-out-of-twenty with a counted gap beats a fake twenty every time. The
audit scored your dimensions; it still cannot tell you which deployment pattern fits.

### Step 3: Derive the deployment from workload evidence and prove the runbook fires

**Goal:** Derive the deployment pattern from a *measured* workload, inspect the runbook as a
real artifact, then break the system on purpose — inject a latency spike past the SLO and
watch the runbook alert fire with its scale-out action.

```bash
.venv/bin/python scripts/workload_decision.py --sample-minutes 15 --latency-target 500
sed -n '/^controls:/,$p' docs/runbook.yaml          # the runbook is a real file — inspect its controls
# Now BREAK IT: inject a p95 spike above the 2500ms SLO, then read the alert the runbook fired
curl -s -X POST "http://localhost:8000/admin/inject-latency?p95_ms=2600&duration_s=90" | jq .
sleep 5 && curl -s http://localhost:8000/admin/alerts | .venv/bin/python scripts/ops_view.py --type alert
```

**Expected output:** first the **WORKLOAD PROFILE** panel — `Average RPS 9.8`, `Peak 11.2`,
`P95 420 ms`, `Latency Target 500 ms`, `Headroom 80 ms ← THIN`, `Cold-Start Penalty 1800 ms
← 3.6x OVER TARGET` — then the pattern table: `serverless 🔴 VIOLATES TARGET`, `containers
🟢 RECOMMENDED`, `dedicated_gpu 🟡 OVERKILL @ 10RPS`, and ★ `DECISION: containers`. Then the
runbook `controls:` block from `docs/runbook.yaml`. Then, after the injected breach, the
**🚨 RUNBOOK ALERT FIRED** box — `Alert p95_latency_breach`, `Measured 2600 ms`, `Threshold
2500 ms`, `Action Taken 🟢 scale_out_triggered (target 30 RPS)`, with the escalation,
diagnosis path, and rollback target.

**What the learner should notice:** Watch the order — the numbers come first, the decision
falls out of them. The profile is *measured*: 9.8 RPS, a p95 of 420ms against a 500ms
*deployment target* (the interactive latency this service needs, distinct from the wider
2500ms operational SLO the runbook monitors). The killer number is the cold-start penalty —
1800ms, 3.6× the target — which eliminates scale-to-zero serverless before the conversation
starts. Dedicated GPU is warm and fast but unjustified at ten RPS; containers win because
their strengths line up with *this* evidence. Then the part most demos skip: proving the
runbook. The runbook is a real file — `docs/runbook.yaml`, its controls readable by any
on-call engineer. Inject a p95 of 2600ms, past the 2500ms SLO, and the alert fires *live*:
`scale_out_triggered`. That is not a canned response — inject `2400ms` instead
(`?p95_ms=2400`) and nothing fires, because the control is a real threshold, not a
screenshot. A runbook that executes in front of you is a runbook; a document nobody opens
during an incident is not.

### Step 4: Check maturity and name the gaps honestly

**Goal:** Place the system on the maturity ladder from the accumulated evidence, list the
seven proven capabilities, and name the three gaps to scale-ready — each with the concrete
investment it needs.

```bash
.venv/bin/python scripts/maturity_check.py --format rich
```

**Expected output:** the **MATURITY ASSESSMENT** — `Current Level: 🟡 MANAGED-PRODUCTION`
with the ladder marking `▲ YOU ARE HERE`; **PROVEN CAPABILITIES**, seven `✅` rows
(observability, resilience, prompt versioning, canary release, cost tracking, model
migration, runbook execution); and **GAPS BLOCKING SCALE-READY**, three `🔴` rows each with
its investment — PII redaction `62% → 95%` (inline redaction or 2× sample rate),
load-test `30 RPS proven → prove 100 RPS` (a 4-hour soak test), and single-region → a
replica region plus a failover drill. Closes on `DISPOSITION: MANAGED_PRODUCTION`.

**What the learner should notice:** Managed production — not prototype, not scale-ready. The
ladder shows exactly where you stand. Read the green section first: seven capabilities
proven, and every one carries receipts you can audit — including the migration and the
runbook alert you fired minutes ago. Then the red section: three gaps block scale-ready, and
each names the *investment*, not just the shortfall. PII coverage at 62% — inline redaction
or double the sample rate, then re-audit after seven days. Load-test ceiling at 30 RPS —
schedule a four-hour soak at 100 RPS and verify autoscale and circuit-breaker behavior under
sustained pressure. Single-region — deploy a replica region, run a failover drill, prove
receipt continuity. That is what separates an honest maturity assessment from a slide that
says "we're production-ready." Maturity is raised by closing evidence gaps, not by wishing.
When someone asks "are we ready to scale," you point at this table: here is what is proven,
here is what is missing, and here is what closing each gap costs.

## Preflight check

```bash
bash module3/scripts/m3-demo6-readiness-audit-runbook.preflight.sh
```

Runs every step above (activating the migration, sending the twelve requests, scoring the
audit, deriving the deployment, injecting the breach, and reading the maturity), asserts the
output proves the learning objectives, and writes a readable log to
`preflight-logs/m3-demo6-readiness-audit-runbook.log`. Expect `PASS: 4  FAIL: 0`.

## Cleanup

```bash
./scripts/module3-demo-reset.sh
```

## Key files

- `app/lifecycle/migration.py` — the deterministic replacement-adapter migration:
  `/admin/deprecate`, `/v1/completions` routing, and the aggregated `/receipts/migration`
- `app/lifecycle/readiness.py` — the deterministic audit (with the quantified PII gap),
  the workload/decision/patterns, the runbook, the breach/alert, and the maturity decision
  (seven proven capabilities + investment-named gaps)
- `config/deployment.yaml` — the measured workload profile and pattern criteria that
  `workload_decision.py` reads
- `docs/runbook.yaml` — the operational runbook (thresholds + trigger→action controls),
  inspected in Step 3
- `scripts/readiness_audit.py` / `workload_decision.py` / `maturity_check.py` / `ops_view.py`
  — the rich CLIs that render the audit, the deployment decision, the maturity, and the
  receipt/alert
- `scripts/migration-traffic.js` — the k6 script that sends the twelve migration requests
- `app/main.py` — the `/admin/deprecate`, `/v1/completions`, `/receipts/migration`,
  `/admin/inject-latency`, `/admin/alerts`, and `/lifecycle/readiness/*` endpoints
