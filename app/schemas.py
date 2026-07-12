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


class BatchRequest(BaseModel):
    count: int = Field(20, ge=1, le=200, description="How many requests to route")
    prompt: str = Field(
        "Summarize this customer support ticket into one sentence for triage.",
        description="Prompt used for every request in the batch",
    )


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
    # Set only by payload-based smart routing (Clip 5). Left None by the
    # baseline and weighted policies so their responses are unchanged.
    complexity: str | None = Field(
        None, description="low | medium | high — payload complexity bucket"
    )
    would_have_selected: str | None = Field(
        None, description="Tier payload routing would have picked before an override"
    )
