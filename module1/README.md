# Module 1 — Scaling GenAI Traffic with FastAPI Routing Controls

**Terminal objective (TO1):** Implement load balancing and intelligent request
routing for multi-model GenAI service architectures. · **30 minutes**

## Clips

| # | Title | Type | Length | Learning objectives | Runbook |
|---|-------|------|--------|---------------------|---------|
| 1 | AI service layer and routing contracts | Presentation | 3 min | TO1, EO1a | — |
| 2 | Build the FastAPI provider adapter layer | **Demo** | 6 min | TO1, EO1a | [demo/clip2.md](demo/clip2.md) ✅ |
| 3 | Prove weighted routing across model tiers | **Demo** | 6 min | EO1b | [demo/clip3.md](demo/clip3.md) ✅ |
| 4 | Routing policy tradeoffs and operator decisions | Presentation | 3 min | EO1b, EO1c, EO1d | — |
| 5 | Prove payload-based routing and deterministic overrides | **Demo** | 6 min | EO1c, EO1d | [demo/clip5.md](demo/clip5.md) ✅ |
| 6 | Validate routing receipts, counters, and final disposition | **Demo** | 6 min | TO1, EO1a–d | [demo/clip6.md](demo/clip6.md) _(planned)_ |

Clips 1 and 4 are presentation, not demos.

## Learning Objectives

| LO | Description |
|----|-------------|
| EO1a | Design a dedicated AI service layer that decouples application logic from model provider dependencies and enables independent scaling |
| EO1b | Implement weighted load balancing across multiple AI models to distribute requests according to cost and latency targets |
| EO1c | Apply payload-based routing to direct requests to appropriate model tiers based on input characteristics such as length or complexity |
| EO1d | Evaluate the trade-offs between weighted distribution and deterministic routing strategies for different traffic patterns and cost profiles |

## Run a demo

```bash
bash module1/scripts/demo_up.sh      # readiness check + start FastAPI/Redis/PostgreSQL (auto-starts Docker)
# follow demo/clip2.md, demo/clip3.md, or demo/clip5.md
bash module1/scripts/demo_down.sh    # stop the stack when finished
```

Reset to a clean state at any time while the stack is up:

```bash
./scripts/module1-demo-reset.sh
```

## Scripts

`module1/scripts/` — `demo_up.sh`, `demo_down.sh`, `capture_demo_output.sh`, and a
preflight per demo clip (`preflight_check.sh` for Clip 2, `clip3_preflight_check.sh`
for Clip 3, `clip5_preflight_check.sh` for Clip 5) that runs every step, asserts
each learning objective, and writes a readable log.
