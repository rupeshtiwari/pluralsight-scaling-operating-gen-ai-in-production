"""Baseline routing decision for the adapter layer (Clip 2 scope).

Clip 2 proves the *adapter layer itself*: one dedicated service boundary,
one deterministic baseline decision, one normalized receipt. Weighted
distribution and payload-based overrides are separate policies introduced in
later clips, so this module intentionally applies only the baseline default.
"""
from __future__ import annotations

import uuid

from app.db import redis_client
from app.providers.adapter import (
    adapter_config,
    estimate_cost,
    estimate_tokens,
)
from app.providers.registry import DEFAULT_MODEL
from app.schemas import RouteRequest, RouteResponse

POLICY_NAME = "baseline"


def route(request: RouteRequest) -> tuple[RouteResponse, dict]:
    """Return the caller-facing response and the normalized receipt row."""
    model = DEFAULT_MODEL
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
        route_reason="baseline_default_tier",
        latency_target_ms=config.latency_target_ms,
        token_estimate=tokens,
        cost_estimate_usd=cost,
        quality_score=config.quality_score,
        policy_name=POLICY_NAME,
    )

    receipt = {
        "request_id": request_id,
        "selected_model": config.model,
        "provider_tier": config.tier,
        "provider_status": config.status,
        "route_reason": "baseline_default_tier",
        "latency_target_ms": config.latency_target_ms,
        "prompt_tokens": tokens.prompt,
        "completion_tokens": tokens.completion,
        "total_tokens": tokens.total,
        "cost_estimate_usd": cost,
        "quality_score": config.quality_score,
        "policy_name": POLICY_NAME,
    }
    return response, receipt
