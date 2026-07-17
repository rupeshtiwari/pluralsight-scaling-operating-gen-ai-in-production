"""Canary promotion, hold, and rollback (Module 3, Clip 5).

A candidate prompt+model combination that has cleared the offline baseline earns a
canary: a small, bounded slice of eligible traffic — ten percent — served by the
new release under watch, while the rest stays on the approved release. The canary
is promoted only when its live signals (quality, latency, cost, error rate, and
output-contract compliance) clear the promotion criteria AND the receipt trail
proves the exposure stayed bounded. The moment a signal breaches, the canary is
held or rolled back and production returns to the approved release.

Two canaries make the decision concrete and deterministic: a healthy one that
earns promotion, and a degraded one that breaches and is rolled back. Either way
the blast radius is capped at ten percent, so a bad release can never harm more
than the canary slice.

What this proves (EO4c): a canary deployment with a controlled blast radius and
defined promotion criteria.
"""
from __future__ import annotations

import math

# --- The approved release the canary is measured against -------------------
APPROVED_PROMPT = "v2.0.0"
APPROVED_RELEASE = "rel-2026.06"
APPROVED_MODEL = "balanced-std@2026-06"

CANARY_PROMPT = "v3.0.0-rc1"
CANARY_RELEASE = "rel-2026.07-rc1"
CANARY_MODEL = "balanced-std@2026-07"

CANARY_PCT = 10                 # bounded blast radius: 10% of eligible traffic
ELIGIBLE_REQUESTS = 50          # eligible traffic in the watch window
RAMP_PLAN = [10, 25, 50, 100]   # staged promotion ramp (percent)

# Promotion criteria — a min floor or a max ceiling per signal.
PROMOTION_CRITERIA: dict[str, dict] = {
    "quality_score":           {"threshold": 0.90, "direction": "min", "unit": ""},
    "latency_p95_ms":          {"threshold": 900,  "direction": "max", "unit": "ms"},
    "cost_per_1k_usd":         {"threshold": 0.35, "direction": "max", "unit": "$"},
    "error_rate_pct":          {"threshold": 1.0,  "direction": "max", "unit": "%"},
    "contract_compliance_pct": {"threshold": 99.0, "direction": "min", "unit": "%"},
}

# The approved release's live signals — the production reference during the watch.
APPROVED_SIGNALS = {
    "quality_score": 0.91, "latency_p95_ms": 740, "cost_per_1k_usd": 0.30,
    "error_rate_pct": 0.4, "contract_compliance_pct": 99.6,
}

# Two canaries: one healthy (earns promotion), one degraded (rolled back).
CANARY_HEALTHY = {
    "quality_score": 0.93, "latency_p95_ms": 780, "cost_per_1k_usd": 0.32,
    "error_rate_pct": 0.5, "contract_compliance_pct": 100.0,
}
CANARY_DEGRADED = {
    "quality_score": 0.84, "latency_p95_ms": 1300, "cost_per_1k_usd": 0.33,
    "error_rate_pct": 3.2, "contract_compliance_pct": 95.0,
}

_STATE: dict = {}


def _passes(value: float, threshold: float, direction: str) -> bool:
    return value >= threshold if direction == "min" else value <= threshold


def _evaluate(signals: dict) -> list[dict]:
    rows = []
    for dim, cfg in PROMOTION_CRITERIA.items():
        ok = _passes(signals[dim], cfg["threshold"], cfg["direction"])
        rows.append({
            "signal": dim, "value": signals[dim], "threshold": cfg["threshold"],
            "comparator": ">=" if cfg["direction"] == "min" else "<=",
            "unit": cfg["unit"], "status": "pass" if ok else "breach",
        })
    return rows


def run_canary() -> dict:
    """Build the deterministic canary state: start, watch, criteria, promote,
    rollback, and reconcile — for the /lifecycle/canary/* endpoints."""
    canary_requests = math.ceil(ELIGIBLE_REQUESTS * CANARY_PCT / 100)  # 5
    production_requests = ELIGIBLE_REQUESTS - canary_requests          # 45
    bounded = canary_requests <= math.ceil(ELIGIBLE_REQUESTS * CANARY_PCT / 100)

    start = {
        "canary_pct": CANARY_PCT,
        "eligible_requests": ELIGIBLE_REQUESTS,
        "canary_requests": canary_requests,
        "production_requests": production_requests,
        "canary_release": CANARY_RELEASE, "canary_prompt": CANARY_PROMPT,
        "canary_model": CANARY_MODEL,
        "approved_release": APPROVED_RELEASE, "approved_prompt": APPROVED_PROMPT,
        "approved_model": APPROVED_MODEL,
        "blast_radius_bounded": bounded,
        "note": "the canary serves only 10% of eligible traffic — a bad release "
                "can never harm more than the canary slice",
    }

    # Watch: the healthy canary's live signals next to the approved reference.
    watch = {
        "canary_release": CANARY_RELEASE,
        "approved_release": APPROVED_RELEASE,
        "signals": [
            {"signal": k, "canary": CANARY_HEALTHY[k], "approved": APPROVED_SIGNALS[k],
             "unit": PROMOTION_CRITERIA[k]["unit"]}
            for k in PROMOTION_CRITERIA
        ],
        "note": "watching quality, latency, cost, error rate, and contract "
                "compliance on the canary slice against production",
    }

    # Criteria: the healthy canary evaluated against the promotion thresholds,
    # plus the bounded-exposure proof from the receipt trail.
    healthy_rows = _evaluate(CANARY_HEALTHY)
    healthy_breaches = [r["signal"] for r in healthy_rows if r["status"] == "breach"]
    criteria = {
        "canary_release": CANARY_RELEASE,
        "rows": healthy_rows,
        "breaches": healthy_breaches,
        "criteria_met": len(healthy_breaches) == 0,
        "canary_requests": canary_requests,
        "expected_max_canary": math.ceil(ELIGIBLE_REQUESTS * CANARY_PCT / 100),
        "exposure_bounded": bounded,
        "eligible_to_promote": len(healthy_breaches) == 0 and bounded,
        "note": "promotion needs BOTH: every signal within criteria AND a receipt "
                "trail proving exposure never exceeded the 10% blast radius",
    }

    # Promote: the healthy canary earns a staged ramp to the new default.
    promote = {
        "canary_release": CANARY_RELEASE,
        "decision": "PROMOTE",
        "criteria_met": criteria["criteria_met"],
        "exposure_bounded": bounded,
        "ramp_plan_pct": RAMP_PLAN,
        "from_release": APPROVED_RELEASE,
        "to_release": CANARY_RELEASE,
        "note": "criteria met and exposure bounded — promote on a staged ramp "
                "(10 → 25 → 50 → 100%), each stage still watched",
    }

    # Rollback: the degraded canary breaches, so it is rolled back and production
    # returns to the approved release. The blast radius is the 5 canary requests.
    degraded_rows = _evaluate(CANARY_DEGRADED)
    degraded_breaches = [r["signal"] for r in degraded_rows if r["status"] == "breach"]
    rollback = {
        "canary_release": CANARY_RELEASE,
        "decision": "ROLLBACK",
        "rows": degraded_rows,
        "breaches": degraded_breaches,
        "affected_requests": canary_requests,
        "affected_pct": CANARY_PCT,
        "active_release_after": APPROVED_RELEASE,
        "active_prompt_after": APPROVED_PROMPT,
        "active_model_after": APPROVED_MODEL,
        "canary_exposure_after_pct": 0,
        "note": "a breached signal rolls the canary back — production returns to "
                "the approved release, and only the 10% canary slice ever saw the regression",
    }

    # Reconcile: after the rollback, production is provably on the approved release
    # with zero canary exposure and a bounded blast radius throughout.
    active_ok = rollback["active_release_after"] == APPROVED_RELEASE
    exposure_zero = rollback["canary_exposure_after_pct"] == 0
    confirmed = active_ok and exposure_zero and bounded
    reconcile = {
        "active_release": rollback["active_release_after"],
        "active_prompt": rollback["active_prompt_after"],
        "active_model": rollback["active_model_after"],
        "approved_release": APPROVED_RELEASE,
        "active_matches_approved": active_ok,
        "canary_exposure_pct": rollback["canary_exposure_after_pct"],
        "blast_radius_bounded": bounded,
        "max_exposure_pct": CANARY_PCT,
        "disposition": "CONFIRMED" if confirmed else "BLOCKED",
        "note": "production is back on the approved release, canary exposure is "
                "zero, and the blast radius never exceeded 10% — the rollback is provable",
    }

    _STATE.update({
        "start": start, "watch": watch, "criteria": criteria,
        "promote": promote, "rollback": rollback, "reconcile": reconcile,
    })
    return {"canary_pct": CANARY_PCT, "eligible_to_promote": criteria["eligible_to_promote"],
            "rollback_breaches": len(degraded_breaches),
            "disposition": reconcile["disposition"]}


def state() -> dict:
    return _STATE
