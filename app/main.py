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
from app.observability import observe
from app.incident import diagnose
from app.lifecycle import prompts as lc_prompts
from app.lifecycle import validation as lc_validation
from app.lifecycle import canary as lc_canary
from app.lifecycle import readiness as lc_readiness
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
    """Reconcile the three sources of truth the outline names: the CALLER
    response (the run summary), the fallback RECEIPT (PostgreSQL), and the RETRY
    LOG (the per-request attempt record). Confirmed only when the primary and
    fallback counts agree across all three and the circuit recovered."""
    summary = redis_client.get_circuit_summary()
    caller = {"primary": summary.get("primary_served", 0),
              "fallback": summary.get("fallback_served", 0)}
    receipts = postgres.count_circuit_roles()
    # The retry log's own tally: a request the primary served vs one that failed
    # over — derived from the durable retry record, not the run summary.
    retrylog = redis_client.get_circuit_retrylog()
    log_counts = {
        "primary": sum(1 for e in retrylog if e.get("outcome") == "primary_served"),
        "fallback": sum(1 for e in retrylog if e.get("outcome") == "failed_over"),
    }
    roles = {}
    for role in ("primary", "fallback"):
        c = int(caller.get(role, 0))
        p = int(receipts.get(role, 0))
        l = int(log_counts.get(role, 0))
        roles[role] = {"caller": c, "receipt": p, "retry_log": l,
                       "agree": c == p == l}
    counts_agree = all(v["agree"] for v in roles.values())
    recovered = bool(summary.get("recovered"))
    total = sum(caller.values())
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


# --- Observability: traces, logs, metrics, quality, SLOs (Module 2, Clip 5) --

@app.post("/observe/run")
def observe_run() -> dict:
    """Run the deterministic observed batch: emit OpenTelemetry traces, record
    Prometheus metrics, sample output quality, and evaluate the SLOs."""
    return observe.run_observe()


@app.get("/observe/trace")
def observe_trace() -> dict:
    """The end-to-end trace for one request: ingress, queue, routing, provider
    call, retry, fallback, response — with each span's duration."""
    return observe.state().get("trace", {})


@app.get("/observe/logs")
def observe_logs() -> dict:
    """Structured logs carrying request id, model, route reason, tokens, cost,
    latency, provider status, and quality status."""
    return {"logs": observe.state().get("logs", [])}


@app.get("/metrics")
def metrics() -> Response:
    """Real Prometheus exposition — the endpoint a Prometheus server scrapes."""
    from prometheus_client import CONTENT_TYPE_LATEST
    return Response(content=observe.metrics_exposition(), media_type=CONTENT_TYPE_LATEST)


@app.get("/observe/metrics")
def observe_metrics() -> dict:
    """The service metrics an operator watches — latency, availability, queue
    depth, fallback rate, retry rate, and cost — summarized for the demo view."""
    return observe.state().get("metrics", {})


@app.get("/observe/quality")
def observe_quality() -> dict:
    """Output quality sampling over a representative subset: schema, policy, and
    the reviewer reason behind each pass or fail."""
    return observe.state().get("quality", {})


@app.get("/observe/slo")
def observe_slo() -> dict:
    """SLO evaluation across latency, availability, and output quality, with the
    alert that fires when a dimension breaches its objective."""
    return observe.state().get("slo", {})


@app.get("/observe/diagnose")
def observe_diagnose() -> dict:
    """Root-cause a slow request: the trace's nested span timings point at the
    stage responsible for the latency."""
    return observe.state().get("diagnose", {})


@app.get("/observe/correlate")
def observe_correlate() -> dict:
    """Correlate one request's token count, cost, quality status, and the
    operator action from the structured record."""
    return observe.state().get("correlate", {})


# --- Incident diagnosis: the capstone (Module 2, Clip 6) -------------------

@app.post("/incident/run")
def incident_run() -> dict:
    """Trigger the deterministic incident: one provider fault (balanced-ai
    degraded) that lights up latency, quota, cost, and quality at once."""
    return diagnose.run_incident()


@app.get("/incident/alerts")
def incident_alerts() -> dict:
    """The alert timeline — which SLO fired first. The first signal is a symptom,
    not the root cause."""
    return diagnose.state().get("alerts", {})


@app.get("/incident/dashboard")
def incident_dashboard() -> dict:
    """The operator dashboard: latency, quota saturation, cost per request, and
    quality pass rate, each baseline vs current against its objective."""
    return diagnose.state().get("dashboard", {})


@app.get("/incident/isolate")
def incident_isolate() -> dict:
    """Isolate the latency from one trace: queueing, retry, and fallback are
    innocent; the degraded provider call owns the time."""
    return diagnose.state().get("isolate", {})


@app.get("/incident/quota")
def incident_quota() -> dict:
    """The quota pressure: admission control sheds excess load with a 429 and a
    Retry-After, protecting the provider behind its quota."""
    return diagnose.state().get("quota", {})


@app.get("/incident/cost")
def incident_cost() -> dict:
    """The cost drift tied to its cause: retries and failover on the degraded
    provider, reconciled to the dollar."""
    return diagnose.state().get("cost", {})


@app.get("/incident/quality")
def incident_quality() -> dict:
    """The quality regression confirmed by sampling: grouped failure reasons that
    cluster on the degraded provider."""
    return diagnose.state().get("quality", {})


@app.get("/incident/action")
def incident_action() -> dict:
    """The root cause and the coordinated action: four alerts, one provider fault,
    one evidence-based decision per dimension."""
    return diagnose.state().get("action", {})


# --- LLMOps lifecycle: prompt versioning + rollback (Module 3, Clip 2) -----

@app.post("/lifecycle/prompts/run")
def lc_prompts_run() -> dict:
    """Read the real prompt repository and build the versioning/rollback state:
    receipts, candidate isolation, rollback, reproducibility, reconcile."""
    return lc_prompts.run_prompts()


@app.get("/lifecycle/prompts/registry")
def lc_prompts_registry() -> dict:
    """The prompt version registry: version ids, owners, fixtures, model pins,
    evaluation run ids, release tags, and lifecycle status."""
    return lc_prompts.state().get("registry", {})


@app.get("/lifecycle/prompts/receipts")
def lc_prompts_receipts() -> dict:
    """Request receipts, each linking a prompt version, model version, and
    evaluation run id to a release tag and result hash."""
    return lc_prompts.state().get("receipts", {})


@app.get("/lifecycle/prompts/isolation")
def lc_prompts_isolation() -> dict:
    """The candidate prompt change, deployed to an isolated lane that approved
    production traffic never reaches."""
    return lc_prompts.state().get("isolation", {})


@app.get("/lifecycle/prompts/rollback")
def lc_prompts_rollback() -> dict:
    """The rollback: production returns to the approved release id, targeting a
    retained, immutable version."""
    return lc_prompts.state().get("rollback", {})


@app.get("/lifecycle/prompts/reproducibility")
def lc_prompts_reproducibility() -> dict:
    """Replay the approved version with its preserved prompt, fixture, and model,
    and confirm the recomputed result hash matches the recorded one."""
    return lc_prompts.state().get("reproducibility", {})


@app.get("/lifecycle/prompts/reconcile")
def lc_prompts_reconcile() -> dict:
    """Reconcile the release state: active release matches approved, no candidate
    traffic in production, and the result reproduces → CONFIRMED / BLOCKED."""
    return lc_prompts.state().get("reconcile", {})


# --- LLMOps lifecycle: model baseline validation (Module 3, Clip 3) --------

@app.post("/lifecycle/validation/run")
def lc_validation_run() -> dict:
    """Evaluate every candidate model against the baseline gate (quality, latency,
    cost, failure rate, output-contract compliance) and build the report."""
    return lc_validation.run_validation()


@app.get("/lifecycle/validation/gate")
def lc_validation_gate() -> dict:
    """The baseline gate summary — the dimensions checked and each candidate's
    eligibility. Enforced by a real Pytest suite (tests/baseline)."""
    return lc_validation.state().get("gate", {})


@app.get("/lifecycle/validation/baseline")
def lc_validation_baseline() -> dict:
    """The approved baseline thresholds each candidate must clear, per dimension."""
    return lc_validation.state().get("baseline", {})


@app.get("/lifecycle/validation/pass")
def lc_validation_pass() -> dict:
    """The passing candidate — every dimension within its threshold, eligible for
    promotion."""
    return lc_validation.state().get("pass", {})


@app.get("/lifecycle/validation/fail")
def lc_validation_fail() -> dict:
    """The failing candidate — the dimensions that drifted past threshold, blocked
    from promotion."""
    return lc_validation.state().get("fail", {})


@app.get("/lifecycle/validation/decision")
def lc_validation_decision() -> dict:
    """The release decision per candidate — a candidate cannot become the default
    without clearing the baseline."""
    return lc_validation.state().get("decision", {})


@app.get("/lifecycle/validation/reconcile")
def lc_validation_reconcile() -> dict:
    """Reconcile: the default stays on the approved model; only a baseline-passing
    candidate is eligible → CONFIRMED / BLOCKED."""
    return lc_validation.state().get("reconcile", {})


# --- LLMOps lifecycle: canary promotion, hold, rollback (Module 3, Clip 5) --

@app.post("/lifecycle/canary/run")
def lc_canary_run() -> dict:
    """Build the canary state: start a 10% canary, watch its signals, evaluate the
    promotion criteria, and produce the promote and rollback decisions."""
    return lc_canary.run_canary()


@app.get("/lifecycle/canary/start")
def lc_canary_start() -> dict:
    """The canary start: 10% of eligible traffic shifted to the candidate release,
    with the blast radius bounded to that slice."""
    return lc_canary.state().get("start", {})


@app.get("/lifecycle/canary/watch")
def lc_canary_watch() -> dict:
    """The canary's live signals — quality, latency, cost, error rate, and contract
    compliance — next to the approved release."""
    return lc_canary.state().get("watch", {})


@app.get("/lifecycle/canary/criteria")
def lc_canary_criteria() -> dict:
    """The promotion criteria: every signal within threshold AND a receipt trail
    proving the exposure stayed bounded."""
    return lc_canary.state().get("criteria", {})


@app.get("/lifecycle/canary/promote")
def lc_canary_promote() -> dict:
    """The promote decision for a healthy canary — a staged ramp to the new
    default, each stage still watched."""
    return lc_canary.state().get("promote", {})


@app.get("/lifecycle/canary/rollback")
def lc_canary_rollback() -> dict:
    """The rollback decision for a degraded canary — production returns to the
    approved release, with the blast radius capped at the canary slice."""
    return lc_canary.state().get("rollback", {})


@app.get("/lifecycle/canary/reconcile")
def lc_canary_reconcile() -> dict:
    """Reconcile after rollback: production is on the approved release, canary
    exposure is zero, and the blast radius stayed bounded → CONFIRMED / BLOCKED."""
    return lc_canary.state().get("reconcile", {})


# --- LLMOps lifecycle: readiness audit + runbook (Module 3, Clip 6) --------

@app.post("/lifecycle/readiness/run")
def lc_readiness_run() -> dict:
    """Build the readiness state: deprecation migration, the readiness audit, the
    deployment decision, the pattern comparison, the runbook, and the maturity."""
    return lc_readiness.run_readiness()


@app.get("/lifecycle/readiness/deprecation")
def lc_readiness_deprecation() -> dict:
    """Manage an upstream deprecation: route to a replacement adapter with
    compatibility receipts, and minimal disruption."""
    return lc_readiness.state().get("deprecation", {})


@app.get("/lifecycle/readiness/audit")
def lc_readiness_audit() -> dict:
    """The readiness audit across scalability, observability, security, cost
    efficiency, and reliability."""
    return lc_readiness.state().get("audit", {})


@app.get("/lifecycle/readiness/decision")
def lc_readiness_decision() -> dict:
    """The deployment decision — the cloud-native pattern the workload calls for."""
    return lc_readiness.state().get("decision", {})


@app.get("/lifecycle/readiness/patterns")
def lc_readiness_patterns() -> dict:
    """Compare serverless, containers, and dedicated GPU on latency, throughput,
    warm start, and ownership."""
    return lc_readiness.state().get("patterns", {})


@app.get("/lifecycle/readiness/runbook")
def lc_readiness_runbook() -> dict:
    """The operational runbook: deploy, monitoring thresholds, incident response,
    rollback, and capacity planning."""
    return lc_readiness.state().get("runbook", {})


@app.get("/lifecycle/readiness/maturity")
def lc_readiness_maturity() -> dict:
    """The maturity decision — prototype, managed production, or scale-ready — with
    the evidence and the gaps to the next level."""
    return lc_readiness.state().get("maturity", {})


@app.get("/receipts")
def receipts(limit: int = 5) -> dict:
    rows = postgres.latest_receipts(limit)
    for r in rows:
        r["created_at"] = str(r["created_at"])
        r["cost_estimate_usd"] = float(r["cost_estimate_usd"])
        r["quality_score"] = float(r["quality_score"])
    return {"count": len(rows), "receipts": rows}
