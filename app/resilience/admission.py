"""Deterministic admission control (Module 2, Clip 2).

Proves queuing, rate limiting, and fail-fast behaviour WITHOUT real
concurrency. A burst of N requests is classified against a tier's configured
rate limit and queue capacity by a pure function, so the accepted / delayed /
rejected split is identical on every run — testable in CI, repeatable on camera.

    accepted — admitted immediately, within the rate limit (served now)
    delayed  — over the rate limit but within queue capacity (waits in queue)
    rejected — over queue capacity: fail fast with HTTP 429, nothing served

Every request — including a reject — writes ONE durable receipt tagged with its
disposition, so the caller-facing outcome, the live Redis state, and the
PostgreSQL record all agree.
"""
from __future__ import annotations

import uuid

from app.db import postgres, redis_client
from app.providers.adapter import adapter_config, estimate_cost, estimate_tokens
from app.providers.registry import (
    ADMISSION_POLICY_NAME,
    RATE_LIMITS,
    classify_arrival,
)
from app.schemas import TokenEstimate

# One fixed reference prompt so token and cost estimates are deterministic.
SPIKE_PROMPT = "Summarize this customer support ticket into one sentence for triage."

_ZERO_TOKENS = TokenEstimate(prompt=0, completion=0, total=0)


def _receipt(model: str, disposition: str, request_class: str) -> dict:
    """Build one normalized receipt for an admitted, delayed, or rejected request.

    A rejected request was never served, so it costs nothing and produces no
    output: tokens, cost, quality, and latency target are all zero. That is what
    lets an operator tell a shed request apart from a served one in the ledger.
    """
    condition = redis_client.get_condition(model)
    cfg = adapter_config(model, condition)
    served = disposition != "rejected"

    tokens = estimate_tokens(SPIKE_PROMPT) if served else _ZERO_TOKENS
    cost = estimate_cost(tokens.total, cfg.cost_per_1k_usd) if served else 0.0
    quality = cfg.quality_score if served else 0.0
    latency = cfg.latency_target_ms if served else 0

    return {
        "request_id": f"req-{uuid.uuid4().hex[:12]}",
        "selected_model": cfg.model,
        "provider_tier": cfg.tier,
        "provider_status": cfg.status,
        "route_reason": f"admission_{disposition}",
        "latency_target_ms": latency,
        "prompt_tokens": tokens.prompt,
        "completion_tokens": tokens.completion,
        "total_tokens": tokens.total,
        "cost_estimate_usd": cost,
        "quality_score": quality,
        "policy_name": ADMISSION_POLICY_NAME,
        "disposition": disposition,
        "request_class": request_class,
    }


def run_spike(model: str, count: int, request_class: str | None) -> dict:
    """Run one deterministic burst against a tier and persist every receipt.

    Resets the resilience state first so the spike is repeatable, then classifies
    each arrival, writes its receipt, and updates the live Redis queue,
    rate-limit, and disposition state an operator watches.
    """
    cfg = RATE_LIMITS[model]
    rate, capacity = cfg["rate_limit"], cfg["queue_capacity"]
    rc = request_class or cfg["request_class"]

    redis_client.reset_resilience()
    counts = {"accepted": 0, "delayed": 0, "rejected": 0}
    for i in range(count):
        disposition = classify_arrival(i, rate, capacity)
        postgres.insert_receipt(_receipt(model, disposition, rc))
        redis_client.disposition_incr(disposition)
        counts[disposition] += 1

    admitted = min(count, rate)
    depth = counts["delayed"]  # requests left waiting in the queue
    redis_client.set_queue(model, depth=depth, peak=depth, capacity=capacity)
    redis_client.set_ratelimit(model, admitted=admitted, limit=rate)

    base = adapter_config(model, redis_client.get_condition(model))
    return {
        "policy_name": ADMISSION_POLICY_NAME,
        "model": model,
        "tier": base.tier,
        "request_class": rc,
        "submitted": count,
        "accepted": counts["accepted"],
        "delayed": counts["delayed"],
        "rejected": counts["rejected"],
        "rate_limit": rate,
        "queue_capacity": capacity,
        "queue_peak": depth,
        "queue_full": depth >= capacity,
    }


def submit_one(model: str, request_class: str | None) -> tuple[str, dict, dict]:
    """Submit ONE request against the current live queue state.

    Returns (disposition, receipt, state). If the rate-limit window still has
    room the request is accepted; else if the queue has room it is delayed;
    otherwise it is rejected — the fail-fast path the caller sees as HTTP 429.
    """
    cfg = RATE_LIMITS[model]
    rate, capacity = cfg["rate_limit"], cfg["queue_capacity"]
    rc = request_class or cfg["request_class"]

    rl = redis_client.get_ratelimit(model)
    q = redis_client.get_queue(model)
    admitted, depth = rl["admitted"], q["depth"]

    if admitted < rate:
        disposition = "accepted"
        redis_client.set_ratelimit(model, admitted=admitted + 1, limit=rate)
    elif depth < capacity:
        disposition = "delayed"
        depth += 1
        redis_client.set_queue(model, depth=depth,
                               peak=max(depth, q["peak"]), capacity=capacity)
    else:
        disposition = "rejected"

    receipt = _receipt(model, disposition, rc)
    postgres.insert_receipt(receipt)
    redis_client.disposition_incr(disposition)
    state = {"admitted": admitted, "rate_limit": rate,
             "queue_depth": depth, "queue_capacity": capacity}
    return disposition, receipt, state
