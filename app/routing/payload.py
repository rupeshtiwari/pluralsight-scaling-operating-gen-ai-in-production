"""Payload-based (smart) routing with deterministic overrides (Clip 5).

The decision reads three independent signals — kept separate on purpose:

* **size** — the prompt's token estimate. Shown for cost and evidence; it does
  not by itself select the tier (a long summary can still be simple).
* **complexity** — a DECLARED ``task_class`` maps to a semantic complexity. This
  is what selects the tier (EO1c), independent of length.
* **risk / override** — a declared ``override_class`` deterministically pins the
  tier, bypassing complexity routing on purpose (EO1d). Overrides run in two
  directions: *economy* (force cheaper) and *risk* (force stronger).

``smart_decision`` is a pure function of the declared payload metadata for a
given policy version, so it is reused by both the live endpoint (which persists
a receipt) and the validation endpoint (which asserts the logic).
"""
from __future__ import annotations

import uuid

from app.db import redis_client
from app.providers.adapter import adapter_config, estimate_cost, estimate_tokens
from app.providers.registry import (
    COMPLEXITY_TIERS,
    OVERRIDE_RULES,
    SMART_POLICY_NAME,
    size_label,
    task_complexity,
)
from app.schemas import RouteRequest, RouteResponse


def smart_decision(prompt: str, task_class: str | None,
                   override_class: str | None) -> dict:
    """Decide a tier from complexity, honouring deterministic overrides.

    Returns size (evidence), complexity (the tier driver), risk, the selected
    model and route reason, and — when an override fired — the tier complexity
    routing *would* have chosen plus the override direction. Pure: no Redis,
    no PostgreSQL, no network.
    """
    total_tokens = estimate_tokens(prompt).total
    size = size_label(total_tokens)
    complexity = task_complexity(task_class)
    complexity_model = COMPLEXITY_TIERS[complexity]

    rule = OVERRIDE_RULES.get(override_class or "")
    if rule is not None:
        model = rule["model"]
        return {
            "size": size,
            "complexity": complexity,
            "risk": rule["risk"],
            "selected_model": model,
            "route_reason": f"override_{override_class}",
            "would_have_selected": complexity_model if complexity_model != model else None,
            "override_class": override_class,
            "override_direction": rule["direction"],
        }
    return {
        "size": size,
        "complexity": complexity,
        "risk": "low",
        "selected_model": complexity_model,
        "route_reason": f"complexity_{complexity}",
        "would_have_selected": None,
        "override_class": None,
        "override_direction": None,
    }


def route_smart(request: RouteRequest) -> tuple[RouteResponse, dict]:
    """Route one request by complexity (with overrides) and build its receipt."""
    decision = smart_decision(request.prompt, request.task_class, request.override_class)
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
        size=decision["size"],
        complexity=decision["complexity"],
        risk=decision["risk"],
        task_class=request.task_class,
        override_class=decision["override_class"],
        override_direction=decision["override_direction"],
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
        "complexity": decision["complexity"],
        "override_class": decision["override_class"],
    }
    return response, receipt
