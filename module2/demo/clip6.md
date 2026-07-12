# Module 2 — Demo: Diagnose Latency, Quota Pressure, Cost Drift, and Quality Regression

> **Status: planned.** Scaffolded from the course outline; not yet built.

## What This Demo Will Prove

Given a controlled incident profile, the operator uses Grafana, traces, logs, and
receipts to find the first bad signal, isolate the source (queueing, provider
latency, retry, or fallback), connect it to model identity / tokens / cost /
quality, and choose an evidence-based action: scale, shed load, fail over, roll
back, or tune quality gates.

## Learning Objectives Covered

| LO | Description |
|----|-------------|
| TO2 | Build resilient GenAI integrations using queuing, rate limiting, and fallback |
| EO2e | Test resilience by simulating failures, latency spikes, and quota exhaustion |
| TO3 | Establish observability through tracing, structured logging, and quality monitoring |
| EO3a–e | Tracing, logging, quality sampling, SLOs, and incident diagnosis |

## Planned Steps

1. Trigger a controlled incident profile with a latency spike, quota pressure, cost drift, or quality regression.
2. Use Grafana to identify the first bad signal and the affected model or request class.
3. Follow traces to isolate whether the delay came from queueing, provider latency, retry, or fallback.
4. Use logs and receipts to connect model identity, token usage, cost estimate, and quality status.
5. Choose the operator action — scale, shed load, fail over, roll back, or tune quality gates — based on the evidence.

## Next

Module 3 — Operating LLMOps change and production readiness.
