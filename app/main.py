"""FastAPI AI service layer — the dedicated boundary between application code
and model providers (TO1, EO1a).

Endpoints used by the Module 1 / Clip 2 demo:

    GET  /health                  stack + provider-stub readiness
    GET  /providers               uniform adapter contract, one row per model
    GET  /providers/{model}/probe deterministic local simulation (no egress)
    GET  /providers/conditions    active + supported condition matrix
    POST /route                   baseline decision, writes a normalized receipt
    GET  /receipts                normalized receipts (also queried via psql)
"""
from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException

from app.config import settings
from app.db import postgres, redis_client
from app.providers.adapter import adapter_config, probe
from app.providers.registry import (
    BASE_ADAPTERS,
    CONDITIONS,
    DEFAULT_MODEL,
    WEIGHTED_POLICY_NAME,
    WEIGHTED_WEIGHTS,
    weighted_sequence,
)
from app.routing.router import route
from app.routing.weighted import ROUTE_REASON as WEIGHTED_ROUTE_REASON
from app.routing.weighted import route_weighted
from app.schemas import BatchRequest, RouteRequest


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Ensure the receipts schema exists and conditions default to healthy so
    # the very first demo run is clean and repeatable.
    postgres.init_schema()
    try:
        redis_client.reset_conditions()
    except Exception:
        pass
    yield


app = FastAPI(title=settings.service_name, version=settings.version, lifespan=lifespan)


@app.get("/health")
def health() -> dict:
    components = {}
    try:
        components["redis"] = "healthy" if redis_client.ping() else "unhealthy"
    except Exception:
        components["redis"] = "unhealthy"
    try:
        components["postgres"] = "healthy" if postgres.ping() else "unhealthy"
    except Exception:
        components["postgres"] = "unhealthy"
    # Provider stubs are in-process and deterministic — healthy if importable.
    components["provider_stubs"] = "healthy" if BASE_ADAPTERS else "unhealthy"
    components["fastapi"] = "healthy"
    overall = "healthy" if all(v == "healthy" for v in components.values()) else "unhealthy"
    return {
        "status": overall,
        "service": settings.service_name,
        "version": settings.version,
        "components": components,
    }


@app.get("/providers")
def providers() -> dict:
    rows = []
    for model in BASE_ADAPTERS:
        condition = redis_client.get_condition(model)
        cfg = adapter_config(model, condition)
        rows.append(cfg.model_dump())
    return {"count": len(rows), "default_model": DEFAULT_MODEL, "adapters": rows}


@app.get("/providers/conditions")
def conditions() -> dict:
    active = {m: redis_client.get_condition(m) for m in BASE_ADAPTERS}
    supported = {name: c["note"] for name, c in CONDITIONS.items()}
    return {
        "active": active,
        "supported": supported,
        "external_api_calls": 0,
        "deterministic": True,
    }


@app.get("/providers/{model}/probe")
def provider_probe(model: str) -> dict:
    if model not in BASE_ADAPTERS:
        raise HTTPException(status_code=404, detail=f"unknown model: {model}")
    condition = redis_client.get_condition(model)
    return probe(model, condition)


@app.post("/route")
def route_request(request: RouteRequest) -> dict:
    response, receipt = route(request)
    postgres.insert_receipt(receipt)
    return response.model_dump()


@app.post("/admin/reset")
def admin_reset() -> dict:
    """Bring the demo to a clean, repeatable state: no receipts, all healthy."""
    postgres.clear_receipts()
    redis_client.reset_conditions()
    redis_client.reset_routing()
    return {"status": "reset", "receipts": postgres.count_receipts(),
            "conditions": redis_client.all_conditions()}


# --- Weighted routing (Clip 3) --------------------------------------------

@app.get("/routing/policy")
def routing_policy() -> dict:
    return {
        "policy_name": WEIGHTED_POLICY_NAME,
        "weights": WEIGHTED_WEIGHTS,
        "sequence": weighted_sequence(),
    }


@app.post("/route/batch")
def route_batch(body: BatchRequest) -> dict:
    """Route `count` requests under the weighted policy; persist each receipt
    and tally per-tier counters. Returns a run summary; samples live in Redis
    for /routing/last-batch."""
    samples = []
    for _ in range(body.count):
        idx = redis_client.next_seq()
        response, receipt = route_weighted(RouteRequest(prompt=body.prompt), idx)
        postgres.insert_receipt(receipt)
        redis_client.incr_count(response.selected_model)
        samples.append({
            "request_id": response.request_id,
            "selected_model": response.selected_model,
            "provider_tier": response.provider_tier,
            "latency_target_ms": response.latency_target_ms,
            "cost_estimate_usd": response.cost_estimate_usd,
        })
    summary = {
        "policy_name": WEIGHTED_POLICY_NAME,
        "route_reason": WEIGHTED_ROUTE_REASON,
        "count": body.count,
        "samples": samples,
    }
    redis_client.set_last_batch(summary)
    return {"policy_name": WEIGHTED_POLICY_NAME,
            "route_reason": WEIGHTED_ROUTE_REASON, "count": body.count}


@app.get("/routing/last-batch")
def routing_last_batch(limit: int = 6) -> dict:
    data = redis_client.get_last_batch()
    if data.get("samples"):
        data = {**data, "samples": data["samples"][:limit]}
    return data


@app.get("/routing/counters")
def routing_counters() -> dict:
    counts = redis_client.routing_counts()
    return {"policy_name": WEIGHTED_POLICY_NAME,
            "counters": counts, "total": sum(counts.values())}


@app.get("/routing/validate")
def routing_validate() -> dict:
    counts = redis_client.routing_counts()
    total = sum(counts.values())
    tiers = {}
    for model, pct in WEIGHTED_WEIGHTS.items():
        expected = round(total * pct / 100)
        observed = counts.get(model, 0)
        tiers[model] = {"weight_pct": pct, "expected": expected,
                        "observed": observed, "match": observed == expected}
    return {"policy_name": WEIGHTED_POLICY_NAME, "total": total,
            "all_match": all(t["match"] for t in tiers.values()), "tiers": tiers}


@app.get("/receipts")
def receipts(limit: int = 5) -> dict:
    rows = postgres.latest_receipts(limit)
    for r in rows:
        r["created_at"] = str(r["created_at"])
        r["cost_estimate_usd"] = float(r["cost_estimate_usd"])
        r["quality_score"] = float(r["quality_score"])
    return {"count": len(rows), "receipts": rows}
