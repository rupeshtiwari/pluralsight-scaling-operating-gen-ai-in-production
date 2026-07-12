# Module 2 — Demo: Prove Circuit Breaker Fallback and Retry Backoff

> **Status: planned.** Scaffolded from the course outline; not yet built.

## What This Demo Will Prove

With deterministic provider failure modes, the circuit breaker moves through
healthy → open → half-open → recovered with visible thresholds, fallback routes
traffic to a healthy alternative model, and retries use exponential backoff
without a retry storm — caller response, fallback receipt, and retry log all
agreeing on the outcome.

## Learning Objectives Covered

| LO | Description |
|----|-------------|
| EO2c | Circuit breaker that detects failures/slow responses and routes to healthy models |
| EO2d | Retry logic with exponential backoff suited to LLM inference latency |
| EO2e | Test resilience by simulating failures and latency spikes in a controlled environment |

## Planned Steps

1. Simulate slow responses, provider errors, and quota exhaustion with deterministic provider modes.
2. Show healthy, open, half-open, and recovered circuit states with thresholds visible.
3. Prove fallback routing sends traffic to a healthy alternative model when the primary is unsafe.
4. Inspect retry attempts and exponential backoff timing without creating a retry storm.
5. Validate that caller response, fallback receipt, and retry log agree on the same outcome.

## Next

Observability — traces, logs, metrics, and quality sampling.
