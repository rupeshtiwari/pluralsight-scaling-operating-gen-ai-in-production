"""Weighted routing policy (Clip 3).

Distributes traffic across the three model tiers by their configured weights.
The pick order is a deterministic sequence indexed by a Redis counter, so the
distribution is reproducible from a clean start — weighted balancing you can
prove, not random sampling you have to trust.
"""
from __future__ import annotations

import uuid

from app.db import redis_client
from app.providers.adapter import adapter_config, estimate_cost, estimate_tokens
from app.providers.registry import WEIGHTED_POLICY_NAME, weighted_sequence
from app.schemas import RouteRequest, RouteResponse

ROUTE_REASON = "weighted_distribution"


def route_weighted(request: RouteRequest, seq_index: int) -> tuple[RouteResponse, dict]:
    """Route one request to the tier the weighted sequence selects at seq_index."""
    seq = weighted_sequence()
    model = seq[seq_index % len(seq)]

    condition = redis_client.get_condition(model)
    config = adapter_config(model, condition)
    tokens = estimate_tokens(request.prompt)
    cost = estimate_cost(tokens.total, config.cost_per_1k_usd)
    request_id = f"req-{uuid.uuid4().hex[:12]}"

    response = RouteResponse(
        request_id=request_id,
        selected_model=config.model,
        provider_tier=config.tier,
        provider_status=config.status,
        route_reason=ROUTE_REASON,
        latency_target_ms=config.latency_target_ms,
        token_estimate=tokens,
        cost_estimate_usd=cost,
        quality_score=config.quality_score,
        policy_name=WEIGHTED_POLICY_NAME,
    )
    receipt = {
        "request_id": request_id,
        "selected_model": config.model,
        "provider_tier": config.tier,
        "provider_status": config.status,
        "route_reason": ROUTE_REASON,
        "latency_target_ms": config.latency_target_ms,
        "prompt_tokens": tokens.prompt,
        "completion_tokens": tokens.completion,
        "total_tokens": tokens.total,
        "cost_estimate_usd": cost,
        "quality_score": config.quality_score,
        "policy_name": WEIGHTED_POLICY_NAME,
    }
    return response, receipt
