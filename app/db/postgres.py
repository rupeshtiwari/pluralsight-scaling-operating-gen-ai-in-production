"""PostgreSQL request receipts.

The receipts table is the decoupling proof (EO1a): every route decision is
persisted in ONE normalized, provider-agnostic shape. Whichever model served
the request, the receipt columns are identical, so downstream application
code never depends on a vendor's response shape.
"""
from __future__ import annotations

import psycopg

from app.config import settings

DDL = """
CREATE TABLE IF NOT EXISTS receipts (
    request_id        TEXT PRIMARY KEY,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    selected_model    TEXT NOT NULL,
    provider_tier     TEXT NOT NULL,
    provider_status   TEXT NOT NULL,
    route_reason      TEXT NOT NULL,
    latency_target_ms INTEGER NOT NULL,
    prompt_tokens     INTEGER NOT NULL,
    completion_tokens INTEGER NOT NULL,
    total_tokens      INTEGER NOT NULL,
    cost_estimate_usd NUMERIC(12,6) NOT NULL,
    quality_score     NUMERIC(4,2) NOT NULL,
    policy_name       TEXT NOT NULL
);
"""


def connect() -> psycopg.Connection:
    return psycopg.connect(settings.pg_dsn, autocommit=True)


def init_schema() -> None:
    with connect() as conn:
        conn.execute(DDL)


def insert_receipt(receipt: dict) -> None:
    with connect() as conn:
        conn.execute(
            """
            INSERT INTO receipts (
                request_id, selected_model, provider_tier, provider_status,
                route_reason, latency_target_ms, prompt_tokens,
                completion_tokens, total_tokens, cost_estimate_usd,
                quality_score, policy_name
            ) VALUES (
                %(request_id)s, %(selected_model)s, %(provider_tier)s,
                %(provider_status)s, %(route_reason)s, %(latency_target_ms)s,
                %(prompt_tokens)s, %(completion_tokens)s, %(total_tokens)s,
                %(cost_estimate_usd)s, %(quality_score)s, %(policy_name)s
            )
            ON CONFLICT (request_id) DO NOTHING
            """,
            receipt,
        )


def latest_receipts(limit: int = 5) -> list[dict]:
    with connect() as conn:
        cur = conn.execute(
            "SELECT * FROM receipts ORDER BY created_at DESC LIMIT %s", (limit,)
        )
        cols = [d.name for d in cur.description]
        return [dict(zip(cols, row)) for row in cur.fetchall()]


def count_receipts() -> int:
    with connect() as conn:
        return conn.execute("SELECT count(*) FROM receipts").fetchone()[0]


def clear_receipts() -> None:
    with connect() as conn:
        conn.execute("TRUNCATE receipts")


def ping() -> bool:
    with connect() as conn:
        return conn.execute("SELECT 1").fetchone()[0] == 1
