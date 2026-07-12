# Module 1 — Demo: Validate Routing Receipts, Counters, and Final Disposition

> **Status: planned.** Scaffolded from the course outline; this demo is not yet
> built.

## What This Demo Will Prove

Run a mixed batch that exercises all three routing policies — weighted,
payload-based, and override-driven — then reconcile the three sources of truth:
the live API responses, the Redis counters (aggregate behavior), and the
PostgreSQL receipts (durable per-request record). The operator decision is
confirmed only when policy, receipt, and observed model behavior agree.

## Learning Objectives Covered

| LO | Description |
|----|-------------|
| TO1 | Implement load balancing and intelligent request routing for multi-model GenAI service architectures |
| EO1a | Dedicated AI service layer that decouples app logic from providers |
| EO1b | Weighted load balancing across model tiers |
| EO1c | Payload-based routing to appropriate tiers |
| EO1d | Weighted vs deterministic trade-offs |

## Planned Steps

1. Run a mixed request batch with weighted, payload-based, and override-driven examples.
2. Compare API responses with Redis counters to prove routing behavior at the aggregate level.
3. Query PostgreSQL receipts for request ID, policy name, provider, latency target, token estimate, cost estimate, and quality score.
4. Confirm the operator decision only when policy, receipt, and model behavior agree.

## Next

Module 2 — Protecting and observing GenAI reliability.
