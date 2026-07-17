"""Model update baseline gate (Module 3, Clip 3).

A real Pytest suite that enforces the promotion baseline. It imports the same
validation logic the demo endpoints use, so "the baseline tests pass" is a
genuine, runnable fact. Run it directly:

    pytest tests/baseline -q

The gate covers five dimensions — output quality, latency, cost, failure rate,
and output-contract compliance. A passing candidate clears every threshold; a
failing candidate is blocked and can never become the default.
"""
from __future__ import annotations

import pytest

from app.lifecycle import validation

PASSING = "balanced-std@2026-07"
FAILING = "econo-fast@2026-07"


@pytest.mark.parametrize("dimension", list(validation.BASELINE.keys()))
def test_passing_candidate_clears_every_dimension(dimension):
    """The passing candidate must clear every baseline dimension individually."""
    rows = {r["dimension"]: r for r in validation.evaluate(PASSING)}
    assert rows[dimension]["status"] == "pass", (
        f"{PASSING} unexpectedly breached {dimension}: {rows[dimension]}"
    )


def test_passing_candidate_is_eligible():
    """A candidate that clears all thresholds is eligible for promotion."""
    g = validation.gate(PASSING)
    assert g["eligible"] is True
    assert g["breaches"] == []


def test_failing_candidate_is_blocked():
    """A candidate that drifts on any dimension is blocked from promotion."""
    g = validation.gate(FAILING)
    assert g["eligible"] is False
    assert g["breaches"], "failing candidate must report the breached dimensions"


def test_failing_candidate_breaches_expected_dimensions():
    """The failing candidate breaches quality, latency, failure rate, and contract."""
    breaches = set(validation.gate(FAILING)["breaches"])
    assert {"quality_score", "latency_p95_ms", "failure_rate_pct",
            "contract_compliance_pct"} <= breaches


def test_no_candidate_becomes_default_without_passing():
    """The release decision never marks any candidate as the new default; a
    candidate must pass the gate AND clear a canary before it can be default."""
    validation.run_validation()
    for d in validation.state()["decision"]["decisions"]:
        assert d["becomes_default"] is False


def test_blocked_candidate_decision_is_blocked():
    """The failing candidate's release decision must be an explicit block."""
    validation.run_validation()
    decisions = {d["candidate"]: d for d in validation.state()["decision"]["decisions"]}
    assert decisions[FAILING]["decision"] == "blocked"
    assert decisions[PASSING]["eligible"] is True
