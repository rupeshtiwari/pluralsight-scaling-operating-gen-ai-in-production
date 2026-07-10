"""Pydantic request/response contracts for the AI service layer.

These models are the *stable* shape the application depends on. No provider
specific field ever leaks past this boundary — that is the EO1a promise:
application code talks to ``RouteResponse`` and ``AdapterConfig``, never to a
vendor's raw payload.
"""
from __future__ import annotations

from pydantic import BaseModel, Field


class TokenEstimate(BaseModel):
    prompt: int
    completion: int
    total: int


class AdapterConfig(BaseModel):
    """The provider adapter contract (Clip 1) — one uniform shape per model."""

    model: str = Field(..., description="Provider/model identity")
    tier: str = Field(..., description="low_cost | balanced | premium")
    latency_target_ms: int = Field(..., description="Latency profile target")
    quota_mode: str = Field(..., description="shared | dedicated | reserved")
    cost_per_1k_usd: float = Field(..., description="Cost estimate basis")
    quality_score: float = Field(..., description="0.0 - 1.0 quality signal")
    status: str = Field(..., description="Live provider status")
    condition: str = Field(..., description="Active simulated condition")


class RouteRequest(BaseModel):
    prompt: str = Field(..., description="Caller input text")
    request_class: str = Field("standard", description="Caller-declared class")


class RouteResponse(BaseModel):
    request_id: str
    selected_model: str
    provider_tier: str
    provider_status: str
    route_reason: str
    latency_target_ms: int
    token_estimate: TokenEstimate
    cost_estimate_usd: float
    quality_score: float
    policy_name: str
