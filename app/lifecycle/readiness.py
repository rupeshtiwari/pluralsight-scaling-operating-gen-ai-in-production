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

# The operational service SLO the runbook monitors — the p95 ceiling that fires the
# latency alert (distinct from the 500ms deployment target the pattern choice uses).
_SERVICE_SLO_P95_MS = 2500


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
        # A concrete, representative compatibility receipt — a named artifact that
        # ties the routed model identity (deprecated → replacement) to the four
        # checks, so the proof is a receipt you can point at, not just results.
        "receipt_id": "dep-0012",
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
        # A concrete PII-redaction example makes the security gap tangible: a raw
        # value carrying PII is masked (last 3 kept for support lookup), and only
        # part of the traffic is sampled — that unsampled remainder IS the gap.
        "redaction_sample": {
            "field": "customer_ref",
            "raw": "cust-102317",
            "redacted": "cust-XXX317",
            "rule": "last 3 kept for support lookup, the rest masked",
            "verified_requests": 1240,
            "total_requests": 2000,
            "coverage_pct": 62,          # 1240 / 2000
            "unverified_requests": 760,  # 2000 - 1240, no redaction proof
            "required_pct": 95,
            "gap_pp": 33,                # 95 - 62
            "action": "scale blocked until sampling coverage reaches 95%+ — increase "
                      "the sample rate or switch to inline redaction",
            "note": "redaction works on sampled traffic, but only 62% of requests are "
                    "sampled — the other 38% (760/2000) are unverified, and that is the gap",
        },
        "note": "four dimensions are production-ready; security is the one open "
                "gap, and naming it is what makes the audit honest",
    }

    # --- EO5b (evidence): the workload profile the decision reads ----------
    # Concrete deterministic inputs: steady ~10 RPS, a tight latency target, and a
    # cold-start penalty that would exceed it. The deployment decision is DERIVED
    # from these numbers below, so the recommendation is auditable evidence.
    workload = {
        "window": "15 min controlled workload sample",
        "measured_rps": 9.8,
        "peak_rps": 11.2,
        "variance": "low — steady, not bursty",
        "latency_target_ms": 500,        # the deployment latency requirement (NOT the 2500ms service SLO)
        "observed_p95_ms": 420,
        "cold_start_penalty_ms": 1800,
        "latency_sensitive": True,
        "cold_start_tolerable": False,   # a 1800ms cold start vs a 500ms deployment target
        "signals": [
            {"signal": "traffic", "sample": "9.8 RPS avg · 11.2 peak",
             "reading": "steady ~10 RPS"},
            {"signal": "latency", "sample": "p95 420ms vs 500ms target",
             "reading": "latency-sensitive"},
            {"signal": "cold_start", "sample": "1800ms penalty vs 500ms target",
             "reading": "cold starts unacceptable"},
        ],
        "note": "the workload profile provides the inputs the deployment decision "
                "is derived from",
    }

    # Derive the pattern FROM the workload profile, so the recommendation is a
    # computed result of the evidence, not a hard-coded label.
    _steady = workload["variance"].startswith("low")
    _rps = workload["measured_rps"]
    if not workload["cold_start_tolerable"] and _rps < 20 and _steady:
        _recommended = "containers"
    elif workload["cold_start_tolerable"] and not _steady:
        _recommended = "serverless"
    elif _rps >= 100:
        _recommended = "dedicated_gpu"
    else:
        _recommended = "containers"

    # --- EO5b (decision): choose the deployment pattern for the workload --
    decision = {
        "workload": "steady ~10 RPS, latency-sensitive, cold start unacceptable",
        "derived_from": "GET /lifecycle/readiness/workload (workload profile)",
        "recommended_pattern": _recommended,
        "reasons": [
            "cold-start penalty 1800ms exceeds the 500ms deployment target — rules out scale-to-zero serverless",
            "traffic is steady at ~10 RPS, so serverless burst scaling is unneeded",
            "10 RPS does not justify the cost of a dedicated GPU instance",
            "containers stay warm, autoscale for headroom, and keep ownership control",
        ],
        "note": "the deployment pattern follows the workload profile — steady, "
                "latency-sensitive traffic points at warm containers, not serverless or GPU",
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
             "fit": "no — unnecessary operating cost and ownership at 10 RPS"},
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
             "quality pass ≥ 90%, cost/1k ≤ $0.35, error rate ≤ 1%"},
            {"section": "incident_response", "detail": "page on an availability or "
             "quality breach; diagnose trace → logs → receipts; fail over via the "
             "circuit breaker"},
            {"section": "rollback", "detail": "revert to the approved release id "
             "(prompt + model); drive canary exposure to 0"},
            {"section": "capacity", "detail": "baseline 10 RPS with headroom to 30 "
             "RPS; scale when queue depth > 20 or p95 > 2000ms"},
        ],
        # Actionable operator controls — each a concrete trigger → action rule, not
        # descriptive prose. This is what makes the runbook executable, not aspirational.
        "controls": [
            {"trigger": "queue_depth > 20  OR  p95 > 2000ms",
             "action": "scale out container replicas toward the 30 RPS ceiling",
             "kind": "capacity / auto-scale"},
            {"trigger": "availability < 99%  OR  quality_pass < 90%",
             "action": "page the on-call operator, then diagnose trace → logs → receipts",
             "kind": "incident / page"},
            {"trigger": "error_rate > 1% sustained",
             "action": "fail over via the circuit breaker and roll back to the approved release",
             "kind": "reliability / fail-over"},
        ],
        "complete": True,
        "note": "every runbook section maps to a concrete production control, and each "
                "operator rule connects a trigger directly to an action",
    }

    # --- EO5d: the maturity decision (DERIVED from the audit evidence) ----
    # Not a static label: the level is computed from what the readiness audit and
    # capacity plan actually prove. An open audit gap, or missing load-test /
    # multi-region evidence, keeps the system at managed production, not scale-ready.
    _core_ready = audit["ready_dimensions"] >= 4     # observability, resilience, ...
    _load_tested_to_ceiling = False                  # capacity baselined at ~10 RPS only
    _multi_region = False                            # single-region today
    # Each gap names the concrete INVESTMENT needed to close it — an honest maturity
    # assessment tells you the work, not just "not ready yet".
    _gap_to_next = []
    if gaps:
        _gap_to_next.append({
            "gap": "readiness-audit gap — " + ", ".join(gaps) +
                   ": PII redaction at 62% coverage, must reach 95%",
            "investment": "switch to inline redaction or 2x the sample rate, then "
                          "re-audit after 7 days of traffic",
        })
    if not _load_tested_to_ceiling:
        _gap_to_next.append({
            "gap": "load-test ceiling — 30 RPS proven, must prove 100 RPS sustained",
            "investment": "run a 4-hour soak test at 100 RPS; verify autoscale, queue, "
                          "and circuit breaker hold under sustained load",
        })
    if not _multi_region:
        _gap_to_next.append({
            "gap": "single-region only — no regional failover proof",
            "investment": "deploy a replica region, run a failover drill, prove receipt "
                          "continuity across regions",
        })
    if not _gap_to_next:
        _current = "scale_ready"
    elif _core_ready:
        _current = "managed_production"
    else:
        _current = "prototype"
    maturity = {
        "levels": ["prototype", "managed_production", "scale_ready"],
        "current": _current,
        "derived_from": "GET /lifecycle/readiness/audit (open gaps) + capacity evidence",
        "evidence": [
            "observability, resilience, prompt/model versioning, canary release, "
            "and cost tracking are all in place and proven",
        ],
        # The seven capabilities proven across the module — each ties a prior clip's
        # evidence into the finale, so the maturity call rests on receipts, not claims.
        "proven_capabilities": [
            {"capability": "observability", "evidence": "traces + logs + metrics + SLO alerts"},
            {"capability": "resilience", "evidence": "circuit breaker + fallback + retry backoff"},
            {"capability": "prompt versioning", "evidence": "rollback proven with a receipt trail"},
            {"capability": "canary release", "evidence": "promotion + rollback + hold decisions"},
            {"capability": "cost tracking", "evidence": "$0.28/1K against a $0.35 budget"},
            {"capability": "model migration", "evidence": "adapter receipt with 4 compatibility checks"},
            {"capability": "runbook execution", "evidence": "a latency breach triggered scale-out live"},
        ],
        "gap_to_next": _gap_to_next,
        "disposition": _current.upper(),
        "note": "the level is computed from the evidence — the open audit gap plus "
                "the missing load-test and multi-region proof are what hold it at "
                "managed production, one step short of scale-ready",
    }

    _STATE.update({
        "deprecation": deprecation,
        "audit": audit,
        "workload": workload,
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
    # Auto-build on first read so a GET before the POST /run (e.g. after an api
    # restart, or when running a step out of order) never returns empty "None"
    # fields. run_readiness() is deterministic, so lazy-seeding is safe and
    # idempotent — the explicit POST /run in Step 1 still rebuilds it the same way.
    if not _STATE:
        run_readiness()
    return _STATE


def inject_breach(p95_ms: float) -> dict:
    """Prove the runbook is live, not a document: inject a p95 latency and record
    it. Reading /lifecycle/readiness/alert then shows whether the monitored SLO
    threshold fired the mapped scale-out action — a live trigger, not a canned
    response. Injecting a value under the threshold fires nothing."""
    st = state()
    if isinstance(p95_ms, float) and p95_ms.is_integer():
        p95_ms = int(p95_ms)   # 2600.0 -> 2600 so the panel reads cleanly
    st["_injected_p95_ms"] = p95_ms
    breaches = p95_ms > _SERVICE_SLO_P95_MS
    return {
        "injected": True,
        "p95_ms": p95_ms,
        "threshold_ms": _SERVICE_SLO_P95_MS,
        "breaches": breaches,
        "note": ("a p95 above the runbook SLO fires the latency alert and its "
                 "scale-out action" if breaches else
                 "a p95 within the SLO fires nothing — the alert is a live threshold"),
    }


def alert() -> dict:
    """Derive the runbook alert from the last injected p95: fires the mapped
    trigger -> action only when the injected latency breaches the monitored SLO."""
    st = state()
    p95 = st.get("_injected_p95_ms")
    threshold = _SERVICE_SLO_P95_MS
    if p95 is None:
        return {"fired": False, "threshold_ms": threshold,
                "note": "no breach injected yet — inject one to watch the control fire"}
    if p95 <= threshold:
        return {"fired": False, "measured_ms": p95, "threshold_ms": threshold,
                "note": f"p95 {p95}ms is within the {threshold}ms SLO — no alert, the "
                        f"control did not fire"}
    return {
        "fired": True,
        "alert": "p95_latency_breach",
        "measured_ms": p95,
        "threshold_ms": threshold,
        "breach_window_s": 60,
        "action_taken": "scale_out_triggered (target 30 RPS)",
        "escalation": "page the on-call operator if unresolved in 5m",
        "diagnosis_path": "traces -> logs -> receipts",
        "rollback": "revert to the approved release id (prompt + model)",
        "note": "the runbook control fired live — the injected breach triggered the "
                "mapped action, proving the runbook executes, not just describes",
    }
