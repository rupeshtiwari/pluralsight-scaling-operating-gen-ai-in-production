"""Deterministic provider simulation and token/cost estimation.

No network egress ever happens here. A provider "call" is a pure function of
the input text and the adapter's pinned config, so every demo run reproduces
the same selected model, token estimate, and cost estimate. That determinism
is what makes the adapter layer testable in CI and repeatable on camera.
"""
from __future__ import annotations

from app.providers.registry import (
    BASE_ADAPTERS,
    CONDITIONS,
    DEFAULT_CONDITION,
    effective_quality,
    effective_status,
)
from app.schemas import AdapterConfig, TokenEstimate


def estimate_tokens(prompt: str) -> TokenEstimate:
    """Estimate prompt/completion/total tokens from input text, deterministically.

    ~4 characters per token is the standard rough heuristic; completion is
    modelled as 60% of the prompt so the total is stable per input.
    """
    prompt_tokens = max(1, (len(prompt) + 3) // 4)
    completion_tokens = max(1, round(prompt_tokens * 0.6))
    return TokenEstimate(
        prompt=prompt_tokens,
        completion=completion_tokens,
        total=prompt_tokens + completion_tokens,
    )


def estimate_cost(total_tokens: int, cost_per_1k_usd: float) -> float:
    return round((total_tokens / 1000.0) * cost_per_1k_usd, 6)


def adapter_config(model: str, condition: str) -> AdapterConfig:
    """Return the uniform adapter contract for one model under one condition."""
    base = BASE_ADAPTERS[model]
    return AdapterConfig(
        model=base.model,
        tier=base.tier,
        latency_target_ms=base.latency_target_ms,
        quota_mode=base.quota_mode,
        cost_per_1k_usd=base.cost_per_1k_usd,
        quality_score=effective_quality(base.quality_score, condition),
        status=effective_status(condition),
        condition=condition if condition in CONDITIONS else DEFAULT_CONDITION,
    )


def probe(model: str, condition: str) -> dict:
    """Deterministic local provider simulation — proof there is no external call.

    Returns a fixed, reproducible shape carrying the marker fields the demo
    reads on screen: ``external_api_calls`` is always 0 and ``deterministic``
    is always true.
    """
    base = BASE_ADAPTERS[model]
    cond = CONDITIONS.get(condition, CONDITIONS[DEFAULT_CONDITION])
    simulated_latency = int(base.latency_target_ms * cond["latency_multiplier"])
    return {
        "model": base.model,
        "condition": condition,
        "status": cond["status"],
        "simulated_latency_ms": simulated_latency,
        "external_api_calls": 0,
        "deterministic": True,
        "note": cond["note"],
    }
