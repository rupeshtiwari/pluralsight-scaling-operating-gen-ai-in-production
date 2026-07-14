"""Deterministic circuit breaker, fallback, and retry backoff (Module 2, Clip 3).

A fixed drill drives one primary provider through a scripted failure-then-heal
sequence, so a single run walks the whole state journey — closed -> open ->
half_open -> recovered — identically every time. No real outage, no wall-clock
sleeps: the failure modes come from the deterministic provider stubs and the
backoff schedule is computed, not waited on, so the demo is repeatable.

    closed    healthy; the primary serves
    open       too many consecutive failures; the primary is skipped (fail fast)
               and a healthy fallback model serves instead
    half_open  after a cooldown, one probe is allowed through to test recovery
    recovered  a successful probe closes the circuit again

Every request writes ONE receipt tagged with what served it (primary or
fallback) and, on a failover, the model it fell back from — so the caller
response, the durable receipt, and the retry log all agree on the outcome.
"""
from __future__ import annotations

import uuid

from app.db import postgres, redis_client
from app.providers.adapter import adapter_config, estimate_cost, estimate_tokens
from app.providers.registry import (
    BACKOFF_MAX_ATTEMPTS,
    CIRCUIT_DRILL_PRIMARY,
    CIRCUIT_DRILL_SEQUENCE,
    CIRCUIT_POLICY_NAME,
    COOLDOWN_PROBES,
    FAILURE_THRESHOLD,
    FALLBACK_ROUTES,
    backoff_schedule,
)

DRILL_PROMPT = "Summarize this customer support ticket into one sentence for triage."


def _receipt(model: str, route_reason: str, fallback_from: str | None) -> dict:
    """One normalized receipt for a served request (primary or fallback). The
    serving model is always healthy — a fallback is healthy by definition, and
    the primary only serves when it is healthy again."""
    cfg = adapter_config(model, "healthy")
    tokens = estimate_tokens(DRILL_PROMPT)
    cost = estimate_cost(tokens.total, cfg.cost_per_1k_usd)
    return {
        "request_id": f"req-{uuid.uuid4().hex[:12]}",
        "selected_model": cfg.model,
        "provider_tier": cfg.tier,
        "provider_status": cfg.status,
        "route_reason": route_reason,
        "latency_target_ms": cfg.latency_target_ms,
        "prompt_tokens": tokens.prompt,
        "completion_tokens": tokens.completion,
        "total_tokens": tokens.total,
        "cost_estimate_usd": cost,
        "quality_score": cfg.quality_score,
        "policy_name": CIRCUIT_POLICY_NAME,
        "fallback_from": fallback_from,
    }


def run_drill() -> dict:
    """Run the deterministic circuit-breaker drill and persist every receipt,
    the per-request timeline, and the retry log. Returns the run summary."""
    primary = CIRCUIT_DRILL_PRIMARY
    fallback = FALLBACK_ROUTES[primary]
    redis_client.reset_circuit()
    postgres.clear_circuit_receipts()  # idempotent re-runs → reconcile always matches

    state = "closed"
    consecutive_failures = 0
    probes_since_open = 0

    timeline: list[dict] = []
    retrylog: list[dict] = []
    fallback_count = 0
    primary_count = 0
    total_primary_attempts = 0
    tripped = False
    recovered = False

    for i, condition in enumerate(CIRCUIT_DRILL_SEQUENCE):
        seq = i + 1
        state_before = state
        healthy = condition == "healthy"

        # An open circuit that has waited out its cooldown gets one probe.
        if state == "open" and probes_since_open >= COOLDOWN_PROBES:
            state = "half_open"
        handling = state  # the state this request is handled under (visible on screen)

        if state == "open":
            # Fail fast: skip the primary entirely, shed to the fallback. This is
            # what PREVENTS a retry storm — zero primary attempts while open.
            attempts = 0
            probes_since_open += 1
            served, role, from_model, reason = fallback, "fallback", primary, "fallback_fast"
            transition = "shed"
            fallback_count += 1
        elif state == "half_open":
            # One probe to the primary tests recovery.
            attempts = 1
            total_primary_attempts += 1
            if healthy:
                state = "closed"
                consecutive_failures = 0
                probes_since_open = 0
                recovered = True
                served, role, from_model, reason = primary, "primary", None, "primary_recovered"
                transition = "recovered"
                primary_count += 1
            else:
                # Probe failed: reopen and keep shedding to the fallback.
                state = "open"
                probes_since_open = 0
                served, role, from_model, reason = fallback, "fallback", primary, "fallback_fast"
                transition = "probe_failed"
                fallback_count += 1
        else:  # closed
            if healthy:
                attempts = 1
                total_primary_attempts += 1
                consecutive_failures = 0
                served, role, from_model, reason = primary, "primary", None, "primary_ok"
                transition = "healthy"
                primary_count += 1
            else:
                # Retry the primary with backoff, then fail over to the fallback.
                attempts = BACKOFF_MAX_ATTEMPTS
                total_primary_attempts += BACKOFF_MAX_ATTEMPTS
                consecutive_failures += 1
                served, role, from_model, reason = fallback, "fallback", primary, "fallback_after_retry"
                transition = "failover"
                fallback_count += 1
                if consecutive_failures >= FAILURE_THRESHOLD:
                    state = "open"
                    probes_since_open = 0
                    tripped = True
                    transition = "trip"

        receipt = _receipt(served, reason, from_model)
        postgres.insert_receipt(receipt)

        record = {
            "seq": seq,
            "primary_condition": condition,
            "state_before": state_before,
            "circuit": handling,
            "state_after": state,
            "transition": transition,
            "served_by": served,
            "role": role,
            "fallback_from": from_model,
            "primary_attempts": attempts,
            "request_id": receipt["request_id"],
        }
        timeline.append(record)
        retrylog.append({
            "seq": seq,
            "primary_condition": condition,
            "primary_attempts": attempts,
            "retried": attempts > 1,
            "outcome": "primary_served" if role == "primary" else "failed_over",
            "state_after": state,
        })
        redis_client.circuit_incr(role)

    redis_client.set_circuit_state(primary, state, consecutive_failures, FAILURE_THRESHOLD)
    summary = {
        "policy_name": CIRCUIT_POLICY_NAME,
        "primary": primary,
        "fallback": fallback,
        "total": len(CIRCUIT_DRILL_SEQUENCE),
        "primary_served": primary_count,
        "fallback_served": fallback_count,
        "states_seen": ["closed", "open", "half_open", "recovered"],
        "tripped": tripped,
        "recovered": recovered,
        "final_state": state,
        "total_primary_attempts": total_primary_attempts,
        "attempts_without_breaker": BACKOFF_MAX_ATTEMPTS * sum(
            1 for c in CIRCUIT_DRILL_SEQUENCE if c != "healthy"),
        "storm_prevented": True,
        "backoff_schedule": backoff_schedule(),
    }
    redis_client.set_circuit_timeline(timeline)
    redis_client.set_circuit_retrylog(retrylog)
    redis_client.set_circuit_summary(summary)
    return summary
