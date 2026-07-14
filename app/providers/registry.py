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

# --- Weighted routing policy (Clip 3) -------------------------------------
# Distribute traffic across tiers by percentage. The percentages sum to 100
# and every weight is a multiple of 10, so a deterministic sequence of length
# 10 reproduces the distribution exactly over any multiple of ten requests —
# making the weighted balancing fully repeatable, not random.
WEIGHTED_POLICY_NAME = "weighted"
WEIGHTED_WEIGHTS: dict[str, int] = {
    "econo-mini": 50,
    "balanced-std": 30,
    "premium-max": 20,
}


def weighted_sequence() -> list[str]:
    """A deterministic length-10 pick order that reflects WEIGHTED_WEIGHTS AND
    interleaves the tiers, so any short sample shows variety instead of five
    identical picks in a row. Even-spread (largest-deficit) selection: at each
    slot pick the tier furthest behind its target share.
    """
    total = sum(pct // 10 for pct in WEIGHTED_WEIGHTS.values())  # 10
    picked = {m: 0 for m in WEIGHTED_WEIGHTS}
    seq: list[str] = []
    for _ in range(total):
        n = len(seq) + 1
        best, best_deficit = None, None
        for model, pct in WEIGHTED_WEIGHTS.items():
            deficit = (pct / 100.0) * n - picked[model]
            if best is None or deficit > best_deficit + 1e-9:
                best, best_deficit = model, deficit
        seq.append(best)
        picked[best] += 1
    return seq

# --- Payload-based smart routing (Clip 5) ---------------------------------
# The route decision reads THREE independent signals, kept deliberately separate
# (size is not complexity, complexity is not risk):
#
#   size        — the token estimate of the prompt. Shown for cost/evidence; it
#                 does NOT by itself pick the tier (a long summary is still simple).
#   complexity  — a DECLARED task_class maps to a semantic complexity. This is
#                 what selects the tier, independent of length.
#   risk /      — a declared override_class deterministically pins the tier,
#   override      bypassing complexity routing on purpose (EO1d). Overrides run
#                 in two directions: economy (force cheaper) and risk (force
#                 stronger).
#
# EO1c — route each request to the tier its complexity calls for.
# EO1d — deterministic overrides that intentionally bypass the normal decision.
SMART_POLICY_NAME = "payload_smart"

# Declared task_class -> semantic complexity. Complexity is NOT derived from
# prompt length: a long doc summary is simple; a short bug-triage ask is complex.
TASK_COMPLEXITY: dict[str, str] = {
    "ticket_tag": "simple",
    "doc_summary": "simple",        # can be long, still simple
    "data_extract": "moderate",
    "bug_triage": "complex",        # can be short, still complex
    "incident_analysis": "complex",
}
DEFAULT_COMPLEXITY = "simple"

# Each complexity level maps to exactly one tier.
COMPLEXITY_TIERS: dict[str, str] = {
    "simple": "econo-mini",
    "moderate": "balanced-std",
    "complex": "premium-max",
}

# Size is a SEPARATE signal from complexity. This threshold only labels a prompt
# short/long for evidence and cost — it never selects the tier on its own.
SIZE_THRESHOLD_TOKENS = 60

# Deterministic override rules keyed by a declared override_class. Each pins a
# tier and carries its direction (economy = force cheaper, risk = force stronger)
# and the risk level it represents.
OVERRIDE_RULES: dict[str, dict] = {
    "bulk_batch": {"model": "econo-mini", "direction": "economy", "risk": "low"},
    "legal_review": {"model": "premium-max", "direction": "risk", "risk": "high"},
    "code_generation": {"model": "premium-max", "direction": "risk", "risk": "high"},
}


def task_complexity(task_class: str | None) -> str:
    """Map a declared task_class to its semantic complexity (never from length)."""
    return TASK_COMPLEXITY.get(task_class or "", DEFAULT_COMPLEXITY)


def size_label(total_tokens: int) -> str:
    """Label a prompt short/long by token estimate — evidence only, not the tier."""
    return "long" if total_tokens > SIZE_THRESHOLD_TOKENS else "short"


# Canonical cases the smart-routing validation replays — the five approved
# payload forms plus the two override directions. Each asserts the tier and
# reason, so the decision logic is provable and repeatable in CI.
SMART_VALIDATION_CASES: list[dict] = [
    {
        "name": "short_simple",
        "prompt": "Tag this support ticket by topic.",
        "task_class": "ticket_tag",
        "override_class": None,
        "expect_model": "econo-mini",
        "expect_reason": "complexity_simple",
    },
    {
        "name": "long_simple",
        "prompt": (
            "Summarize the following support thread into one paragraph. " * 8
        ),
        "task_class": "doc_summary",
        "override_class": None,
        "expect_model": "econo-mini",
        "expect_reason": "complexity_simple",
    },
    {
        "name": "short_complex",
        "prompt": "Identify the concurrency bug in this transaction protocol.",
        "task_class": "bug_triage",
        "override_class": None,
        "expect_model": "premium-max",
        "expect_reason": "complexity_complex",
    },
    {
        "name": "long_complex",
        "prompt": (
            "Analyze the attached quarterly incident report, correlate each "
            "outage with its root cause, summarize the customer impact per "
            "region, and recommend three concrete reliability improvements with "
            "estimated effort and expected risk reduction for the platform team."
        ),
        "task_class": "incident_analysis",
        "override_class": None,
        "expect_model": "premium-max",
        "expect_reason": "complexity_complex",
    },
    {
        "name": "high_risk_override",
        "prompt": "Confirm the retention clause wording in this contract.",
        "task_class": "ticket_tag",
        "override_class": "legal_review",
        "expect_model": "premium-max",
        "expect_reason": "override_legal_review",
    },
    {
        "name": "bulk_override",
        "prompt": (
            "Analyze the attached quarterly incident report, correlate each "
            "outage with its root cause, summarize the customer impact per "
            "region, and recommend three concrete reliability improvements with "
            "estimated effort and expected risk reduction for the platform team."
        ),
        "task_class": "incident_analysis",
        "override_class": "bulk_batch",
        "expect_model": "econo-mini",
        "expect_reason": "override_bulk_batch",
    },
]

# --- Admission control: rate limits + queue capacity (Module 2, Clip 2) ---
# Each model tier carries its own configured rate limit (immediate admits per
# window) and queue capacity (waiting slots), reflecting the provider quota mode
# it sits behind: a shared tier gets a generous limit, a reserved tier a tight
# one — so a burst can never exhaust a provider's quota (EO2a). A declared
# request_class labels the traffic class the limit applies to. These are the
# operator's knobs: raise them to absorb more, lower them to shed sooner.
ADMISSION_POLICY_NAME = "admission_control"

RATE_LIMITS: dict[str, dict] = {
    "econo-mini":   {"request_class": "bulk",        "rate_limit": 10, "queue_capacity": 20},
    "balanced-std": {"request_class": "interactive", "rate_limit": 6,  "queue_capacity": 10},
    "premium-max":  {"request_class": "critical",    "rate_limit": 3,  "queue_capacity": 4},
}
DEFAULT_SPIKE_MODEL = "balanced-std"


def classify_arrival(index: int, rate_limit: int, queue_capacity: int) -> str:
    """Map a 0-based arrival index to its admission disposition, deterministically.

    accepted — within the rate limit, served immediately
    delayed  — over the rate limit but within queue capacity, waits in the queue
    rejected — over queue capacity, fail fast with HTTP 429, nothing served
    """
    if index < rate_limit:
        return "accepted"
    if index < rate_limit + queue_capacity:
        return "delayed"
    return "rejected"


# --- Circuit breaker, fallback, and retry backoff (Module 2, Clip 3) -------
# A circuit breaker protects the caller from a failing provider. It moves
# through four states with visible thresholds:
#   closed    — healthy; requests flow to the primary
#   open      — too many consecutive failures; the primary is skipped (fail
#               fast) and traffic goes to a healthy fallback model
#   half_open — after a cooldown, one probe is allowed through to test recovery
#   closed    — a successful probe recovers the circuit (recovered)
CIRCUIT_POLICY_NAME = "circuit_breaker"
FAILURE_THRESHOLD = 3      # consecutive failures that trip the circuit open
COOLDOWN_PROBES = 1        # requests served by fallback before a half-open probe
SUCCESS_THRESHOLD = 1      # successful probes that close a half-open circuit

# When a primary tier is unsafe, traffic fails over to a healthy alternative.
FALLBACK_ROUTES: dict[str, str] = {
    "balanced-std": "econo-mini",
    "premium-max": "balanced-std",
    "econo-mini": "balanced-std",
}

# Exponential backoff for retrying a failing provider, tuned for LLM latency:
# a base delay doubled each attempt, capped, with deterministic jitter so the
# schedule is repeatable and bounded — no retry storm.
BACKOFF_BASE_MS = 200
BACKOFF_FACTOR = 2
BACKOFF_MAX_ATTEMPTS = 3    # cap: at most 3 tries, then fail over
BACKOFF_CAP_MS = 2000
# Deterministic per-attempt jitter (ms) — fixed, not random, so the demo repeats.
BACKOFF_JITTER_MS = (0, 30, 70)

# The conditions that count as a provider "failure" for the breaker.
FAILURE_CONDITIONS = {"error", "quota", "slow"}


def backoff_schedule() -> list[dict]:
    """The deterministic retry schedule: attempt number, base delay, jitter, and
    the effective wait — doubling each attempt, capped, bounded by the attempt
    limit so retries can never storm."""
    schedule = []
    for i in range(BACKOFF_MAX_ATTEMPTS):
        base = min(BACKOFF_BASE_MS * (BACKOFF_FACTOR ** i), BACKOFF_CAP_MS) if i else 0
        jitter = BACKOFF_JITTER_MS[i % len(BACKOFF_JITTER_MS)]
        schedule.append({
            "attempt": i + 1,
            "base_delay_ms": base,
            "jitter_ms": jitter,
            "wait_ms": base + jitter,
        })
    return schedule


# The deterministic circuit-breaker drill (Clip 3). A fixed sequence of requests
# against a primary that fails, then heals — so one run walks the full state
# journey closed -> open -> half_open -> recovered, repeatably. Each entry is the
# primary's condition for that request; the fallback stays healthy throughout.
CIRCUIT_DRILL_PRIMARY = "balanced-std"
# Six failures then two healthy calls: trips the breaker (3 consecutive fails),
# sheds while open, takes a half-open probe that fails and reopens, then a second
# probe that succeeds and recovers — every state exercised, storm visibly avoided.
CIRCUIT_DRILL_SEQUENCE = ["error", "error", "error", "error", "error", "error",
                          "healthy", "healthy"]


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
