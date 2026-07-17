"""Model update validation against quality/performance baselines (Module 3, Clip 3).

A candidate model may not become the production default until it clears a baseline
gate covering five dimensions: output quality, latency, cost, failure rate, and
output-contract compliance. The gate is deterministic and is enforced by a real
Pytest suite (tests/baseline/test_model_baseline.py) that imports this module — so
"the tests pass" is a genuine, runnable fact, not a claim.

Two candidates make the lesson concrete: one clears every threshold and becomes
eligible for promotion; the other drifts on quality, latency, failure rate, and
contract compliance and is blocked. Neither can become the default without passing
the gate.

What this proves (EO4b): a model update validation workflow that tests candidates
against quality and performance baselines before promotion.
"""
from __future__ import annotations

# --- The approved baseline the gate measures against -----------------------
APPROVED_MODEL = "balanced-std@2026-06"

# Each dimension has a direction: "min" means higher-is-better (candidate value
# must be >= threshold); "max" means lower-is-better (value must be <= threshold).
BASELINE: dict[str, dict] = {
    "quality_score":        {"threshold": 0.90, "direction": "min", "unit": ""},
    "latency_p95_ms":       {"threshold": 800,  "direction": "max", "unit": "ms"},
    "cost_per_1k_usd":      {"threshold": 0.35, "direction": "max", "unit": "$"},
    "failure_rate_pct":     {"threshold": 1.0,  "direction": "max", "unit": "%"},
    "contract_compliance_pct": {"threshold": 99.0, "direction": "min", "unit": "%"},
}

# Candidate measurements (deterministic — the fixed evaluation result per model).
CANDIDATES: dict[str, dict] = {
    "balanced-std@2026-07": {
        "label": "passing candidate",
        "metrics": {
            "quality_score": 0.93,
            "latency_p95_ms": 760,
            "cost_per_1k_usd": 0.32,
            "failure_rate_pct": 0.4,
            "contract_compliance_pct": 100.0,
        },
    },
    "econo-fast@2026-07": {
        "label": "failing candidate",
        "metrics": {
            "quality_score": 0.86,        # below the 0.90 quality floor
            "latency_p95_ms": 900,        # above the 800ms latency budget
            "cost_per_1k_usd": 0.30,      # within cost budget
            "failure_rate_pct": 2.1,      # above the 1.0% failure ceiling
            "contract_compliance_pct": 96.5,  # below the 99% contract floor
        },
    },
}


def _passes(value: float, threshold: float, direction: str) -> bool:
    return value >= threshold if direction == "min" else value <= threshold


def evaluate(candidate: str) -> list[dict]:
    """Score one candidate against every baseline dimension, returning a row per
    dimension with the value, threshold, comparator, and pass/fail."""
    metrics = CANDIDATES[candidate]["metrics"]
    rows = []
    for dim, cfg in BASELINE.items():
        value = metrics[dim]
        ok = _passes(value, cfg["threshold"], cfg["direction"])
        comparator = ">=" if cfg["direction"] == "min" else "<="
        rows.append({
            "dimension": dim,
            "value": value,
            "threshold": cfg["threshold"],
            "comparator": comparator,
            "unit": cfg["unit"],
            "status": "pass" if ok else "breach",
        })
    return rows


def gate(candidate: str) -> dict:
    """The promotion gate: a candidate is eligible only if it clears EVERY
    baseline dimension. Returns eligibility and the list of breached dimensions."""
    rows = evaluate(candidate)
    breaches = [r["dimension"] for r in rows if r["status"] == "breach"]
    return {
        "candidate": candidate,
        "label": CANDIDATES[candidate]["label"],
        "rows": rows,
        "breaches": breaches,
        "eligible": len(breaches) == 0,
    }


_STATE: dict = {}


def run_validation() -> dict:
    """Evaluate every candidate against the baseline and build the state the
    /lifecycle/validation/* endpoints read."""
    passing = "balanced-std@2026-07"
    failing = "econo-fast@2026-07"
    gate_pass = gate(passing)
    gate_fail = gate(failing)

    # The gate summary — what Step 1 shows, and what the Pytest suite asserts.
    dims = list(BASELINE.keys())
    suite = {
        "approved_model": APPROVED_MODEL,
        "dimensions": dims,
        "checks": len(dims) * len(CANDIDATES),
        "candidates": [
            {"candidate": passing, "label": gate_pass["label"],
             "eligible": gate_pass["eligible"], "breaches": len(gate_pass["breaches"])},
            {"candidate": failing, "label": gate_fail["label"],
             "eligible": gate_fail["eligible"], "breaches": len(gate_fail["breaches"])},
        ],
        "gate_enforced": True,
        "note": "the gate is a real Pytest suite — run pytest tests/baseline to see "
                "it enforce these thresholds",
    }

    # Report: both candidates, per-dimension, side by side with the baseline.
    report = {
        "approved_model": APPROVED_MODEL,
        "baseline": [{"dimension": d, "threshold": BASELINE[d]["threshold"],
                      "comparator": ">=" if BASELINE[d]["direction"] == "min" else "<=",
                      "unit": BASELINE[d]["unit"]} for d in dims],
        "candidates": [gate_pass, gate_fail],
    }

    # Release decision per candidate: promote the passing one, block the failing
    # one. A candidate can never become default without clearing the baseline.
    decisions = [
        {"candidate": passing, "eligible": gate_pass["eligible"],
         "decision": "promote_to_candidate_default", "breaches": gate_pass["breaches"],
         "becomes_default": False,
         "note": "eligible — cleared every baseline dimension; promoted behind a canary"},
        {"candidate": failing, "eligible": gate_fail["eligible"],
         "decision": "blocked", "breaches": gate_fail["breaches"],
         "becomes_default": False,
         "note": "blocked on " + ", ".join(gate_fail["breaches"]) + " — cannot become default"},
    ]

    reconcile = {
        "approved_model": APPROVED_MODEL,
        "default_unchanged": True,
        "eligible_candidates": [c["candidate"] for c in report["candidates"] if c["eligible"]],
        "blocked_candidates": [c["candidate"] for c in report["candidates"] if not c["eligible"]],
        "gate_enforced": True,
        "disposition": "CONFIRMED",
        "note": "the default stays on the approved model; only a baseline-passing "
                "candidate is even eligible, and promotion still goes through a canary",
    }

    _STATE.update({
        "gate": suite,
        "baseline": {"approved_model": APPROVED_MODEL, "rows": report["baseline"]},
        "report": report,
        "pass": gate_pass,
        "fail": gate_fail,
        "decision": {"decisions": decisions},
        "reconcile": reconcile,
    })
    return {"approved_model": APPROVED_MODEL, "eligible": gate_pass["eligible"],
            "blocked": not gate_fail["eligible"], "checks": suite["checks"],
            "disposition": reconcile["disposition"]}


def state() -> dict:
    return _STATE
