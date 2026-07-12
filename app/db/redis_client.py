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


def ping() -> bool:
    return bool(client().ping())
