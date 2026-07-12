# Module 3 — Demo: Prove Canary Promotion, Hold, and Rollback Decisions

> **Status: planned.** Scaffolded from the course outline; not yet built.

## What This Demo Will Prove

A canary shifts ten percent of eligible traffic to a new prompt+model combination
under watch. It is promoted only when quality, latency, cost, error rate, and
output-contract criteria pass and the receipt trail proves bounded exposure — and
held or rolled back the moment a signal breaches threshold, returning production
to the approved release.

## Learning Objectives Covered

| LO | Description |
|----|-------------|
| EO4c | Canary deployment with controlled blast radius and defined promotion criteria |

## Planned Steps

1. Shift ten percent of eligible traffic to a canary prompt and model combination.
2. Watch canary metrics for quality, latency, cost, error rate, and output-contract compliance.
3. Promote the canary only when criteria pass and the receipt trail proves bounded exposure.
4. Hold or roll back when a quality or latency signal breaches the promotion threshold.
5. Confirm production traffic returns to the approved prompt and model release after rollback.

## Next

Run readiness audit and finalize operational runbook proof.
