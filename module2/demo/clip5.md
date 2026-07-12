# Module 2 — Demo: Prove Traces, Logs, Metrics, and Quality Sampling

> **Status: planned.** Scaffolded from the course outline; not yet built.

## What This Demo Will Prove

A single request is observable end to end: a distributed trace spans ingress →
queue → routing → provider call → retry → fallback → response; structured logs
carry request id, model identity, route reason, tokens, cost, latency, and
provider status; Prometheus/Grafana show the service SLOs; and output quality
sampling separates a successful response from a trustworthy one.

## Learning Objectives Covered

| LO | Description |
|----|-------------|
| EO3a | Distributed tracing across application, AI service, and model provider layers |
| EO3b | Structured logging schema (inputs, outputs, model, latency, tokens, cost) |
| EO3c | Production output quality sampling on a representative subset |
| EO3d | SLOs for latency, availability, and output quality, with alerting |
| EO3e | Use observability data to diagnose incidents |

## Planned Steps

1. Open a trace across ingress, queue, routing, provider call, retry, fallback, and response.
2. Inspect structured logs for request id, model identity, route reason, tokens, cost, latency, and provider status.
3. Show Prometheus metrics for latency, availability, queue depth, fallback rate, retry rate, and cost estimate.
4. Run output quality sampling and inspect schema, policy, and reviewer reasons.
5. Confirm SLO alert rules cover latency, availability, and output quality dimensions.
6. Diagnose root cause by opening a slow trace span, inspecting nested timings, and matching provider logs to the latency source.
7. Use structured logs to correlate token count, cost estimate, quality status, and the operator action.

## Next

Diagnose latency, quota pressure, cost drift, and quality regression.
