# Module 2 — Demo: Prove Queues, Rate Limits, and Fail-Fast Behavior

> **Status: planned.** Scaffolded from the course outline; not yet built.

## What This Demo Will Prove

Under a controlled k6 spike, the service absorbs the burst in a queue, applies
configurable rate limits per provider / tier / request class, and fails fast with
HTTP 429 when capacity is exceeded — with every accepted, delayed, and rejected
request distinguishable in receipts and logs.

## Learning Objectives Covered

| LO | Description |
|----|-------------|
| TO2 | Build resilient GenAI integrations using queuing, rate limiting, and automatic fallback |
| EO2a | Request queue with configurable rate limits that absorbs spikes and prevents quota exhaustion |
| EO2b | Fail-fast pattern that rejects at capacity with appropriate error responses |
| EO2e | Test resilience by simulating spikes and quota exhaustion in a controlled environment |

## Planned Steps

1. Run controlled k6 spike traffic against the local GenAI service.
2. Inspect Redis queue depth and prove the backlog rises above zero during load.
3. Inspect rate-limit state and compare the current count against the configured threshold.
4. Trigger rate-limit decisions by provider, model tier, and request class.
5. Exceed queue capacity and prove HTTP 429 returns "Queue capacity exceeded" with a PostgreSQL rejected-request receipt.
6. Query receipts and logs to distinguish accepted, delayed, and rejected requests.

## Next

Circuit breaker fallback and retry backoff.
