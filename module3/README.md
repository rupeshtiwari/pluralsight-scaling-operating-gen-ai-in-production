# Module 3 — Operating LLMOps Change and Production Readiness

**Terminal objectives:** TO4 — Apply LLMOps practices to manage the operational
lifecycle of prompts and models · TO5 — Assess GenAI systems against production
readiness criteria and establish operational practices. · **30 minutes**

> **Status: planned.** This module is scaffolded from the course outline. The
> demo runbooks are stubs until the module is built.

## Clips

| # | Title | Type | Length | Learning objectives | Runbook |
|---|-------|------|--------|---------------------|---------|
| 1 | LLMOps release gates and production readiness | Presentation | 3 min | TO4, EO4a, EO4b, TO5, EO5a | — |
| 2 | Prove prompt versioning and reproducible rollback | **Demo** | 6 min | TO4, EO4a | [demo/clip2.md](demo/clip2.md) _(planned)_ |
| 3 | Validate model updates against quality baselines | **Demo** | 6 min | EO4b | [demo/clip3.md](demo/clip3.md) _(planned)_ |
| 4 | Canary, deprecation, and readiness decision logic | Presentation | 3 min | EO4c, EO4d, EO5a–d | — |
| 5 | Prove canary promotion, hold, and rollback decisions | **Demo** | 6 min | EO4c | [demo/clip5.md](demo/clip5.md) _(planned)_ |
| 6 | Run readiness audit and finalize operational runbook proof | **Demo** | 6 min | EO4d, TO5, EO5a–d | [demo/clip6.md](demo/clip6.md) _(planned)_ |

Clips 1 and 4 are presentation, not demos.

## Learning Objectives

| LO | Description |
|----|-------------|
| EO4a | Prompt version control enabling reproducible experiments and safe rollback |
| EO4b | Model update validation workflow that tests candidates against quality/performance baselines |
| EO4c | Canary deployment with controlled blast radius and defined promotion criteria |
| EO4d | Manage upstream model deprecations with minimal disruption |
| EO5a | Evaluate architecture against readiness criteria (scalability, observability, security, cost, reliability) |
| EO5b | Select cloud-native deployment patterns (serverless, containers, dedicated GPU) by latency/throughput |
| EO5c | Construct an operational runbook (deploy, monitoring thresholds, incident response, capacity) |
| EO5d | Identify the operational maturity progression from prototype to production scale |
