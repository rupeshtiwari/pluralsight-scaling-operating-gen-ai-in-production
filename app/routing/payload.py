"""Payload-based (smart) routing with deterministic overrides (Clip 5).

Two ideas, one endpoint:

* EO1c — route by the *payload itself*. A request's complexity is derived
  deterministically from its token estimate and mapped to the tier that fits:
  simple prompts to the low-cost model, involved ones to premium. The caller
  never names a model; the content decides.
* EO1d — deterministic overrides. Some request classes must land on a specific
  tier regardless of what the payload (or a weighted split) would choose. An
  override rule pins them, bypassing payload routing on purpose — the
  weighted-vs-deterministic trade-off made explicit.

The decision itself (:func:`smart_decision`) is a pure function of the payload,
so it is reused by both the live endpoint (which persists a receipt) and the
validation endpoint (which asserts the logic with no side effects).
"""
from __future__ import annotations

import uuid

from app.db import redis_client
from app.providers.adapter import adapter_config, estimate_cost, estimate_tokens
from app.providers.registry import (
    COMPLEXITY_TIERS,
    OVERRIDE_RULES,
    SMART_POLICY_NAME,
    classify_complexity,
)
from app.schemas import RouteRequest, RouteResponse


def smart_decision(prompt: str, request_class: str) -> dict:
    """Decide a tier from the payload, honouring deterministic overrides.

    Returns the selected model, the route reason, the complexity bucket, and —
    when an override fired — the tier payload routing *would* have chosen. Pure:
    no Redis, no PostgreSQL, no network.
    """
    total_tokens = estimate_tokens(prompt).total
    complexity = classify_complexity(total_tokens)
    payload_model = COMPLEXITY_TIERS[complexity]

    override_model = OVERRIDE_RULES.get(request_class)
    if override_model is not None:
        return {
            "selected_model": override_model,
            "route_reason": f"override_{request_class}",
            "complexity": complexity,
            "would_have_selected": (
                payload_model if payload_model != override_model else None
            ),
        }
    return {
        "selected_model": payload_model,
        "route_reason": f"payload_complexity_{complexity}",
        "complexity": complexity,
        "would_have_selected": None,
    }


def route_smart(request: RouteRequest) -> tuple[RouteResponse, dict]:
    """Route one request by its payload (with overrides) and build its receipt."""
    decision = smart_decision(request.prompt, request.request_class)
    model = decision["selected_model"]

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
        route_reason=decision["route_reason"],
        latency_target_ms=config.latency_target_ms,
        token_estimate=tokens,
        cost_estimate_usd=cost,
        quality_score=config.quality_score,
        policy_name=SMART_POLICY_NAME,
        complexity=decision["complexity"],
        would_have_selected=decision["would_have_selected"],
    )
    receipt = {
        "request_id": request_id,
        "selected_model": config.model,
        "provider_tier": config.tier,
        "provider_status": config.status,
        "route_reason": decision["route_reason"],
        "latency_target_ms": config.latency_target_ms,
        "prompt_tokens": tokens.prompt,
        "completion_tokens": tokens.completion,
        "total_tokens": tokens.total,
        "cost_estimate_usd": cost,
        "quality_score": config.quality_score,
        "policy_name": SMART_POLICY_NAME,
    }
    return response, receipt
