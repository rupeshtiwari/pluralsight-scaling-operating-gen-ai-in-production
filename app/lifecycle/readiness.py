"""Production readiness audit and operational runbook (Module 3, Clip 6).

The course finale ties the operational lifecycle together and grades the whole
system for production. It covers: managing an upstream model deprecation through a
replacement adapter with compatibility receipts (EO4d); a readiness audit across
scalability, observability, security, cost efficiency, and reliability (EO5a);
choosing a cloud-native deployment pattern by latency/throughput (EO5b); an
operational runbook for deploy, monitoring, incident response, rollback, and
capacity (EO5c); and an evidence-based maturity decision from prototype to
production scale (EO5d).

Everything is deterministic. The audit deliberately surfaces one real gap
(security), so the maturity decision has teeth and the runbook has something to
close — a readiness review that scores everything green teaches nothing.

What this proves: TO5 and EO4d, EO5a-d — assess a GenAI system against readiness
criteria and establish the operational practices that run it.
"""
from __future__ import annotations

_STATE: dict = {}


def run_readiness() -> dict:
    """Build the deterministic readiness state the /lifecycle/readiness/*
    endpoints read: deprecation migration, audit, deployment decision, pattern
    comparison, operational runbook, and maturity decision."""

    # --- EO4d: manage an upstream deprecation with minimal disruption -----
    # A deprecated model is retired behind the uniform adapter contract: traffic
    # routes to a replacement, and compatibility receipts prove the swap is safe.
    deprecation = {
        "deprecated_model": "balanced-std@2026-04",
        "replacement_model": "balanced-std@2026-06",
        "sunset_date": "2026-09-30",
        "adapter": "replacement adapter (uniform contract) — application code unchanged",
        "migrated_requests": 12,
        "compatibility": [
            {"check": "output_contract", "status": "pass"},
            {"check": "latency_within_slo", "status": "pass"},
            {"check": "cost_within_budget", "status": "pass"},
            {"check": "quality_within_bar", "status": "pass"},
        ],
        "disruption": "none",
        "disposition": "MIGRATED",
        "note": "the uniform adapter contract absorbs the deprecation — callers "
                "never change code, and compatibility receipts prove the swap is safe",
    }

    # --- EO5a: readiness audit across five dimensions --------------------
    # One honest gap (security) keeps the review meaningful.
    audit_rows = [
        {"dimension": "scalability", "score": 4, "max": 4, "status": "ready",
         "evidence": "request queue, per-tier rate limits, and a staged canary ramp"},
        {"dimension": "observability", "score": 4, "max": 4, "status": "ready",
         "evidence": "OpenTelemetry traces, Prometheus metrics, and SLO alerting"},
        {"dimension": "security", "score": 2, "max": 4, "status": "gap",
         "evidence": "secrets managed, but PII redaction sampling is not yet complete"},
        {"dimension": "cost_efficiency", "score": 3, "max": 4, "status": "ready",
         "evidence": "per-request cost tracked, tiered routing, and budget alerts"},
        {"dimension": "reliability", "score": 4, "max": 4, "status": "ready",
         "evidence": "circuit breaker, automatic fallback, and bounded retry backoff"},
    ]
    total = sum(r["score"] for r in audit_rows)
    max_total = sum(r["max"] for r in audit_rows)
    gaps = [r["dimension"] for r in audit_rows if r["status"] == "gap"]
    audit = {
        "rows": audit_rows,
        "score": total,
        "max_score": max_total,
        "ready_dimensions": sum(1 for r in audit_rows if r["status"] == "ready"),
        "gaps": gaps,
        "note": "four dimensions are production-ready; security is the one open "
                "gap, and naming it is what makes the audit honest",
    }

    # --- EO5b (decision): choose the deployment pattern for the workload --
    decision = {
        "workload": "steady ~10 RPS, latency-sensitive, cold start unacceptable",
        "recommended_pattern": "containers",
        "reasons": [
            "cold start is unacceptable, which rules out scale-to-zero serverless",
            "load is steady and predictable, so serverless burst scaling is unneeded",
            "10 RPS does not justify the cost of a dedicated GPU instance",
            "containers stay warm, autoscale for headroom, and keep ownership control",
        ],
        "note": "the deployment pattern follows the workload — steady, latency-"
                "sensitive traffic points at warm containers, not serverless or GPU",
    }

    # --- EO5b: compare the three patterns on the deciding factors --------
    patterns = {
        "chosen": "containers",
        "rows": [
            {"pattern": "serverless", "latency": "variable", "throughput": "burst",
             "warm_start": "cold starts", "ownership": "low (managed)",
             "fit": "no — cold starts violate the latency requirement"},
            {"pattern": "containers", "latency": "steady", "throughput": "high",
             "warm_start": "always warm", "ownership": "medium",
             "fit": "chosen — warm, autoscaling, right-sized for 10 RPS"},
            {"pattern": "dedicated_gpu", "latency": "lowest", "throughput": "very high",
             "warm_start": "always warm", "ownership": "high (ops burden)",
             "fit": "no — overkill and overpriced at 10 RPS"},
        ],
        "note": "serverless loses on cold starts, dedicated GPU is overkill at this "
                "load — containers are the right-sized choice",
    }

    # --- EO5c: the operational runbook -----------------------------------
    runbook = {
        "sections": [
            {"section": "deploy", "detail": "blue/green via the canary ramp "
             "(10 → 25 → 50 → 100%), each stage health-gated on the SLOs"},
            {"section": "monitoring", "detail": "p95 ≤ 2500ms, availability ≥ 99%, "
             "quality pass ≥ 90%, cost/req ≤ $0.015, error rate ≤ 1%"},
            {"section": "incident_response", "detail": "page on an availability or "
             "quality breach; diagnose trace → logs → receipts; fail over via the "
             "circuit breaker"},
            {"section": "rollback", "detail": "revert to the approved release id "
             "(prompt + model); drive canary exposure to 0"},
            {"section": "capacity", "detail": "baseline 10 RPS with headroom to 30 "
             "RPS; scale when queue depth > 20 or p95 > 2000ms"},
        ],
        "complete": True,
        "note": "every runbook section maps to a control the earlier demos built — "
                "the runbook is not aspirational, it is wired to real signals",
    }

    # --- EO5d: the maturity decision -------------------------------------
    maturity = {
        "levels": ["prototype", "managed_production", "scale_ready"],
        "current": "managed_production",
        "evidence": [
            "observability, resilience, prompt/model versioning, canary release, "
            "and cost tracking are all in place and proven",
        ],
        "gap_to_next": [
            "close the security gap: complete PII redaction sampling",
            "load-test to the 30 RPS capacity ceiling",
            "add multi-region capacity for regional failover",
        ],
        "disposition": "MANAGED_PRODUCTION",
        "note": "the evidence puts the system firmly at managed production; the "
                "named gaps are exactly what stand between it and scale-ready",
    }

    _STATE.update({
        "deprecation": deprecation,
        "audit": audit,
        "decision": decision,
        "patterns": patterns,
        "runbook": runbook,
        "maturity": maturity,
    })
    return {"deprecation": deprecation["disposition"],
            "audit_score": f"{total}/{max_total}", "gaps": gaps,
            "chosen_pattern": patterns["chosen"],
            "maturity": maturity["disposition"]}


def state() -> dict:
    return _STATE
