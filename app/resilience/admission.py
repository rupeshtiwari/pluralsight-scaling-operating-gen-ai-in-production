"""Admission control (Module 2, Clip 2).

Every request is admitted, queued, or rejected by ONE atomic Redis script, so
the decision is correct under real concurrent load (k6): the rate-limit counter
and the queue length are checked and updated together, and no two racing
requests can both pass a full queue. The queue is a real Redis LIST of request
IDs — actual queued work, not a depth counter — and every decision emits a
structured log event and a durable PostgreSQL receipt, so an operator can
correlate one request across the caller response, the log, and the ledger.

    accepted — within the rate limit, served now (HTTP 200)
    delayed  — over the limit, within queue capacity, parked in the queue (200)
    rejected — over queue capacity, fail fast (HTTP 429, Retry-After)

Costs shown for accepted/delayed requests are ESTIMATES for capacity planning;
a rejected request never reaches the model, so its tokens and cost are zero.
"""
from __future__ import annotations

import json
import logging
import uuid

from app.db import postgres, redis_client
from app.providers.adapter import adapter_config, estimate_cost, estimate_tokens
from app.providers.registry import (
    ADMISSION_POLICY_NAME,
    BASE_ADAPTERS,
    RATE_LIMITS,
    RATE_LIMIT_WINDOW_SECONDS,
    limiter_key,
)
from app.schemas import TokenEstimate

SPIKE_PROMPT = "Summarize this customer support ticket into one sentence for triage."
_ZERO_TOKENS = TokenEstimate(prompt=0, completion=0, total=0)

_HTTP = {"accepted": 200, "delayed": 200, "rejected": 429}
_REASON = {
    "accepted": "within rate limit",
    "delayed": "queued for capacity",
    "rejected": "Queue capacity exceeded",
}

# Real structured logs to stdout so `docker compose logs api` shows them, too.
_log = logging.getLogger("admission")
if not _log.handlers:
    _h = logging.StreamHandler()
    _h.setFormatter(logging.Formatter("%(message)s"))
    _log.addHandler(_h)
    _log.setLevel(logging.INFO)


def _receipt(model: str, disposition: str, request_class: str) -> dict:
    cfg = adapter_config(model, "healthy")
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


def submit_one(model: str, request_class: str | None) -> tuple[str, dict, dict]:
    """Atomically admit ONE request, persist its receipt, and log the decision.
    Returns (disposition, receipt, log_event)."""
    cfg = RATE_LIMITS[model]
    rate, capacity = cfg["rate_limit"], cfg["queue_capacity"]
    rc = request_class or cfg["request_class"]

    receipt = _receipt(model, "pending", rc)  # request_id first, decision next
    request_id = receipt["request_id"]
    disposition = redis_client.admit(model, rate, capacity, request_id)

    receipt["disposition"] = disposition
    receipt["route_reason"] = f"admission_{disposition}"
    if disposition == "rejected":
        receipt.update(latency_target_ms=0, prompt_tokens=0, completion_tokens=0,
                       total_tokens=0, cost_estimate_usd=0.0, quality_score=0.0)
    postgres.insert_receipt(receipt)
    redis_client.disposition_incr(disposition)

    event = {
        "event": "admission_decision",
        "request_id": request_id,
        "provider": cfg["provider"],
        "model": model,
        "tier": BASE_ADAPTERS[model].tier,
        "request_class": rc,
        "limiter_key": limiter_key(model),
        "rate_limit_count": redis_client.get_admitted(model),
        "rate_limit": rate,
        "queue_depth": redis_client.queue_depth(model),
        "queue_capacity": capacity,
        "disposition": disposition,
        "reason": _REASON[disposition],
        "http_status": _HTTP[disposition],
        "est_tokens": receipt["total_tokens"],
        "est_cost_usd": receipt["cost_estimate_usd"],
    }
    redis_client.log_admission(event)
    _log.info(json.dumps(event))
    return disposition, receipt, event


def run_spike(model: str, count: int, request_class: str | None) -> dict:
    """Deterministic internal spike: submit `count` requests through the SAME
    atomic path k6 uses, so preflight validation matches the live demo without
    requiring k6. Resets first for a repeatable run."""
    cfg = RATE_LIMITS[model]
    rc = request_class or cfg["request_class"]
    redis_client.reset_resilience()
    postgres.clear_admission_receipts()
    counts = {"accepted": 0, "delayed": 0, "rejected": 0}
    for _ in range(count):
        disposition, _, _ = submit_one(model, rc)
        counts[disposition] += 1
    return {
        "policy_name": ADMISSION_POLICY_NAME,
        "provider": cfg["provider"],
        "model": model,
        "tier": BASE_ADAPTERS[model].tier,
        "request_class": rc,
        "submitted": count,
        "accepted": counts["accepted"],
        "delayed": counts["delayed"],
        "rejected": counts["rejected"],
        "rate_limit": cfg["rate_limit"],
        "queue_capacity": cfg["queue_capacity"],
        "queue_depth": redis_client.queue_depth(model),
        "window_seconds": RATE_LIMIT_WINDOW_SECONDS,
        "queue_full": redis_client.queue_depth(model) >= cfg["queue_capacity"],
    }
