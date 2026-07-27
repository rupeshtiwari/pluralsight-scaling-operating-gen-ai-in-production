# Module 1 — Scaling GenAI Traffic with FastAPI Routing Controls

**Terminal objective (TO1):** Implement load balancing and intelligent request
routing for multi-model GenAI service architectures. · **30 minutes**

## Demos

| # | Title | Length | Learning objectives | Runbook |
|---|-------|--------|---------------------|---------|
| 2 | Build the FastAPI provider adapter layer | 6 min | TO1, EO1a | [demo/m1-demo1-provider-adapter-layer.md](demo/m1-demo1-provider-adapter-layer.md) ✅ |
| 3 | Prove weighted routing across model tiers | 6 min | EO1b | [demo/m1-demo2-weighted-routing.md](demo/m1-demo2-weighted-routing.md) ✅ |
| 5 | Prove payload-based routing and deterministic overrides | 6 min | EO1c, EO1d | [demo/m1-demo3-payload-routing-and-overrides.md](demo/m1-demo3-payload-routing-and-overrides.md) ✅ |
| 6 | Validate routing receipts, counters, and final disposition | 6 min | TO1, EO1a–d | [demo/m1-demo4-routing-receipts-and-disposition.md](demo/m1-demo4-routing-receipts-and-disposition.md) ✅ |

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
# follow demo/m1-demo1-provider-adapter-layer.md, demo/m1-demo2-weighted-routing.md, or demo/m1-demo3-payload-routing-and-overrides.md
bash module1/scripts/demo_down.sh    # stop the stack when finished
```

Reset to a clean state at any time while the stack is up:

```bash
./scripts/module1-demo-reset.sh
```

## Scripts

`module1/scripts/` — `demo_up.sh`, `demo_down.sh`, `capture_demo_output.sh`, and a
preflight per demo (`m1-demo1-provider-adapter-layer.preflight.sh`,
`m1-demo2-weighted-routing.preflight.sh`,
`m1-demo3-payload-routing-and-overrides.preflight.sh`, and
`m1-demo4-routing-receipts-and-disposition.preflight.sh`) that runs every step,
asserts each learning objective, and writes a readable log.
