"""Incident diagnosis (Module 2, Clip 6).

The capstone: a single controlled incident that lights up all four alerting
dimensions at once — latency, quota pressure, cost drift, and quality
regression — and the operator's job is to walk the diagnosis funnel from the
first bad signal down to one root cause and a coordinated, evidence-based action.

Everything here is deterministic on purpose. One provider fault drives the whole
incident: the ``balanced-ai`` provider behind the ``balanced-std`` tier goes
``degraded_slow`` and then exhausts its quota. That single fault cascades into
four separate alerts, which is exactly the trap this clip teaches you to avoid —
four alerts do not mean four problems. The trace, the receipts, and the cost and
quality breakdowns all point back to the same provider, so the operator acts on
the cause, not each symptom.

What this proves (TO2, EO2e, TO3, EO3a-e): a simulated incident (EO2e) is read
from an alert timeline and an operator dashboard (EO3d); one trace isolates the
latency to a stage (EO3a, EO3e); admission control sheds the quota pressure (TO2,
EO2e); cost drift is tied to model identity, tokens, and retries (EO3b); quality
sampling confirms the regression (EO3c); and the evidence resolves to a single
root cause and a coordinated action (EO3e).
"""
from __future__ import annotations

from app.observability.observe import _build_trace

# --- The incident trace: one slow request, every stage timed ---------------
# The primary (balanced-std) is degraded_slow, so provider_call dominates. The
# queue is backed up but small; a retry backs off; a fallback finally serves.
# The point of the shape is that provider_call dwarfs queue, retry, and fallback
# combined — the latency is the provider's, not the service's.


def _incident_stages() -> list[tuple]:
    return [
        ("request", None, None),
        ("ingress", "request", 2),
        ("queue", "request", 40),           # backlog present, but small
        ("routing", "request", 3),
        ("provider_call", "request", 3100),  # degraded_slow primary — the culprit
        ("retry_backoff", "request", 200),   # one bounded backoff before failover
        ("fallback", "request", 400),        # a healthy alternative serves
        ("response", "request", 5),
    ]


# --- Fixed incident numbers, so every derived figure reconciles ------------
WINDOW_REQUESTS = 40           # requests in the incident window
ACCEPTED = 34                  # admitted and served
REJECTED_429 = 6               # shed by admission control (fail-fast, Retry-After)

# Objectives (the same objectives the SLO rules and Clip 5 use).
OBJ_LATENCY_P95_MS = 2500
OBJ_QUOTA_SATURATION_PCT = 90
OBJ_COST_PER_REQUEST_USD = 0.0150
OBJ_QUALITY_PASS_PCT = 90.0

_STATE: dict = {}


def _dashboard_row(metric, dimension, baseline, current, objective, comparator,
                   ok, severity, unit):
    return {
        "metric": metric, "dimension": dimension, "baseline": baseline,
        "current": current, "objective": objective, "comparator": comparator,
        "unit": unit, "status": "ok" if ok else "breach",
        "severity": "none" if ok else severity,
    }


def run_incident() -> dict:
    """Build the deterministic incident: alert timeline, operator dashboard, the
    isolating trace, the quota shed, the cost drift, the quality regression, and
    the root-cause action. Populates the state the /incident/* endpoints read."""

    # One exemplar slow request, traced end to end with real OTel spans.
    tid, spans = _build_trace(_incident_stages())
    child = [s for s in spans if s["parent"]]
    total_ms = sum(s["duration_ms"] for s in child)
    by = {s["span"]: s["duration_ms"] for s in child}
    prov = by["provider_call"]

    def share(ms: int) -> float:
        return round(100.0 * ms / total_ms, 1)

    # --- Alert timeline: which signal fired first ------------------------
    # Latency breaches first; quality (the one that matters most) pages last.
    # The lesson: the first alert is a symptom, not the root cause.
    alerts = [
        {"order": 1, "at": "+00:30", "alert": "LatencyP95AboveObjective",
         "dimension": "latency", "severity": "ticket", "first_signal": True,
         "detail": "p95 crossed 2500 ms"},
        {"order": 2, "at": "+01:10", "alert": "QuotaSaturationHigh",
         "dimension": "quota", "severity": "ticket", "first_signal": False,
         "detail": "balanced-ai quota utilization crossed 90%"},
        {"order": 3, "at": "+02:00", "alert": "CostPerRequestDrift",
         "dimension": "cost", "severity": "ticket", "first_signal": False,
         "detail": "cost per request crossed $0.0150"},
        {"order": 4, "at": "+02:40", "alert": "QualityPassRateBelowObjective",
         "dimension": "output_quality", "severity": "page", "first_signal": False,
         "detail": "sampled pass rate fell under 90%"},
    ]

    # --- Operator dashboard: four dimensions, baseline vs current --------
    dashboard = {
        "window_requests": WINDOW_REQUESTS,
        "panels": [
            _dashboard_row("latency_p95_ms", "latency", 950, total_ms,
                           OBJ_LATENCY_P95_MS, "<=", False, "ticket", "ms"),
            _dashboard_row("quota_saturation_pct", "quota", 55, 98,
                           OBJ_QUOTA_SATURATION_PCT, "<=", False, "ticket", "%"),
            _dashboard_row("cost_per_request_usd", "cost", 0.0120, 0.0210,
                           OBJ_COST_PER_REQUEST_USD, "<=", False, "ticket", "$"),
            _dashboard_row("quality_pass_rate_pct", "output_quality", 92.0, 68.0,
                           OBJ_QUALITY_PASS_PCT, ">=", False, "page", "%"),
        ],
        "breached": 4,
        "note": "four panels red at once — but one provider fault is behind them",
    }

    # --- Isolate the latency from the trace ------------------------------
    isolate = {
        "trace_id": tid,
        "total_ms": total_ms,
        "spans": child,
        "contributors": [
            {"stage": "queueing", "span": "queue", "ms": by["queue"],
             "share_pct": share(by["queue"]), "verdict": "innocent"},
            {"stage": "retry", "span": "retry_backoff", "ms": by["retry_backoff"],
             "share_pct": share(by["retry_backoff"]), "verdict": "innocent"},
            {"stage": "fallback", "span": "fallback", "ms": by["fallback"],
             "share_pct": share(by["fallback"]), "verdict": "innocent"},
            {"stage": "provider call", "span": "provider_call", "ms": prov,
             "share_pct": share(prov), "verdict": "root cause"},
        ],
        "slowest_span": "provider_call",
        "slowest_ms": prov,
        "slowest_share_pct": share(prov),
        "provider": "balanced-ai",
        "provider_status": "degraded_slow",
        "root_cause": "provider latency on balanced-ai, not queueing, retry, or fallback",
    }

    # --- Quota pressure: admission control sheds load on purpose ---------
    quota = {
        "provider": "balanced-ai",
        "tier": "balanced-std",
        "request_class": "interactive",
        "quota_mode": "dedicated",
        "rate_limit": 6,
        "window_seconds": 10,
        "submitted": WINDOW_REQUESTS,
        "accepted": ACCEPTED,
        "rejected_429": REJECTED_429,
        "retry_after_seconds": 10,
        "provider_status": "quota_exceeded",
        "quota_utilization_pct": 98,
        "shed_working": True,
        "note": "the 429s are the system shedding load — Retry-After tells the "
                "caller exactly when to come back, and the provider is protected",
    }

    # --- Cost drift: tie the extra dollars to a cause --------------------
    # Baseline $0.0120/req climbs to $0.0210/req (+75%). The delta is two named
    # drivers, and they sum exactly to the gap — no hand-waving.
    base_pr, curr_pr = 0.0120, 0.0210
    retries_add, fallback_add = 0.0063, 0.0027
    cost = {
        "baseline_per_request_usd": base_pr,
        "current_per_request_usd": curr_pr,
        "drift_pct": round(100.0 * (curr_pr - base_pr) / base_pr, 1),
        "objective_per_request_usd": OBJ_COST_PER_REQUEST_USD,
        "served": ACCEPTED,
        "baseline_window_usd": round(ACCEPTED * base_pr, 4),
        "current_window_usd": round(ACCEPTED * curr_pr, 4),
        "drivers": [
            {"driver": "retries on balanced-std",
             "detail": "degraded_slow primary retried before failover — each retry "
                       "pays for a second provider call at $0.30/1k",
             "add_per_request_usd": retries_add},
            {"driver": "fallback overhead",
             "detail": "an extra provider call after the failed primary",
             "add_per_request_usd": fallback_add},
        ],
        "reconciles": round(base_pr + retries_add + fallback_add, 4) == curr_pr,
        "model_rates_per_1k_usd": {"econo-mini": 0.05, "balanced-std": 0.30,
                                   "premium-max": 1.20},
        "note": "the drift is retries and failover on the degraded provider, not "
                "more traffic — model identity is where the dollars went",
    }

    # --- Quality regression: sampling confirms the drop ------------------
    # Grouped failure reasons are more operable than a row per sample: they show
    # the failures cluster on the degraded provider, not random noise.
    sampled, passed = 25, 17
    failed = sampled - passed
    quality = {
        "policy": "output_quality_sampling",
        "sample_size": sampled,
        "passed": passed,
        "failed": failed,
        "pass_rate_pct": round(100.0 * passed / sampled, 1),
        "baseline_pass_rate_pct": 92.0,
        "objective_pass_rate_pct": OBJ_QUALITY_PASS_PCT,
        "quality_bar": 0.85,
        "failure_reasons": [
            {"reason": "hallucinated a policy number", "count": 3},
            {"reason": "answer contradicts the source", "count": 3},
            {"reason": "off-format / schema invalid", "count": 2},
        ],
        "cluster": "balanced-std (degraded window)",
        "note": "every failure is a 200 OK — confident and wrong — and they "
                "cluster on the degraded provider, not spread at random",
    }

    # --- Root cause + coordinated action --------------------------------
    action = {
        "root_cause": "balanced-ai (balanced-std) degraded — slow responses then "
                      "quota exhaustion — one provider fault behind all four alerts",
        "decisions": [
            {"dimension": "latency",
             "evidence": f"provider_call is {share(prov)}% of a {total_ms}ms trace, "
                         "status degraded_slow",
             "action": "open the circuit and fail over balanced-std → econo-mini",
             "expected_effect": "p95 back under 2500 ms"},
            {"dimension": "quota",
             "evidence": "balanced-ai at 98% quota; 6 requests shed with Retry-After",
             "action": "keep the tighter rate limit — it is protecting the provider",
             "expected_effect": "429 shed rate falls as failover drains balanced-ai"},
            {"dimension": "cost",
             "evidence": "+75% per request, driven by retries on balanced-std",
             "action": "cap retries and stop retrying the degraded primary",
             "expected_effect": "cost per request back toward $0.0120"},
            {"dimension": "output_quality",
             "evidence": "pass rate 68% vs 92% baseline; failures cluster on balanced-std",
             "action": "sample-and-block the degraded provider; exclude from training set",
             "expected_effect": "pass rate recovers above 90%"},
        ],
        "disposition": "ACT",
        "note": "four alerts, one provider fault; the trace and receipts turned "
                "symptoms into an evidence-based action, not four guesses",
    }

    _STATE.update({
        "alerts": {"alerts": alerts,
                   "first_signal": next(a["alert"] for a in alerts if a["first_signal"]),
                   "count": len(alerts),
                   "note": "the first alert is a symptom — you still isolate the cause"},
        "dashboard": dashboard,
        "isolate": isolate,
        "quota": quota,
        "cost": cost,
        "quality": quality,
        "action": action,
    })
    return {"incident": "balanced-ai degraded", "alerts": len(alerts),
            "breached_dimensions": 4, "trace_id": tid, "root_cause_provider": "balanced-ai"}


def state() -> dict:
    return _STATE
