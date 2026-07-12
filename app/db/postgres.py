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
    policy_name       TEXT NOT NULL,
    complexity        TEXT,
    override_class    TEXT
);
-- Additive columns for smart routing (Clip 5); nullable so baseline/weighted
-- receipts are unaffected. Guarded for tables created before these existed.
ALTER TABLE receipts ADD COLUMN IF NOT EXISTS complexity TEXT;
ALTER TABLE receipts ADD COLUMN IF NOT EXISTS override_class TEXT;
"""


def connect() -> psycopg.Connection:
    return psycopg.connect(settings.pg_dsn, autocommit=True)


def init_schema() -> None:
    with connect() as conn:
        conn.execute(DDL)


def insert_receipt(receipt: dict) -> None:
    # complexity / override_class are set only by smart routing (Clip 5); default
    # them so baseline and weighted receipts insert unchanged.
    receipt = {"complexity": None, "override_class": None, **receipt}
    with connect() as conn:
        conn.execute(
            """
            INSERT INTO receipts (
                request_id, selected_model, provider_tier, provider_status,
                route_reason, latency_target_ms, prompt_tokens,
                completion_tokens, total_tokens, cost_estimate_usd,
                quality_score, policy_name, complexity, override_class
            ) VALUES (
                %(request_id)s, %(selected_model)s, %(provider_tier)s,
                %(provider_status)s, %(route_reason)s, %(latency_target_ms)s,
                %(prompt_tokens)s, %(completion_tokens)s, %(total_tokens)s,
                %(cost_estimate_usd)s, %(quality_score)s, %(policy_name)s,
                %(complexity)s, %(override_class)s
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


def count_by_kind() -> dict[str, int]:
    """Count receipts grouped by routing kind, derived from route_reason:
    weighted_distribution → weighted, complexity_* → payload, override_* →
    override. Used by the Clip 6 disposition to reconcile against Redis + API."""
    sql = """
        SELECT CASE
                 WHEN route_reason = 'weighted_distribution' THEN 'weighted'
                 WHEN route_reason LIKE 'override_%'          THEN 'override'
                 WHEN route_reason LIKE 'complexity_%'        THEN 'payload'
                 ELSE 'other'
               END AS kind, count(*)
        FROM receipts GROUP BY 1
    """
    with connect() as conn:
        return {k: int(v) for k, v in conn.execute(sql).fetchall()}


def inconsistent_receipts() -> int:
    """Count receipts whose policy_name disagrees with their route_reason kind
    (weighted_distribution must be policy 'weighted'; complexity_/override_ must
    be policy 'payload_smart'). Zero means policy and model behavior agree."""
    sql = """
        SELECT count(*) FROM receipts WHERE
          (route_reason = 'weighted_distribution' AND policy_name <> 'weighted')
          OR ((route_reason LIKE 'complexity_%' OR route_reason LIKE 'override_%')
              AND policy_name <> 'payload_smart')
    """
    with connect() as conn:
        return int(conn.execute(sql).fetchone()[0])


def ping() -> bool:
    with connect() as conn:
        return conn.execute("SELECT 1").fetchone()[0] == 1
