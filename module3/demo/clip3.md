# Module 3 — Demo: Validate Model Updates Against Quality Baselines

> **Status: planned.** Scaffolded from the course outline; not yet built.

## What This Demo Will Prove

A candidate model is gated by a Pytest baseline covering quality, latency, cost,
failure rate, and output-contract compliance. A passing candidate stays inside
promotion thresholds; a failing one is blocked on quality, latency, cost, or
contract drift — and cannot become the default without meeting the baseline.

## Learning Objectives Covered

| LO | Description |
|----|-------------|
| EO4b | Model update validation workflow that tests candidates against quality and performance baselines before promotion |

## Planned Steps

1. Run Pytest baseline validation for candidate model quality, latency, cost, failure rate, and output-contract compliance.
2. Inspect the baseline report and compare candidate results against the approved model version.
3. Show a passing case where quality and performance stay inside promotion thresholds.
4. Show a failing case where quality, latency, cost, or contract drift blocks promotion.
5. Record the release decision and prove the candidate cannot become default without meeting baseline criteria.

## Next

Prove canary promotion, hold, and rollback decisions.
