"""Provider adapter registry — the dedicated AI service layer (EO1a).

Three model tiers sit behind ONE uniform adapter contract. Application code
never imports a vendor SDK; it reads :class:`AdapterConfig` values only. Each
adapter also carries an *active simulated condition* so healthy, slow, error,
quota, quality, and deprecation scenarios are fully repeatable with no
external API call.
"""
from __future__ import annotations

from dataclasses import dataclass

# --- Base adapter configuration, one row per model tier -------------------
# These are the pinned, provider-agnostic contract values (Clip 1).


@dataclass(frozen=True)
class BaseAdapter:
    model: str
    tier: str
    latency_target_ms: int
    quota_mode: str
    cost_per_1k_usd: float
    quality_score: float


BASE_ADAPTERS: dict[str, BaseAdapter] = {
    "econo-mini": BaseAdapter(
        model="econo-mini",
        tier="low_cost",
        latency_target_ms=400,
        quota_mode="shared",
        cost_per_1k_usd=0.05,
        quality_score=0.82,
    ),
    "balanced-std": BaseAdapter(
        model="balanced-std",
        tier="balanced",
        latency_target_ms=700,
        quota_mode="dedicated",
        cost_per_1k_usd=0.30,
        quality_score=0.90,
    ),
    "premium-max": BaseAdapter(
        model="premium-max",
        tier="premium",
        latency_target_ms=1200,
        quota_mode="reserved",
        cost_per_1k_usd=1.20,
        quality_score=0.97,
    ),
}

# Baseline routing default for Clip 2 (weighted/payload routing arrive later).
DEFAULT_MODEL = "balanced-std"

# --- Supported deterministic conditions -----------------------------------
# Each condition maps to the status string shown on screen plus the way it
# bends the effective latency and quality so the simulation is repeatable.

CONDITIONS: dict[str, dict] = {
    "healthy": {
        "status": "healthy",
        "latency_multiplier": 1.0,
        "quality_delta": 0.0,
        "note": "normal operation, within latency target",
    },
    "slow": {
        "status": "degraded_slow",
        "latency_multiplier": 3.0,
        "quality_delta": 0.0,
        "note": "latency inflated beyond target",
    },
    "error": {
        "status": "error",
        "latency_multiplier": 1.0,
        "quality_delta": 0.0,
        "note": "provider returns a hard error",
    },
    "quota": {
        "status": "quota_exceeded",
        "latency_multiplier": 1.0,
        "quality_delta": 0.0,
        "note": "provider quota exhausted",
    },
    "quality": {
        "status": "quality_degraded",
        "latency_multiplier": 1.0,
        "quality_delta": -0.35,
        "note": "output quality below acceptance bar",
    },
    "deprecation": {
        "status": "deprecated",
        "latency_multiplier": 1.0,
        "quality_delta": 0.0,
        "note": "model version scheduled for sunset",
    },
}

DEFAULT_CONDITION = "healthy"


def effective_status(condition: str) -> str:
    return CONDITIONS.get(condition, CONDITIONS[DEFAULT_CONDITION])["status"]


def effective_quality(base_quality: float, condition: str) -> float:
    delta = CONDITIONS.get(condition, CONDITIONS[DEFAULT_CONDITION])["quality_delta"]
    return round(max(0.0, min(1.0, base_quality + delta)), 2)
