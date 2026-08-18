"""Deprecation migration via the replacement adapter (Module 3, Clip 6, Step 1).

Deterministic and in-memory — no external calls. The hands-on Step 1 flow:

  1. POST /admin/deprecate {model, replacement}  activates a route-swap
  2. k6 sends 12 requests to POST /v1/completions  (model = the deprecated one)
  3. the adapter routes each to the replacement and records it
  4. GET /receipts/migration  aggregates the recorded requests into a compatibility
     receipt with four checks and a MIGRATED/BLOCKED disposition

The replacement stub returns a fixed result, so 12 requests always produce the same
receipt — the demo reproduces identically on every take.
"""
from __future__ import annotations

# Route-swap state + the recorded migration requests (reset by /admin/deprecate).
_MIG: dict = {"deprecated": None, "replacement": None, "requests": []}

# The deterministic per-request result the replacement returns through the adapter.
_RESULT = {"latency_ms": 52, "cost_per_1k_usd": 0.24, "quality_pct": 94.2,
           "contract_ok": True}


def deprecate(model: str, replacement: str) -> dict:
    """Activate the replacement adapter: traffic to ``model`` now routes to
    ``replacement`` through the uniform contract. Resets the request log so a
    re-run produces a clean 12-request receipt."""
    _MIG.update({"deprecated": model, "replacement": replacement, "requests": []})
    return {
        "status": "adapter_active",
        "deprecated": model,
        "replacement": replacement,
        "note": "traffic to the deprecated model now routes to the replacement "
                "through the uniform adapter contract — caller code is unchanged",
    }


def complete(model: str) -> dict:
    """A completion request. If it targets the deprecated model, the adapter routes
    it to the replacement and records a migration request with a deterministic
    result; otherwise it is served directly and not recorded."""
    migrated = model == _MIG["deprecated"] and _MIG["replacement"] is not None
    served = _MIG["replacement"] if migrated else model
    if migrated:
        _MIG["requests"].append({"requested_model": model, "served_model": served, **_RESULT})
    return {"model": served, "migrated": migrated, "output": "<deterministic completion>"}


def migration_receipt() -> dict:
    """Aggregate the recorded migration requests into a compatibility receipt."""
    reqs = _MIG["requests"]
    n = len(reqs)
    contract = bool(reqs) and all(r["contract_ok"] for r in reqs)
    p95 = max((r["latency_ms"] for r in reqs), default=0)
    cost = max((r["cost_per_1k_usd"] for r in reqs), default=0.0)
    quality = min((r["quality_pct"] for r in reqs), default=0.0)
    checks = [
        {"check": "output_contract", "result": "pass" if contract else "fail",
         "measured": f"{n}/{n}" if reqs else "0/0", "threshold": "100%"},
        {"check": "latency_within_slo", "result": "pass" if reqs and p95 <= 500 else "fail",
         "measured": f"P95: {p95}ms", "threshold": "<= 500ms"},
        {"check": "cost_within_budget", "result": "pass" if reqs and cost <= 0.35 else "fail",
         "measured": f"${cost:.2f}/1K", "threshold": "<= $0.35/1K"},
        {"check": "quality_above_baseline", "result": "pass" if reqs and quality >= 90 else "fail",
         "measured": f"{quality:.1f}%", "threshold": ">= 90%"},
    ]
    disposition = "MIGRATED" if reqs and all(c["result"] == "pass" for c in checks) else "BLOCKED"
    return {
        "receipt_id": "mig-2026-06-30-001",
        "retiring_model": _MIG["deprecated"],
        "replacement_model": _MIG["replacement"],
        "requests_migrated": n,
        "checks": checks,
        "disposition": disposition,
        "note": "the receipt aggregates the migrated requests into four compatibility "
                "checks — auditable proof the swap preserved the caller contract",
    }
