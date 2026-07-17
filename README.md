# Scaling & Operating Gen AI in Production

**[Watch on Pluralsight](https://www.pluralsight.com/courses/scaling-operating-gen-ai-in-production)**

Learn how to take a GenAI feature from a working prototype to a service that
survives real traffic: intelligent multi-model routing, resilience under
provider failure, production observability, safe prompt/model change, and
operational readiness. You'll scale and operate a production-style GenAI service
with routing, resilience, observability, LLMOps, and runbook-driven operations.

This repository contains a single **FastAPI AI service layer** with progressive
production controls that you enable module by module. **No cloud API keys
required** — everything runs locally with deterministic provider stubs that
simulate healthy, slow, error, quota, quality, and deprecation conditions.

## Table of Contents

- [Learning Objectives](#learning-objectives)
- [Demos — Start Here](#demos--start-here)
- [One-Time Setup](#one-time-setup)
- [How Demos Work](#how-demos-work)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Learning Objectives Coverage](#learning-objectives-coverage)
- [Production Concerns Coverage](#production-concerns-coverage)
- [API Reference](#api-reference)
- [Project Structure](#project-structure)
- [Key References](#key-references)

## Learning Objectives

By the end of all three modules, you will be able to:

| # | Terminal Objective | What You Do |
|---|--------------------|-------------|
| T1 | Implement load balancing and intelligent request routing for multi-model GenAI service architectures | Put three model tiers behind one adapter contract, route by weight and payload, prove each decision with a receipt |
| T2 | Build resilient GenAI integrations using queuing, rate limiting, and automatic fallback | Absorb spikes with a queue, fail fast at capacity, trip a circuit breaker, retry with backoff, fail over to a healthy model |
| T3 | Establish observability through distributed tracing, structured logging, and output quality monitoring | Trace a request end to end, read structured logs, watch Prometheus/Grafana, sample output quality, alert on SLOs |
| T4 | Apply LLMOps practices to manage the operational lifecycle of prompts and models | Version prompts, validate model updates against baselines, run a canary, manage provider deprecation |
| T5 | Assess GenAI systems against production readiness criteria and establish operational practices | Run a readiness audit, choose a deployment pattern, finalize an operational runbook |

## Demos — Start Here

Each module contains hands-on demos. Follow the README inside each module folder —
it has copy-paste commands, expected-output tables, and an explanation for every
step.

| Module | Demo | What You Prove | README |
|--------|------|----------------|--------|
| 1 ✅ | Multi-Model Routing | Put three model tiers behind one adapter contract → route by weight (prove the 10/6/4 spread straight from Redis) → route by declared complexity with deterministic overrides in both directions → back every decision with a PostgreSQL receipt → reconcile a mixed batch across API, Redis, and receipts into one operator disposition | [module1/README.md](module1/README.md) |
| 2 | Resilience & Observability | Absorb spikes with a queue → fail fast at capacity → trip a circuit breaker → retry with backoff → fail over to a healthy model → trace, log, and measure it end to end _(planned)_ | module2/README.md |
| 3 | LLMOps & Readiness | Version prompts → validate a model update against a baseline → run a canary → manage deprecation → audit production readiness and finalize a runbook _(planned)_ | module3/README.md |

**Start with Module 1.** Each module builds on the same service layer.

## One-Time Setup

Run once from the project root, on macOS, before any demo:

```bash
bash environment-setup/setup.sh
```

This single installer auto-installs every dependency the demos use — Homebrew,
Docker Desktop (with Compose), Python 3.13, tmux, jq, curl, and psql — then
builds the virtual environment with the pinned Python packages and writes a
verbose readiness log to `environment-setup/setup_log.txt`. When it finishes
green, your Mac is ready.

To check what you already have without installing anything, run
`bash scripts/ensure-ready.sh` — it prints ✔ / ✗ for each tool with a fix for
anything missing.

Prefer to do it by hand:

```bash
python3.13 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

## How Demos Work

Start a module's stack, then run its steps from the runbook:

```bash
bash module1/scripts/demo_up.sh     # readiness check → starts FastAPI + Redis + PostgreSQL, waits healthy, opens tmux
# ... run the Step 1–6 commands from module1/demo/clip2.md ...
bash module1/scripts/demo_down.sh   # tears the stack down
```

`demo_up.sh` first runs `scripts/ensure-ready.sh`, which verifies every required
tool and **auto-starts Docker Desktop** if it's installed but not open (waiting
until the daemon is ready) — so you don't hit "Docker daemon not running" mid
demo. You can also run that check on its own: `bash scripts/ensure-ready.sh`.

The `api` container mounts the source (`./app`) and runs with `--reload`, so
after a `git pull` the running service reflects the new code **immediately** —
no rebuild or restart. Rebuild (`docker compose up -d --build`) is only needed
when `requirements.txt` changes.

Every demo command pipes JSON into `scripts/fmt.py`, which renders it in the
Pluralsight brand palette so only what the narration reads is on screen:

```
┌────────────────────────────────────────────────────────────────────────┐
│ <what this step shows>                                                   │  ← white heading (the runbook step)
│ <why we show it>                                                         │  ← blue "why" line
└────────────────────────────────────────────────────────────────────────┘
  ★ selected_model: balanced-std      ← pink ★ marks the fields to read aloud
  ★ provider_status: healthy          ← green = healthy/safe, pink = unsafe/blocked
  ★ token_estimate: prompt=17  completion=10  total=27
```

Full values are always shown (never truncated), each highlighted field sits on
its own line, and the header box states **what** you're looking at and **why**.

Author validation, per module:

```bash
bash module1/scripts/preflight_check.sh      # runs every step, asserts each LO, writes a readable log
bash module1/scripts/capture_demo_output.sh  # plain-text transcript of commands + output
./scripts/module1-demo-reset.sh              # reset to a clean, repeatable state
```

## Architecture

```
Application code
      │
      ▼
┌───────────────────────────────────────────────────────────────┐
│  FastAPI AI Service Layer  (the decoupling boundary)           │
│                                                                │
│  Routing policy → Provider adapter (deterministic stub)        │
│    · baseline · weighted · payload-based · deterministic       │
│                                                                │
│  [M2] Queue → Rate limit → Circuit breaker → Retry → Fallback  │
│  [M2] Tracing · structured logs · metrics · quality sampling   │
│  [M3] Prompt/model versioning · canary · deprecation           │
└───────────────────────────────────────────────────────────────┘
      │                          │
      ▼                          ▼
  Redis                     PostgreSQL
  (live provider            (normalized request
   conditions, counters)     receipts — decoupling proof)
```

**The service boundary decouples four concerns** so each scales and changes
independently:

- **Application ↔ Service layer** — callers depend on one adapter contract and a
  normalized receipt, never on a provider SDK or response shape (T1).
- **Service layer ↔ Providers** — deterministic stubs stand in for model
  providers; routing, fallback, and readiness are exercised with no external
  calls (T1, T2).
- **Service layer ↔ Observability** — traces, logs, metrics, and quality samples
  make behavior visible (T3).
- **Service layer ↔ Operations** — versioning, canary, readiness audits, and
  runbooks govern change (T4, T5).

## Tech Stack

| Component | Version | Purpose |
|-----------|---------|---------|
| Python | 3.13 | Runtime (recording baseline) |
| FastAPI | 0.139.0 | AI service layer / web framework |
| Uvicorn | 0.50.1 | ASGI server |
| Redis | 8 (client 8.0.1) | Live provider conditions and routing counters |
| PostgreSQL | 18 (psycopg 3.3.4) | Normalized request receipts |
| OpenTelemetry | 1.43.0 | Distributed tracing |
| Prometheus | 3.11.2 (client 0.25.0) | Metrics |
| Grafana | 11.1.4+ | Dashboards |
| Grafana k6 | 1.0+ | Controlled load and spike traffic |
| Docker Desktop | 4.44.3+ | Full local environment |
| pytest | 9.1.1 | Tests |

All package and container versions are pinned in `requirements.txt` and
`docker-compose.yml`.

## Learning Objectives Coverage

| LO | Description | Module | Demo Proof Point |
|----|-------------|--------|------------------|
| EO1a | Dedicated AI service layer that decouples app logic from providers | 1 | Uniform adapter contract + provider-agnostic PostgreSQL receipt |
| EO1b | Weighted load balancing across model tiers | 1 | ✅ Policy shows weight + latency target + cost per tier; `redis-cli HGETALL` proves the 10/6/4 (50/30/20) spread directly; validation confirms observed == configured |
| EO1c | Payload-based routing to appropriate tiers | 1 | ✅ Declared complexity (separate from prompt size) selects the tier; token estimate + complexity + cost shown and persisted per request |
| EO1d | Weighted vs deterministic trade-offs | 1 | ✅ Overrides bypass the decision in both directions (bulk→economy, legal→premium); `would_have_selected` + Redis `weighted: 0` prove the bypass |
| EO2a–e | Queue, fail-fast, circuit breaker, retry backoff, resilience testing | 2 | ✅ Real k6 spike + atomic Redis admission (429 + Retry-After), circuit states, deterministic backoff, incident shed |
| EO3a–e | Tracing, logging schema, quality sampling, SLOs, incident diagnosis | 2 | ✅ OpenTelemetry spans, structured logs, Prometheus `/metrics` + Grafana board, SLO alerts, root-cause incident diagnosis |
| EO4a–d | Prompt versioning, model validation, canary, deprecation | 3 | Version rollback, baseline gate, canary promotion _(planned)_ |
| EO5a–d | Readiness criteria, deployment patterns, runbook, maturity | 3 | Readiness audit, deployment decision, runbook _(planned)_ |

## Production Concerns Coverage

| Concern | Module | What You See |
|---------|--------|--------------|
| Provider coupling | 1 | One adapter contract; app never sees a vendor payload |
| Traffic distribution & cost | 1 | Weighted + payload routing balances cost and latency _(planned)_ |
| Overload & quota exhaustion | 2 | Queue absorbs bursts; fail-fast returns 429 at capacity _(planned)_ |
| Provider failure | 2 | Circuit breaker + fallback route to a healthy model _(planned)_ |
| Blind spots | 2 | Traces, logs, metrics, and quality sampling _(planned)_ |
| Unsafe change | 3 | Prompt/model versioning, baseline gates, canary _(planned)_ |
| Deprecation | 3 | Adapter compatibility + receipt-backed migration _(planned)_ |
| Operational readiness | 3 | Readiness audit, deployment choice, runbook _(planned)_ |

## API Reference

Endpoints available today (Module 1 and Module 2 complete). More are added as
later modules land.

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Stack readiness — FastAPI, Redis, PostgreSQL, provider stubs |
| `/providers` | GET | Provider adapter contract for every model tier |
| `/providers/{model}/probe` | GET | Deterministic local simulation (zero external calls) |
| `/providers/conditions` | GET | Active + supported provider condition matrix |
| `/route` | POST | Route a request; returns the decision and writes a receipt |
| `/receipts` | GET | Normalized request receipts |
| `/admin/reset` | POST | Reset to a clean state (clear receipts + counters, all conditions healthy) |
| `/routing/policy` | GET | Weighted routing policy — per-tier weights |
| `/route/batch` | POST | Route N requests under the weighted policy |
| `/routing/last-batch` | GET | Individual decisions from the last batch |
| `/routing/counters` | GET | Per-tier distribution counters (Redis) |
| `/routing/validate` | GET | Observed distribution vs configured weights |
| `/routing/rules` | GET | Payload-based routing rules — complexity buckets + override classes |
| `/route/smart` | POST | Route a request by declared complexity, honouring deterministic overrides |
| `/routing/smart-counters` | GET | Decision-dimension counters (complexity vs override; weighted bypassed) |
| `/routing/smart-validate` | GET | Confirm every canonical payload lands on its expected tier |
| `/route/mixed` | POST | Run one mixed batch — weighted + payload + override — and tally by kind |
| `/routing/mixed-batch` | GET | Individual decisions from the mixed batch, tagged by kind |
| `/routing/mixed-counters` | GET | Per-kind mixed-batch counters (Redis) |
| `/routing/disposition` | GET | Reconcile API + Redis + receipts → CONFIRMED / BLOCKED |
| `/resilience/limits` | GET | Admission-control config — per provider/tier/class rate limit, window, queue capacity |
| `/load/submit` | POST | Atomically admit one request; HTTP 429 + Retry-After when the queue is full |
| `/load/spike` | POST | Deterministic internal spike over the same atomic path (preflight helper) |
| `/resilience/queue` | GET | The real queue for a tier — the list of queued request IDs + depth (Redis) |
| `/resilience/rate-limit` | GET | Live rate-limit window for a tier — admitted vs limit, with window (Redis) |
| `/resilience/matrix` | GET | Same burst across every provider key — each sheds at its own limit |
| `/resilience/dispositions` | GET | Receipts grouped by disposition — accepted / delayed / rejected |
| `/resilience/admission-logs` | GET | Structured admission logs + one request correlated across log and receipt |
| `/resilience/circuit-config` | GET | Circuit-breaker thresholds, fallback routes, and backoff schedule |
| `/resilience/drill` | POST | Run the deterministic breaker drill — closed → open → half-open → recovered |
| `/resilience/circuit` | GET | Per-request circuit state timeline from the drill |
| `/resilience/fallback` | GET | Fallback routing outcome — caller kept whole while the primary is unsafe |
| `/resilience/retry-log` | GET | Retry attempts, backoff schedule, and storm prevention |
| `/resilience/failover-reconcile` | GET | Reconcile caller + Redis + receipts → CONFIRMED / BLOCKED |
| `/observe/run` | POST | Run the observed batch — emit traces, record metrics, sample quality |
| `/observe/trace` | GET | One request's end-to-end span timeline |
| `/observe/logs` | GET | Structured logs — request id, model, tokens, cost, latency, status, quality |
| `/metrics` | GET | Real Prometheus exposition (scraped on the `obs` profile) |
| `/observe/metrics` | GET | Metrics summary — latency, availability, queue, fallback, retry, cost |
| `/observe/quality` | GET | Output quality sampling — schema, policy, reviewer reasons |
| `/observe/slo` | GET | SLO evaluation across latency, availability, quality → OK / ALERT |
| `/observe/diagnose` | GET | Slow-request root cause from nested span timings |
| `/observe/correlate` | GET | Tie one request's cost and quality to the operator action |
| `/incident/run` | POST | Trigger the controlled incident — one provider fault, four alerts |
| `/incident/alerts` | GET | Alert timeline in fire order — the first bad signal |
| `/incident/dashboard` | GET | Operator dashboard — latency, quota, cost, quality vs objectives |
| `/incident/isolate` | GET | Isolate the latency from one trace — provider vs queue/retry/fallback |
| `/incident/quota` | GET | Quota pressure and the 429 shed — admission control protecting the provider |
| `/incident/cost` | GET | Cost drift reconciled to its drivers on the degraded provider |
| `/incident/quality` | GET | Quality regression from sampling — grouped failure reasons |
| `/incident/action` | GET | Root cause + one evidence-based action per dimension |

## Project Structure

```
.
├── module1/                     Module 1: Scaling GenAI Traffic (routing)
│   ├── README.md                module index → 6 clips (2 presentation, 4 demo)
│   ├── demo/                     one runbook per demo clip
│   │   ├── clip2.md              adapter layer ✅
│   │   ├── clip3.md              weighted routing ✅
│   │   ├── clip5.md              payload routing & overrides ✅
│   │   └── clip6.md              receipts/counters disposition ✅
│   └── scripts/                 demo_up.sh, demo_down.sh, capture, preflight
├── module2/                     Module 2: Reliability + observability
│   ├── README.md                module index → 6 clips
│   ├── demo/                     clip2 ✅ · clip3 ✅ · clip5 ✅ · clip6 (planned)
│   └── scripts/                 demo_up.sh, demo_down.sh, clip2/clip3/clip5 preflight
├── module3/                     Module 3: LLMOps + readiness (planned)
│   ├── README.md                module index → 6 clips
│   └── demo/                     clip2, clip3, clip5, clip6 (planned)
│
├── app/                         FastAPI AI service layer
│   ├── main.py                  endpoints
│   ├── config.py                env-driven settings
│   ├── schemas.py               request/response contracts
│   ├── providers/               adapter contract, registry, deterministic stubs
│   ├── routing/                 routing policies
│   └── db/                      Redis + PostgreSQL clients
│
├── scripts/
│   ├── fmt.py                   Pluralsight-branded output formatter
│   ├── ensure-ready.sh          readiness check (auto-starts Docker Desktop)
│   └── module1-demo-reset.sh    clean-state reset for Module 1
│
├── data/payloads/               request payloads for the demos
├── docs/                        reusable operator artifacts
├── environment-setup/setup.sh   one installer for every dependency
├── requirements.txt             pinned dependencies
├── Dockerfile                   container build
└── docker-compose.yml           FastAPI + Redis + PostgreSQL
```

## Key References

| Framework / Tool | Version / Date | Where Used |
|------------------|----------------|------------|
| OpenTelemetry | 1.43.0 | Module 2 — distributed tracing |
| Prometheus + Grafana | 3.11.2 / 11.1.4+ | Module 2 — metrics and dashboards |
| Grafana k6 | 1.0+ | Module 2 — load and spike testing |
| SLOs / error budgets | — | Module 2 — latency, availability, quality objectives |
| Circuit breaker & retry patterns | — | Module 2 — resilience controls |
| Canary release | — | Module 3 — controlled prompt/model rollout |
| Cloud-native deployment patterns | — | Module 3 — serverless / containers / dedicated GPU trade-offs |
| Twelve-Factor / config-driven ops | — | All modules — env-driven service, no code changes across environments |
