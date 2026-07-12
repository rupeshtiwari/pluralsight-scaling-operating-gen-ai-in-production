# Module 1 — Scaling GenAI Traffic with FastAPI Routing Controls

Terminal objective **TO1**: Implement load balancing and intelligent request
routing for multi-model GenAI service architectures.

## Demos

The runbook for each demo clip lives in [`demo/`](demo/).

| Clip | Demo | Learning objectives | Runbook |
|------|------|---------------------|---------|
| 2 | Build the FastAPI provider adapter layer | TO1, EO1a | [demo/clip2.md](demo/clip2.md) |
| 3 | Prove weighted routing across model tiers | EO1b | [demo/clip3.md](demo/clip3.md) |
| 5 | Payload-based routing & deterministic overrides | EO1c, EO1d | [demo/clip5.md](demo/clip5.md) |
| 6 | Validate routing receipts, counters, disposition | TO1, EO1a–d | _planned_ |

Clips 1 and 4 are presentation, not demos.

## Run a demo

```bash
bash module1/scripts/demo_up.sh      # readiness check + start FastAPI/Redis/PostgreSQL (auto-starts Docker)
# follow demo/clip2.md or demo/clip3.md
bash module1/scripts/demo_down.sh    # stop the stack when finished
```

Reset to a clean state at any time while the stack is up:

```bash
./scripts/module1-demo-reset.sh
```

## Scripts

`module1/scripts/` — `demo_up.sh`, `demo_down.sh`, `capture_demo_output.sh`, and a
preflight per clip (`preflight_check.sh` for Clip 2, `clip3_preflight_check.sh`
for Clip 3, `clip5_preflight_check.sh` for Clip 5) that runs every step, asserts
each learning objective, and writes a readable log.
