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
# so the distribution is deterministic from a clean start. routing:count:<model>
# is the running tally per tier that proves the spread. routing:last_batch holds
# the samples from the most recent batch for inspection.

_SEQ_KEY = "routing:seq"
_LAST_BATCH_KEY = "routing:last_batch"


def _count_key(model: str) -> str:
    return f"routing:count:{model}"


def next_seq() -> int:
    """Return the next 0-based index into the weighted sequence."""
    return client().incr(_SEQ_KEY) - 1


def incr_count(model: str) -> None:
    client().incr(_count_key(model))


def routing_counts() -> dict[str, int]:
    c = client()
    return {m: int(c.get(_count_key(m)) or 0) for m in BASE_ADAPTERS}


def set_last_batch(data: dict) -> None:
    client().set(_LAST_BATCH_KEY, json.dumps(data))


def get_last_batch() -> dict:
    raw = client().get(_LAST_BATCH_KEY)
    return json.loads(raw) if raw else {}


def reset_routing() -> None:
    c = client()
    c.delete(_SEQ_KEY, _LAST_BATCH_KEY)
    for m in BASE_ADAPTERS:
        c.delete(_count_key(m))


def ping() -> bool:
    return bool(client().ping())
