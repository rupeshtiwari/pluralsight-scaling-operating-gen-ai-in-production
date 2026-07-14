"""FastAPI AI service layer — the dedicated boundary between application code
and model providers (TO1, EO1a).

Endpoints used by the Module 1 / Clip 2 demo:

    GET  /health                  stack + provider-stub readiness
    GET  /providers               uniform adapter contract, one row per model
    GET  /providers/{model}/probe deterministic local simulation (no egress)
    GET  /providers/conditions    active + supported condition matrix
    POST /route                   baseline decision, writes a normalized receipt
    GET  /receipts                normalized receipts (also queried via psql)

Later clips add weighted routing (Clip 3: /routing/policy, /route/batch,
/routing/counters, /routing/validate) and payload-based smart routing with
deterministic overrides (Clip 5: /routing/rules, /route/smart,
/routing/smart-validate).
"""
from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Response

from app.config import settings
from app.db import postgres, redis_client
from app.providers.adapter import adapter_config, estimate_cost, estimate_tokens, probe
from app.providers.registry import (
    ADMISSION_POLICY_NAME,
    BACKOFF_MAX_ATTEMPTS,
    BASE_ADAPTERS,
    CIRCUIT_POLICY_NAME,
    COMPLEXITY_TIERS,
    CONDITIONS,
    COOLDOWN_PROBES,
    DEFAULT_MODEL,
    FAILURE_CONDITIONS,
    FAILURE_THRESHOLD,
    FALLBACK_ROUTES,
    OVERRIDE_RULES,
    RATE_LIMIT_WINDOW_SECONDS,
    RATE_LIMITS,
    SIZE_THRESHOLD_TOKENS,
    SMART_POLICY_NAME,
    SMART_VALIDATION_CASES,
    SUCCESS_THRESHOLD,
    TASK_COMPLEXITY,
    WEIGHTED_POLICY_NAME,
    WEIGHTED_WEIGHTS,
    backoff_schedule,
    limiter_key,
    weighted_sequence,
)
from app.resilience import admission, circuit
from app.routing.payload import route_smart, smart_decision
from app.routing.router import route
from app.routing.weighted import ROUTE_REASON as WEIGHTED_ROUTE_REASON
from app.routing.weighted import route_weighted
from app.schemas import BatchRequest, RouteRequest, SpikeRequest, SubmitRequest


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Ensure the receipts schema exists and conditions default to healthy so
    # the very first demo run is clean and repeatable.
    postgres.init_schema()
    try:
        redis_client.reset_conditions()
        redis_client.reset_smart()
        redis_client.reset_mixed()
        redis_client.reset_resilience()
        redis_client.reset_circuit()
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
    redis_client.reset_smart()
    redis_client.reset_mixed()
    redis_client.reset_resilience()
    redis_client.reset_circuit()
    return {"status": "reset", "receipts": postgres.count_receipts(),
            "conditions": redis_client.all_conditions()}


# --- Weighted routing (Clip 3) --------------------------------------------

# The prompt the batch routes by default — also the reference used to price each
# tier in the policy view, so the cost estimates match what the batch persists.
REFERENCE_PROMPT = "Summarize this customer support ticket into one sentence for triage."


@app.get("/routing/policy")
def routing_policy() -> dict:
    """The weighted policy AND the cost/latency targets that justify the weights:
    most traffic to the cheapest, lowest-latency tier; the least to the most
    expensive, highest-latency one."""
    ref_tokens = estimate_tokens(REFERENCE_PROMPT).total
    tiers = []
    for model, pct in WEIGHTED_WEIGHTS.items():
        base = BASE_ADAPTERS[model]
        tiers.append({
            "model": model,
            "weight_pct": pct,
            "latency_target_ms": base.latency_target_ms,
            "cost_per_1k_usd": base.cost_per_1k_usd,
            "cost_estimate_usd": estimate_cost(ref_tokens, base.cost_per_1k_usd),
        })
    return {
        "policy_name": WEIGHTED_POLICY_NAME,
        "weights": WEIGHTED_WEIGHTS,
        "reference_prompt": REFERENCE_PROMPT,
        "reference_total_tokens": ref_tokens,
        "tiers": tiers,
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


# --- Payload-based smart routing (Clip 5) ---------------------------------

@app.get("/routing/rules")
def routing_rules() -> dict:
    """The smart-routing rule table across three separate signals: prompt size
    (evidence only), declared task complexity (selects the tier), and the
    deterministic override classes that pin a tier and bypass the decision."""
    return {
        "policy_name": SMART_POLICY_NAME,
        "size_threshold_tokens": SIZE_THRESHOLD_TOKENS,
        "task_complexity": TASK_COMPLEXITY,
        "complexity_tiers": COMPLEXITY_TIERS,
        "overrides": OVERRIDE_RULES,
    }


@app.post("/route/smart")
def route_smart_request(request: RouteRequest) -> dict:
    """Route one request by declared complexity (with deterministic overrides),
    persist a receipt, and tally the decision dimension in Redis."""
    response, receipt = route_smart(request)
    postgres.insert_receipt(receipt)
    if response.override_class:
        redis_client.smart_incr(f"override:{response.override_class}")
    else:
        redis_client.smart_incr(f"payload:{response.complexity}")
    return response.model_dump()


@app.get("/routing/smart-counters")
def routing_smart_counters() -> dict:
    """Decision-dimension counters from Redis: how many requests were routed by
    complexity vs pinned by an override, and proof the weighted path was
    bypassed (weighted == 0)."""
    counts = redis_client.smart_counters()
    total = sum(v for k, v in counts.items() if k != "weighted")
    return {"policy_name": SMART_POLICY_NAME, "counters": counts, "total": total}


@app.get("/routing/smart-validate")
def routing_smart_validate() -> dict:
    """Replay the canonical cases through the pure decision logic and assert each
    lands on the expected tier and reason — no side effects, fully repeatable."""
    cases = []
    for c in SMART_VALIDATION_CASES:
        d = smart_decision(c["prompt"], c.get("task_class"), c.get("override_class"))
        model_ok = d["selected_model"] == c["expect_model"]
        reason_ok = d["route_reason"] == c["expect_reason"]
        cases.append({
            "name": c["name"],
            "size": d["size"],
            "complexity": d["complexity"],
            "override_class": d["override_class"],
            "expected_model": c["expect_model"],
            "selected_model": d["selected_model"],
            "route_reason": d["route_reason"],
            "match": model_ok and reason_ok,
        })
    return {
        "policy_name": SMART_POLICY_NAME,
        "total": len(cases),
        "all_match": all(c["match"] for c in cases),
        "cases": cases,
    }


# --- Mixed batch + final disposition (Clip 6) -----------------------------

def _mixed_sample(response, kind: str) -> dict:
    return {
        "request_id": response.request_id,
        "kind": kind,
        "policy_name": response.policy_name,
        "selected_model": response.selected_model,
        "provider_tier": response.provider_tier,
        "route_reason": response.route_reason,
    }


@app.post("/route/mixed")
def route_mixed() -> dict:
    """Run one mixed batch — weighted + payload + override — persisting every
    receipt and tallying by routing kind in Redis. Clip 6 reconciles this summary
    against the Redis counters and the PostgreSQL receipts."""
    by_kind = {"weighted": 0, "payload": 0, "override": 0}
    grouped: dict[str, list] = {"weighted": [], "payload": [], "override": []}

    # 10 weighted requests — deterministic 5 / 3 / 2 across the tiers.
    for i in range(10):
        response, receipt = route_weighted(RouteRequest(prompt=REFERENCE_PROMPT), i)
        postgres.insert_receipt(receipt)
        redis_client.mixed_incr("weighted"); by_kind["weighted"] += 1
        grouped["weighted"].append(_mixed_sample(response, "weighted"))

    # 4 payload + 2 override, from the canonical smart cases.
    for c in SMART_VALIDATION_CASES:
        req = RouteRequest(prompt=c["prompt"], task_class=c.get("task_class"),
                           override_class=c.get("override_class"))
        response, receipt = route_smart(req)
        postgres.insert_receipt(receipt)
        kind = "override" if response.override_class else "payload"
        redis_client.mixed_incr(kind); by_kind[kind] += 1
        grouped[kind].append(_mixed_sample(response, kind))

    # Interleave so a short sample shows all three kinds, not ten weighted rows.
    samples: list[dict] = []
    idx = 0
    while any(idx < len(grouped[k]) for k in grouped):
        for k in ("weighted", "payload", "override"):
            if idx < len(grouped[k]):
                samples.append(grouped[k][idx])
        idx += 1

    summary = {
        "total": sum(by_kind.values()),
        "by_kind": by_kind,
        "policies": sorted({s["policy_name"] for s in samples}),
        "samples": samples,
    }
    redis_client.set_mixed_batch(summary)
    return {"total": summary["total"], "by_kind": by_kind, "policies": summary["policies"]}


@app.get("/routing/mixed-batch")
def routing_mixed_batch(limit: int = 6) -> dict:
    data = redis_client.get_mixed_batch()
    if data.get("samples"):
        data = {**data, "samples": data["samples"][:limit]}
    return data


@app.get("/routing/mixed-counters")
def routing_mixed_counters() -> dict:
    counts = redis_client.mixed_counters()
    return {"counters": counts, "total": sum(counts.values())}


@app.get("/routing/disposition")
def routing_disposition() -> dict:
    """Reconcile the three sources of truth — the API summary, the Redis counters,
    and the PostgreSQL receipts — per routing kind, and confirm the operator
    decision only when all three agree and every receipt's policy is consistent
    with its route reason."""
    api = redis_client.get_mixed_batch().get("by_kind", {})
    redis_counts = redis_client.mixed_counters()
    receipts = postgres.count_by_kind()
    kinds = {}
    for k in ("weighted", "payload", "override"):
        a, r, p = int(api.get(k, 0)), int(redis_counts.get(k, 0)), int(receipts.get(k, 0))
        kinds[k] = {"api": a, "redis": r, "receipts": p, "agree": a == r == p}
    # The explicit, machine-checkable CONFIRMED contract:
    #   counts_agree        — API summary == Redis counters == receipt counts, per kind
    #   receipts_complete   — exactly one durable receipt per routed request (no missing/extra)
    #   policies_consistent — every receipt's policy matches its route_reason kind
    api_total = sum(int(v) for v in api.values())
    counts_agree = all(v["agree"] for v in kinds.values())
    receipts_complete = api_total > 0 and postgres.count_receipts() == api_total
    policies_consistent = postgres.inconsistent_receipts() == 0
    confirmed = counts_agree and receipts_complete and policies_consistent
    return {
        "kinds": kinds,
        "counts_agree": counts_agree,
        "receipts_complete": receipts_complete,
        "policies_consistent": policies_consistent,
        "disposition": "CONFIRMED" if confirmed else "BLOCKED",
    }


# --- Admission control: queues, rate limits, fail-fast (Module 2, Clip 2) --

def _limit_row(model: str, cfg: dict) -> dict:
    base = BASE_ADAPTERS[model]
    return {
        "provider": cfg["provider"],
        "model": model,
        "tier": base.tier,
        "quota_mode": base.quota_mode,
        "request_class": cfg["request_class"],
        "limiter_key": limiter_key(model),
        "rate_limit": cfg["rate_limit"],
        "queue_capacity": cfg["queue_capacity"],
    }


@app.get("/resilience/limits")
def resilience_limits() -> dict:
    """The admission-control configuration, keyed per provider / tier / request
    class: the rate limit (immediate admits per window), the window duration, the
    queue capacity (waiting slots), and the total burst absorbed before shedding."""
    rows = []
    for model, cfg in RATE_LIMITS.items():
        row = _limit_row(model, cfg)
        row["burst_capacity"] = cfg["rate_limit"] + cfg["queue_capacity"]
        rows.append(row)
    return {"policy_name": ADMISSION_POLICY_NAME,
            "window_seconds": RATE_LIMIT_WINDOW_SECONDS, "limits": rows}


@app.post("/load/spike")
def load_spike(body: SpikeRequest) -> dict:
    """Deterministic internal spike over the SAME atomic admission path k6 drives:
    submit `count` requests, absorb what fits the rate limit, queue what fits the
    backlog, shed the rest. Used by the preflight so it matches the live demo."""
    if body.model not in RATE_LIMITS:
        raise HTTPException(status_code=404, detail=f"unknown model: {body.model}")
    return admission.run_spike(body.model, body.count, body.request_class)


@app.get("/resilience/queue")
def resilience_queue(model: str = "balanced-std") -> dict:
    """The real queue for a tier, read from Redis — the actual list of queued
    request IDs plus the depth against capacity."""
    if model not in RATE_LIMITS:
        raise HTTPException(status_code=404, detail=f"unknown model: {model}")
    capacity = RATE_LIMITS[model]["queue_capacity"]
    depth = redis_client.queue_depth(model)
    return {
        "model": model,
        "queue_key": f"resilience:queue:{model}",
        "queued_request_ids": redis_client.queue_ids(model),
        "depth": depth,
        "capacity": capacity,
        "full": depth >= capacity > 0,
    }


@app.get("/resilience/rate-limit")
def resilience_rate_limit(model: str = "balanced-std") -> dict:
    """The live rate-limit window for a tier, read from Redis — admitted vs the
    configured limit, and the window duration that budget lasts."""
    if model not in RATE_LIMITS:
        raise HTTPException(status_code=404, detail=f"unknown model: {model}")
    limit = RATE_LIMITS[model]["rate_limit"]
    admitted = redis_client.get_admitted(model)
    return {
        "model": model,
        "limiter_key": limiter_key(model),
        "admitted": admitted,
        "limit": limit,
        "window_seconds": RATE_LIMIT_WINDOW_SECONDS,
        "at_limit": admitted >= limit > 0,
    }


@app.get("/resilience/matrix")
def resilience_matrix(count: int = 20) -> dict:
    """The rate-limit decision matrix: the SAME burst against every provider key,
    projected through each key's own limit — three providers, three request
    classes, three different accepted / delayed / rejected outcomes."""
    rows = []
    for model, cfg in RATE_LIMITS.items():
        rate, capacity = cfg["rate_limit"], cfg["queue_capacity"]
        accepted = min(count, rate)
        delayed = max(0, min(count - accepted, capacity))
        rejected = max(0, count - accepted - delayed)
        row = _limit_row(model, cfg)
        row.update(accepted=accepted, delayed=delayed, rejected=rejected)
        rows.append(row)
    return {"policy_name": ADMISSION_POLICY_NAME, "burst_size": count, "tiers": rows}


@app.post("/load/submit")
def load_submit(body: SubmitRequest, response: Response) -> dict:
    """Submit ONE request through the atomic admission path. Returns 200 when
    admitted or delayed; fails fast with HTTP 429 'Queue capacity exceeded' plus a
    Retry-After header when the queue is full — and persists a receipt either way."""
    if body.model not in RATE_LIMITS:
        raise HTTPException(status_code=404, detail=f"unknown model: {body.model}")
    disposition, receipt, event = admission.submit_one(body.model, body.request_class)
    payload = {
        "admitted": disposition != "rejected",
        "disposition": disposition,
        "reason": event["reason"],
        "request_id": receipt["request_id"],
        "provider": event["provider"],
        "model": body.model,
        "request_class": receipt["request_class"],
        "queue_depth": event["queue_depth"],
        "queue_capacity": event["queue_capacity"],
        "http_status": event["http_status"],
        "receipt_persisted": True,
    }
    if disposition == "rejected":
        payload["retry_after_seconds"] = RATE_LIMIT_WINDOW_SECONDS
        raise HTTPException(status_code=429, detail=payload,
                            headers={"Retry-After": str(RATE_LIMIT_WINDOW_SECONDS)})
    response.headers["X-Admission-Disposition"] = disposition
    return payload


@app.get("/resilience/dispositions")
def resilience_dispositions() -> dict:
    """Every request's fate straight from the PostgreSQL receipts, grouped by
    disposition — accepted, delayed, rejected — with a few sample rows each. Costs
    shown are estimates; a rejected request never runs, so its estimate is zero."""
    counts = postgres.count_by_disposition()
    for k in ("accepted", "delayed", "rejected"):
        counts.setdefault(k, 0)
    return {
        "policy_name": ADMISSION_POLICY_NAME,
        "total": sum(counts.values()),
        "dispositions": counts,
        "samples": postgres.dispositions_detail(limit_each=2),
    }


@app.get("/resilience/admission-logs")
def resilience_admission_logs(request_id: str | None = None) -> dict:
    """Structured admission-decision logs, and a correlation that proves one
    request ID appears in the caller response, the log, and the durable receipt."""
    logs = redis_client.get_admission_logs()
    samples = {}
    for e in logs:
        d = e.get("disposition")
        if d not in samples:
            samples[d] = e
    # Correlate: the given request_id, else the most recent rejected one.
    target = request_id
    if not target:
        rejected = [e for e in logs if e.get("disposition") == "rejected"]
        target = rejected[-1]["request_id"] if rejected else (logs[-1]["request_id"] if logs else None)
    log_event = next((e for e in logs if e.get("request_id") == target), None)
    receipt = postgres.receipt_by_request_id(target) if target else None
    correlate = {
        "request_id": target,
        "in_log": log_event is not None,
        "in_receipt": receipt is not None,
        "log_disposition": log_event.get("disposition") if log_event else None,
        "receipt_disposition": receipt.get("disposition") if receipt else None,
        "match": bool(log_event and receipt
                      and log_event.get("disposition") == receipt.get("disposition")),
    }
    return {
        "policy_name": ADMISSION_POLICY_NAME,
        "count": len(logs),
        "samples": [samples[k] for k in ("accepted", "delayed", "rejected") if k in samples],
        "correlate": correlate,
    }


# --- Circuit breaker, fallback, retry backoff (Module 2, Clip 3) ----------

@app.get("/resilience/circuit-config")
def resilience_circuit_config() -> dict:
    """The breaker's configured thresholds, the fallback routes, and the retry
    backoff schedule — the knobs that decide when to trip, where to fail over,
    and how long to wait between retries."""
    return {
        "policy_name": CIRCUIT_POLICY_NAME,
        "failure_modes": sorted(FAILURE_CONDITIONS),
        "failure_threshold": FAILURE_THRESHOLD,
        "cooldown_probes": COOLDOWN_PROBES,
        "success_threshold": SUCCESS_THRESHOLD,
        "max_attempts": BACKOFF_MAX_ATTEMPTS,
        "fallback_routes": FALLBACK_ROUTES,
        "backoff_schedule": backoff_schedule(),
    }


@app.post("/resilience/drill")
def resilience_drill() -> dict:
    """Run the deterministic circuit-breaker drill: a primary that fails then
    heals, driving the breaker through closed -> open -> half_open -> recovered
    while a healthy fallback keeps the caller served."""
    return circuit.run_drill()


@app.get("/resilience/circuit")
def resilience_circuit() -> dict:
    """The per-request state timeline from the drill — every transition, the
    model that served, and whether the primary or the fallback answered."""
    summary = redis_client.get_circuit_summary()
    return {
        "policy_name": CIRCUIT_POLICY_NAME,
        "primary": summary.get("primary"),
        "fallback": summary.get("fallback"),
        "tripped": summary.get("tripped"),
        "recovered": summary.get("recovered"),
        "final_state": summary.get("final_state"),
        "timeline": redis_client.get_circuit_timeline(),
    }


@app.get("/resilience/fallback")
def resilience_fallback() -> dict:
    """Fallback routing proof: how many requests the primary served vs how many
    a healthy alternative served while the primary was unsafe — with the caller
    kept whole throughout."""
    summary = redis_client.get_circuit_summary()
    primary_served = summary.get("primary_served", 0)
    fallback_served = summary.get("fallback_served", 0)
    total = primary_served + fallback_served
    return {
        "policy_name": CIRCUIT_POLICY_NAME,
        "primary": summary.get("primary"),
        "fallback": summary.get("fallback"),
        "requests_answered": total,
        "total": total,
        "caller_errors": 0,  # every request was served (primary or fallback)
        "primary_served": primary_served,
        "fallback_served": fallback_served,
        "counts": redis_client.circuit_counts(),
    }


@app.get("/resilience/retry-log")
def resilience_retry_log() -> dict:
    """The retry evidence: per request, how many primary attempts were made and
    the backoff between them — capped so a failing provider is retried, then
    failed over, never stormed. Once the circuit is open, zero primary attempts."""
    summary = redis_client.get_circuit_summary()
    return {
        "policy_name": CIRCUIT_POLICY_NAME,
        "max_attempts": BACKOFF_MAX_ATTEMPTS,
        "backoff_schedule": summary.get("backoff_schedule", backoff_schedule()),
        "total_primary_attempts": summary.get("total_primary_attempts"),
        "attempts_without_breaker": summary.get("attempts_without_breaker"),
        "storm_prevented": summary.get("storm_prevented"),
        "retrylog": redis_client.get_circuit_retrylog(),
    }


@app.get("/resilience/failover-reconcile")
def resilience_failover_reconcile() -> dict:
    """Reconcile the three sources of truth for the drill: the caller-facing
    summary, the Redis role tally, and the PostgreSQL receipts — confirmed only
    when the primary/fallback counts agree and the circuit recovered."""
    summary = redis_client.get_circuit_summary()
    api = {"primary": summary.get("primary_served", 0),
           "fallback": summary.get("fallback_served", 0)}
    redis_counts = redis_client.circuit_counts()
    receipts = postgres.count_circuit_roles()
    roles = {}
    for role in ("primary", "fallback"):
        a = int(api.get(role, 0))
        r = int(redis_counts.get(role, 0))
        p = int(receipts.get(role, 0))
        roles[role] = {"api": a, "redis": r, "receipts": p, "agree": a == r == p}
    counts_agree = all(v["agree"] for v in roles.values())
    recovered = bool(summary.get("recovered"))
    total = sum(api.values())
    receipts_complete = total > 0 and sum(receipts.values()) == total
    confirmed = counts_agree and recovered and receipts_complete
    return {
        "policy_name": CIRCUIT_POLICY_NAME,
        "roles": roles,
        "counts_agree": counts_agree,
        "recovered": recovered,
        "receipts_complete": receipts_complete,
        "disposition": "CONFIRMED" if confirmed else "BLOCKED",
    }


@app.get("/receipts")
def receipts(limit: int = 5) -> dict:
    rows = postgres.latest_receipts(limit)
    for r in rows:
        r["created_at"] = str(r["created_at"])
        r["cost_estimate_usd"] = float(r["cost_estimate_usd"])
        r["quality_score"] = float(r["quality_score"])
    return {"count": len(rows), "receipts": rows}
