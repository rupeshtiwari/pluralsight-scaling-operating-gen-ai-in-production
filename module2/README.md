# Module 2 — Protecting and Observing GenAI Reliability

**Terminal objectives:** TO2 — Build resilient GenAI integrations using queuing,
rate limiting, and automatic fallback mechanisms · TO3 — Establish observability
through distributed tracing, structured logging, and output quality monitoring. ·
**30 minutes**

> **Status: in progress.** Clips 2, 3, and 5 are built and preflight-verified;
> Clip 6 is scaffolded from the course outline and lands next.

## Demos

| # | Title | Length | Learning objectives | Runbook |
|---|-------|--------|---------------------|---------|
| 2 | Prove queues, rate limits, and fail-fast behavior | 6 min | TO2, EO2a, EO2b, EO2e | [demo/clip2.md](demo/clip2.md) ✅ |
| 3 | Prove circuit breaker fallback and retry backoff | 6 min | EO2c, EO2d, EO2e | [demo/clip3.md](demo/clip3.md) ✅ |
| 5 | Prove traces, logs, metrics, and quality sampling | 6 min | EO3a–e | [demo/clip5.md](demo/clip5.md) ✅ |
| 6 | Diagnose latency, quota pressure, cost drift, and quality regression | 6 min | TO2, EO2e, TO3, EO3a–e | [demo/clip6.md](demo/clip6.md) _(planned)_ |

## Learning Objectives

| LO | Description |
|----|-------------|
| EO2a | Implement a request queue with configurable rate limits that absorbs traffic spikes and prevents downstream provider quota exhaustion |
| EO2b | Design a fail-fast pattern that rejects requests when queue capacity is exceeded, returning appropriate error responses to callers |
| EO2c | Build a circuit breaker that detects model failures and slow responses and automatically routes traffic to healthy alternative models |
| EO2d | Implement retry logic with exponential backoff appropriate for the latency characteristics of LLM inference workloads |
| EO2e | Test system resilience by simulating model failures, latency spikes, and quota exhaustion in a controlled environment |
| EO3a | Instrument a GenAI service with distributed tracing across application, AI service, and model provider layers |
| EO3b | Design a structured logging schema capturing inputs, outputs, model identity, latency, token usage, and cost per request |
| EO3c | Implement production output quality sampling on a representative subset of live responses |
| EO3d | Define SLOs covering latency, availability, and output quality, and configure alerting against them |
| EO3e | Use observability data to diagnose production incidents (performance degradation, cost spikes, quality regressions) |
