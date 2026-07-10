"""Redis access for live provider conditions (and, later modules, counters).

The active condition per model lives in Redis so it survives across requests
and is repeatable: set it once, every subsequent route decision honours it
until reset.
"""
from __future__ import annotations

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


def ping() -> bool:
    return bool(client().ping())
