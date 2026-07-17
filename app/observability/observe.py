"""Observability instrumentation (Module 2, Clip 5).

Real OpenTelemetry spans, real Prometheus exposition, structured logs, output
quality sampling, and SLO evaluation — all deterministic on purpose. Span
durations come from fixed stage costs (not wall-clock), set as explicit span
timestamps, so a trace reproduces the same shape every run: testable in CI and
repeatable on camera. The spans are real OTel objects with real trace IDs, so
the identical data exports to an OpenTelemetry collector and Jaeger on the full
Docker stack; the terminal views read the same records.

What this proves (EO3a-e): one request is traceable end to end (EO3a); a
structured log carries the full operator field set (EO3b); a representative
sample separates a successful response from a trustworthy one (EO3c); SLOs turn
metrics into a go/no-go signal with alerting (EO3d); and the trace plus logs
pinpoint the root cause of a slow request (EO3e).
"""
from __future__ import annotations

import json
import logging
import os

from opentelemetry import trace as otel_trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import (
    SimpleSpanProcessor,
    SpanExporter,
    SpanExportResult,
)

SERVICE_NAME = "genai-ai-service-layer"

# --- Real OpenTelemetry tracer with an in-memory store --------------------


class _InMemoryExporter(SpanExporter):
    """Keep finished spans so the demo can render the trace tree in the terminal.
    On the full stack an OTLP exporter runs alongside this and ships the same
    spans to the collector and Jaeger."""

    def __init__(self) -> None:
        self.by_trace: dict[str, list] = {}

    def export(self, spans) -> SpanExportResult:
        for s in spans:
            tid = format(s.context.trace_id, "032x")
            self.by_trace.setdefault(tid, []).append(s)
        return SpanExportResult.SUCCESS

    def shutdown(self) -> None:  # pragma: no cover
        pass


_STORE = _InMemoryExporter()
_provider = TracerProvider(resource=Resource.create({"service.name": SERVICE_NAME}))
_provider.add_span_processor(SimpleSpanProcessor(_STORE))

# When the observability stack is up (the `obs` Compose profile sets
# OTEL_EXPORTER_OTLP_ENDPOINT), also ship every span to the OpenTelemetry
# collector, which forwards them to Jaeger — the same trace id the terminal
# shows then opens in the Jaeger UI. Optional and best-effort: the terminal
# demo works from the in-memory store with or without the collector.
_otlp_endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
if _otlp_endpoint:
    try:
        from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import (
            OTLPSpanExporter,
        )
        from opentelemetry.sdk.trace.export import BatchSpanProcessor
        _provider.add_span_processor(
            BatchSpanProcessor(OTLPSpanExporter(endpoint=_otlp_endpoint, insecure=True)))
    except Exception:
        pass

_tracer = _provider.get_tracer("genai.observe")

_log = logging.getLogger("observe")
if not _log.handlers:
    _h = logging.StreamHandler()
    _h.setFormatter(logging.Formatter("%(message)s"))
    _log.addHandler(_h)
    _log.setLevel(logging.INFO)

# A fixed base epoch (nanoseconds) so span timestamps are deterministic. The
# absolute value is irrelevant — only the per-span offsets set the durations.
_BASE_NS = 1_700_000_000_000_000_000
_MS = 1_000_000  # nanoseconds per millisecond


# --- The traced pipeline stages (deterministic costs, in ms) --------------
# Each scenario is a list of stages: (span_name, parent_name_or_None, cost_ms).
# The parent chain builds the ingress -> queue -> routing -> provider call ->
# retry -> fallback -> response tree the outline calls for.

def _healthy_stages(provider_ms: int) -> list[tuple]:
    return [
        ("request", None, None),           # root; end set to cover the whole trace
        ("ingress", "request", 2),
        ("queue", "request", 6),
        ("routing", "request", 3),
        ("provider_call", "request", provider_ms),
        ("response", "request", 1),
    ]


def _fallback_stages(primary_ms: int, backoff_ms: int, fallback_ms: int) -> list[tuple]:
    return [
        ("request", None, None),
        ("ingress", "request", 2),
        ("queue", "request", 6),
        ("routing", "request", 3),
        ("provider_call", "request", primary_ms),      # primary attempt, fails
        ("retry_backoff", "request", backoff_ms),      # exponential backoff wait
        ("fallback", "request", fallback_ms),          # healthy alternative serves
        ("response", "request", 1),
    ]


def _build_trace(stages: list[tuple]) -> tuple[str, list[dict]]:
    """Emit real, deterministically-timed OTel spans for one request; return the
    trace id and flat span records for terminal rendering."""
    # Compute sequential offsets so children lay out left-to-right under root.
    records: list[dict] = []
    cursor = 0
    # root span covers the sum of the child costs
    child_total = sum(c for _, p, c in stages if p is not None)
    root = _tracer.start_span("request", start_time=_BASE_NS)
    root_ctx = otel_trace.set_span_in_context(root)
    tid = format(root.get_span_context().trace_id, "032x")
    for name, parent, cost in stages:
        if parent is None:
            continue
        start = _BASE_NS + cursor * _MS
        end = _BASE_NS + (cursor + cost) * _MS
        span = _tracer.start_span(name, context=root_ctx, start_time=start)
        span.set_attribute("stage.cost_ms", cost)
        span.end(end_time=end)
        records.append({"span": name, "parent": "request", "start_ms": cursor,
                        "duration_ms": cost})
        cursor += cost
    root.end(end_time=_BASE_NS + child_total * _MS)
    records.insert(0, {"span": "request", "parent": None, "start_ms": 0,
                       "duration_ms": child_total})
    return tid, records


# --- Deterministic observed batch + metrics + quality + SLO ----------------
# A fixed population so every derived number reproduces exactly.
#   15 healthy   — served by the primary, ~712 ms
#    3 failover  — primary error, retry with backoff, fallback serves, ~1812 ms
#    2 slow      — primary degraded, ~2112 ms (breaches the latency budget)
# Two of the served responses fail quality sampling: a 200 OK that is not
# trustworthy — the point of output quality monitoring.
from prometheus_client import (  # noqa: E402
    CollectorRegistry,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
)

QUALITY_BAR = 0.85            # minimum acceptable output quality score
SLO_AVAILABILITY = 99.0       # percent
SLO_LATENCY_P95_MS = 2500     # milliseconds
SLO_QUALITY_PASS = 90.0       # percent of sampled responses that must pass

HEALTHY_MS, FAILOVER_MS, SLOW_MS = 712, 1812, 2112
_STATE: dict = {}


def _percentile(values: list[int], pct: float) -> int:
    s = sorted(values)
    k = max(0, min(len(s) - 1, round((pct / 100.0) * (len(s) - 1))))
    return s[k]


def _structured_log(rid: str, model: str, reason: str, tokens: dict, cost: float,
                    latency: int, status: str, quality: str) -> dict:
    ev = {
        "event": "request_observed", "request_id": rid, "model": model,
        "route_reason": reason, "prompt_tokens": tokens["p"],
        "completion_tokens": tokens["c"], "total_tokens": tokens["p"] + tokens["c"],
        "cost_usd": cost, "latency_ms": latency, "provider_status": status,
        "quality_status": quality,
    }
    _log.info(json.dumps(ev))
    return ev


def run_observe() -> dict:
    """Run the deterministic observed batch: emit traces, record Prometheus
    metrics, sample output quality, and evaluate the SLOs. Populates module
    state the demo endpoints read."""
    # Two exemplar traces: a failover request (all spans) and a slow request.
    fail_tid, fail_spans = _build_trace(_fallback_stages(1200, 200, 400))
    slow_tid, slow_spans = _build_trace(_healthy_stages(2100))

    latencies = [HEALTHY_MS] * 15 + [FAILOVER_MS] * 3 + [SLOW_MS] * 2
    total = len(latencies)
    fallbacks, retries, slow = 3, 3, 2
    queue_peak = 4
    per_cost = {HEALTHY_MS: 0.0081, FAILOVER_MS: 0.0052, SLOW_MS: 0.0081}
    cost_total = round(sum(per_cost[x] for x in latencies), 4)

    # Real Prometheus exposition (fresh registry each run keeps it deterministic).
    reg = CollectorRegistry()
    lat = Histogram("genai_request_latency_ms", "Request latency (ms)",
                    buckets=(250, 500, 750, 1000, 1500, 2000, 3000), registry=reg)
    reqs = Counter("genai_requests_total", "Requests", ["outcome"], registry=reg)
    fb = Counter("genai_fallbacks_total", "Fallback routings", registry=reg)
    rt = Counter("genai_retries_total", "Retry attempts", registry=reg)
    qd = Gauge("genai_queue_depth", "Queue depth (peak)", registry=reg)
    cost_c = Counter("genai_cost_usd_total", "Estimated cost (usd)", registry=reg)
    for x in latencies:
        lat.observe(x)
        reqs.labels(outcome="success").inc()
    fb.inc(fallbacks); rt.inc(retries); qd.set(queue_peak); cost_c.inc(cost_total)

    p50, p95 = _percentile(latencies, 50), _percentile(latencies, 95)
    availability = round(100.0 * total / total, 1)  # all answered (fallback covers)
    metrics = {
        "latency_p50_ms": p50, "latency_p95_ms": p95,
        "availability_pct": availability,
        "queue_depth": queue_peak,
        "fallback_rate_pct": round(100.0 * fallbacks / total, 1),
        "retry_rate_pct": round(100.0 * retries / total, 1),
        "cost_estimate_usd": cost_total,
        "requests": total,
    }

    # Output quality sampling: a representative subset gets automated checks.
    samples = [
        {"request_id": "req-6b1e9a2c47d0", "schema_valid": True, "policy_ok": True,
         "quality_score": 0.92, "reviewer_reason": "grounded, on-format"},
        {"request_id": "req-9f04d31ab8e5", "schema_valid": True, "policy_ok": True,
         "quality_score": 0.90, "reviewer_reason": "complete and accurate"},
        {"request_id": "req-2a7c55e1b93f", "schema_valid": True, "policy_ok": True,
         "quality_score": 0.55, "reviewer_reason": "hallucinated a policy number"},
        {"request_id": "req-c3d8e0f14a6b", "schema_valid": True, "policy_ok": True,
         "quality_score": 0.61, "reviewer_reason": "answer contradicts the source"},
        {"request_id": "req-77b2a9c6e310", "schema_valid": True, "policy_ok": True,
         "quality_score": 0.88, "reviewer_reason": "acceptable, minor omission"},
    ]
    for s in samples:
        s["quality_status"] = "pass" if s["quality_score"] >= QUALITY_BAR else "fail"
    passed = sum(1 for s in samples if s["quality_status"] == "pass")
    quality = {
        "policy": "output_quality_sampling",
        "sample_size": len(samples),
        "schema": "answer:str, citations:list, confidence:float",
        "passed": passed, "failed": len(samples) - passed,
        "pass_rate_pct": round(100.0 * passed / len(samples), 1),
        "quality_bar": QUALITY_BAR,
        "samples": samples,
    }

    # SLO evaluation: metrics become a go / no-go signal with alerting.
    def _slo(name, value, threshold, comparator, ok, sev, dim):
        return {"slo": name, "dimension": dim, "value": value,
                "threshold": threshold, "comparator": comparator,
                "status": "ok" if ok else "breach",
                "severity": "none" if ok else sev}
    slos = [
        _slo("availability", metrics["availability_pct"], SLO_AVAILABILITY, ">=",
             metrics["availability_pct"] >= SLO_AVAILABILITY, "page", "availability"),
        _slo("latency_p95", metrics["latency_p95_ms"], SLO_LATENCY_P95_MS, "<=",
             metrics["latency_p95_ms"] <= SLO_LATENCY_P95_MS, "ticket", "latency"),
        _slo("quality_pass_rate", quality["pass_rate_pct"], SLO_QUALITY_PASS, ">=",
             quality["pass_rate_pct"] >= SLO_QUALITY_PASS, "page", "output quality"),
    ]
    firing = [s for s in slos if s["status"] == "breach"]
    # Expose the quality pass rate as a real Prometheus gauge so the SLO alert
    # rule (observability/alerts.yml) evaluates against a genuine metric.
    Gauge("genai_quality_pass_rate", "Output quality pass rate (percent)",
          registry=reg).set(quality["pass_rate_pct"])

    # Structured logs for a few representative requests (EO3b).
    logs = [
        _structured_log("req-6b1e9a2c47d0", "balanced-std", "weighted_distribution",
                        {"p": 27, "c": 16}, 0.0081, HEALTHY_MS, "healthy", "pass"),
        _structured_log("req-4f18c0a7d2b9", "econo-mini", "circuit_fallback",
                        {"p": 27, "c": 16}, 0.0052, FAILOVER_MS, "healthy", "pass"),
        _structured_log("req-2a7c55e1b93f", "balanced-std", "weighted_distribution",
                        {"p": 31, "c": 19}, 0.0150, SLOW_MS, "degraded_slow", "fail"),
    ]

    # Diagnosis: the slow request's span breakdown pinpoints the latency source.
    slow_total = sum(s["duration_ms"] for s in slow_spans if s["parent"])
    provider_span = next(s for s in slow_spans if s["span"] == "provider_call")
    diagnose = {
        "trace_id": slow_tid,
        "total_ms": slow_total,
        "spans": [s for s in slow_spans if s["parent"]],
        "slowest_span": "provider_call",
        "slowest_ms": provider_span["duration_ms"],
        "slowest_share_pct": round(100.0 * provider_span["duration_ms"] / slow_total, 1),
        "provider_status": "degraded_slow",
        "root_cause": "provider latency, not queueing or retry",
    }

    # Correlation: one request ties tokens, cost, quality, and the operator action.
    correlate = {
        "request_id": "req-2a7c55e1b93f",
        "total_tokens": 50, "cost_usd": 0.0150,
        "quality_status": "fail", "quality_score": 0.55,
        "operator_action": "sampled, flagged for review, excluded from training set",
    }

    _STATE.update({
        "trace": {"trace_id": fail_tid, "total_ms": sum(s["duration_ms"] for s in fail_spans if s["parent"]),
                  "spans": fail_spans},
        "logs": logs,
        "metrics": metrics,
        "metrics_exposition": generate_latest(reg).decode(),
        "quality": quality,
        "slo": {"slos": slos, "firing": firing,
                "disposition": "ALERT" if firing else "OK",
                "note": "a response can be a 200 and still fail quality"},
        "diagnose": diagnose,
        "correlate": correlate,
    })
    return {"observed": total, "trace_id": fail_tid, "slow_trace_id": slow_tid,
            "firing_alerts": len(firing)}


def state() -> dict:
    return _STATE


def metrics_exposition() -> str:
    return _STATE.get("metrics_exposition", "")

