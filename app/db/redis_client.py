"""Redis access for live provider conditions (and, later modules, counters).

The active condition per model lives in Redis so it survives across requests
and is repeatable: set it once, every subsequent route decision honours it
until reset.
"""
from __future__ import annotations

import json

import redis

from app.config import settings
from app.providers.registry import BASE_ADAPTERS, DEFAULT_CONDITION

_pool = redis.ConnectionPool(
    host=settings.redis_host, port=settings.redis_port, decode_responses=True
)


def client() -> redis.Redis:
    return redis.Redis(connection_pool=_pool)


def _key(model: str) -> str:
    return f"provider:condition:{model}"


def get_condition(model: str) -> str:
    return client().get(_key(model)) or DEFAULT_CONDITION


def set_condition(model: str, condition: str) -> None:
    client().set(_key(model), condition)


def all_conditions() -> dict[str, str]:
    return {m: get_condition(m) for m in BASE_ADAPTERS}


def reset_conditions() -> None:
    c = client()
    for m in BASE_ADAPTERS:
        c.set(_key(m), DEFAULT_CONDITION)


# --- Weighted routing counters (Clip 3) -----------------------------------
# routing:seq is a monotonically increasing index into the weighted sequence,
# so the distribution is deterministic from a clean start. routing:counters is
# a Redis HASH (one field per tier) that tallies the spread — stored as a hash
# so the demo can read it straight from the datastore with a single
# `redis-cli HGETALL routing:counters`. routing:last_batch holds the samples
# from the most recent batch for inspection.

_SEQ_KEY = "routing:seq"
_COUNTERS_KEY = "routing:counters"
_LAST_BATCH_KEY = "routing:last_batch"


def next_seq() -> int:
    """Return the next 0-based index into the weighted sequence."""
    return client().incr(_SEQ_KEY) - 1


def incr_count(model: str) -> None:
    client().hincrby(_COUNTERS_KEY, model, 1)


def routing_counts() -> dict[str, int]:
    raw = client().hgetall(_COUNTERS_KEY)
    return {m: int(raw.get(m, 0)) for m in BASE_ADAPTERS}


def set_last_batch(data: dict) -> None:
    client().set(_LAST_BATCH_KEY, json.dumps(data))


def get_last_batch() -> dict:
    raw = client().get(_LAST_BATCH_KEY)
    return json.loads(raw) if raw else {}


def reset_routing() -> None:
    client().delete(_SEQ_KEY, _COUNTERS_KEY, _LAST_BATCH_KEY)


# --- Smart routing counters (Clip 5) --------------------------------------
# smart:counters is a Redis HASH tallying decisions by dimension:
#   payload:<complexity>   — requests routed by declared complexity
#   override:<class>       — requests pinned by a deterministic override
#   weighted               — kept at 0; smart routing never takes the weighted
#                            path, so this is the cleanest proof it was bypassed.

_SMART_COUNTERS_KEY = "smart:counters"


def smart_incr(dimension: str) -> None:
    client().hincrby(_SMART_COUNTERS_KEY, dimension, 1)


def smart_counters() -> dict[str, int]:
    raw = client().hgetall(_SMART_COUNTERS_KEY)
    return {k: int(v) for k, v in raw.items()}


def reset_smart() -> None:
    c = client()
    c.delete(_SMART_COUNTERS_KEY)
    # Seed the weighted-path marker at 0 so HGETALL always shows it was bypassed.
    c.hset(_SMART_COUNTERS_KEY, "weighted", 0)


# --- Mixed-batch counters (Clip 6) ----------------------------------------
# mixed:counters tallies a mixed batch by ROUTING KIND (weighted / payload /
# override) so the aggregate can be reconciled against the API summary and the
# PostgreSQL receipts. mixed:last_batch holds the API summary + samples.

_MIXED_COUNTERS_KEY = "mixed:counters"
_MIXED_BATCH_KEY = "mixed:last_batch"


def mixed_incr(kind: str) -> None:
    client().hincrby(_MIXED_COUNTERS_KEY, kind, 1)


def mixed_counters() -> dict[str, int]:
    raw = client().hgetall(_MIXED_COUNTERS_KEY)
    return {k: int(v) for k, v in raw.items()}


def set_mixed_batch(data: dict) -> None:
    client().set(_MIXED_BATCH_KEY, json.dumps(data))


def get_mixed_batch() -> dict:
    raw = client().get(_MIXED_BATCH_KEY)
    return json.loads(raw) if raw else {}


def reset_mixed() -> None:
    client().delete(_MIXED_COUNTERS_KEY, _MIXED_BATCH_KEY)


# --- Admission control state (Module 2, Clip 2) ---------------------------
# The admission decision is made by ONE atomic Redis script so it is correct
# under real concurrent load (k6): the rate-limit counter and the queue length
# are read and updated in a single server-side step, so no two racing requests
# can both slip past a full queue. State lives in real datastore structures:
#   resilience:admitted:<model>  — INCR counter, the rate-limit window
#   resilience:queue:<model>     — a real LIST of queued request IDs (the backlog)
#   resilience:dispositions      — accepted / delayed / rejected tally (HASH)
#   resilience:logs              — structured admission-decision log events (LIST)

_RES_DISP_KEY = "resilience:dispositions"
_RES_LOGS_KEY = "resilience:logs"


def _admitted_key(model: str) -> str:
    return f"resilience:admitted:{model}"


def _queue_key(model: str) -> str:
    return f"resilience:queue:{model}"


# Atomic admission: within one Redis execution, admit if under the rate limit,
# else enqueue if the queue has room, else reject. Returns the disposition.
_ADMIT_LUA = """
local admitted = tonumber(redis.call('GET', KEYS[1]) or '0')
if admitted < tonumber(ARGV[1]) then
  redis.call('INCR', KEYS[1])
  return 'accepted'
end
if redis.call('LLEN', KEYS[2]) < tonumber(ARGV[2]) then
  redis.call('RPUSH', KEYS[2], ARGV[3])
  return 'delayed'
end
return 'rejected'
"""


def admit(model: str, rate_limit: int, queue_capacity: int, request_id: str) -> str:
    """Atomically decide accepted / delayed / rejected for one request."""
    return client().eval(
        _ADMIT_LUA, 2, _admitted_key(model), _queue_key(model),
        rate_limit, queue_capacity, request_id)


def get_admitted(model: str) -> int:
    return int(client().get(_admitted_key(model)) or 0)


def queue_depth(model: str) -> int:
    return int(client().llen(_queue_key(model)))


def queue_ids(model: str, limit: int = 25) -> list[str]:
    return client().lrange(_queue_key(model), 0, limit - 1)


def disposition_incr(disposition: str) -> None:
    client().hincrby(_RES_DISP_KEY, disposition, 1)


def disposition_hash() -> dict[str, str]:
    return client().hgetall(_RES_DISP_KEY)


def log_admission(event: dict) -> None:
    """Append one structured admission-decision log event (newest last)."""
    client().rpush(_RES_LOGS_KEY, json.dumps(event))


def get_admission_logs() -> list[dict]:
    raw = client().lrange(_RES_LOGS_KEY, 0, -1)
    return [json.loads(x) for x in raw]


def reset_resilience() -> None:
    c = client()
    keys = [_RES_DISP_KEY, _RES_LOGS_KEY]
    for m in BASE_ADAPTERS:
        keys.append(_admitted_key(m))
        keys.append(_queue_key(m))
    c.delete(*keys)


# --- Circuit breaker state (Module 2, Clip 3) -----------------------------
# The breaker's live state, the per-request timeline, the retry log, and a
# per-role tally (primary vs fallback) — the operator evidence the demo reads.

_CB_STATE_KEY = "circuit:state"
_CB_TIMELINE_KEY = "circuit:timeline"
_CB_RETRYLOG_KEY = "circuit:retrylog"
_CB_SUMMARY_KEY = "circuit:summary"
_CB_COUNTS_KEY = "circuit:counts"


def set_circuit_state(model: str, state: str, failures: int, threshold: int) -> None:
    client().hset(_CB_STATE_KEY, mapping={
        f"{model}:state": state, f"{model}:failures": failures,
        f"{model}:threshold": threshold})


def circuit_state_hash() -> dict[str, str]:
    return client().hgetall(_CB_STATE_KEY)


def set_circuit_timeline(data: list) -> None:
    client().set(_CB_TIMELINE_KEY, json.dumps(data))


def get_circuit_timeline() -> list:
    raw = client().get(_CB_TIMELINE_KEY)
    return json.loads(raw) if raw else []


def set_circuit_retrylog(data: list) -> None:
    client().set(_CB_RETRYLOG_KEY, json.dumps(data))


def get_circuit_retrylog() -> list:
    raw = client().get(_CB_RETRYLOG_KEY)
    return json.loads(raw) if raw else []


def set_circuit_summary(data: dict) -> None:
    client().set(_CB_SUMMARY_KEY, json.dumps(data))


def get_circuit_summary() -> dict:
    raw = client().get(_CB_SUMMARY_KEY)
    return json.loads(raw) if raw else {}


def circuit_incr(role: str) -> None:
    client().hincrby(_CB_COUNTS_KEY, role, 1)


def circuit_counts() -> dict[str, int]:
    raw = client().hgetall(_CB_COUNTS_KEY)
    return {k: int(v) for k, v in raw.items()}


def reset_circuit() -> None:
    client().delete(_CB_STATE_KEY, _CB_TIMELINE_KEY, _CB_RETRYLOG_KEY,
                    _CB_SUMMARY_KEY, _CB_COUNTS_KEY)


def ping() -> bool:
    return bool(client().ping())
