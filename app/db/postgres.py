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
-- Additive columns for admission control (Module 2, Clip 2); nullable so every
-- earlier receipt is unaffected. disposition is accepted/delayed/rejected;
-- request_class is the caller-declared traffic class.
ALTER TABLE receipts ADD COLUMN IF NOT EXISTS disposition TEXT;
ALTER TABLE receipts ADD COLUMN IF NOT EXISTS request_class TEXT;
-- Additive column for the circuit breaker (Module 2, Clip 3); the model a
-- request fell back FROM when the primary was unsafe. NULL for primary-served.
ALTER TABLE receipts ADD COLUMN IF NOT EXISTS fallback_from TEXT;
"""


def connect() -> psycopg.Connection:
    return psycopg.connect(settings.pg_dsn, autocommit=True)


def init_schema() -> None:
    with connect() as conn:
        conn.execute(DDL)


def insert_receipt(receipt: dict) -> None:
    # complexity / override_class (Clip 5) and disposition / request_class
    # (Module 2 Clip 2) are set only by their own policies; default them so
    # baseline and weighted receipts insert unchanged.
    receipt = {"complexity": None, "override_class": None,
               "disposition": None, "request_class": None,
               "fallback_from": None, **receipt}
    with connect() as conn:
        conn.execute(
            """
            INSERT INTO receipts (
                request_id, selected_model, provider_tier, provider_status,
                route_reason, latency_target_ms, prompt_tokens,
                completion_tokens, total_tokens, cost_estimate_usd,
                quality_score, policy_name, complexity, override_class,
                disposition, request_class, fallback_from
            ) VALUES (
                %(request_id)s, %(selected_model)s, %(provider_tier)s,
                %(provider_status)s, %(route_reason)s, %(latency_target_ms)s,
                %(prompt_tokens)s, %(completion_tokens)s, %(total_tokens)s,
                %(cost_estimate_usd)s, %(quality_score)s, %(policy_name)s,
                %(complexity)s, %(override_class)s,
                %(disposition)s, %(request_class)s, %(fallback_from)s
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


def count_by_disposition() -> dict[str, int]:
    """Count admission-control receipts grouped by disposition (accepted /
    delayed / rejected). Used by the Clip 2 demo to distinguish every request's
    fate straight from the durable record."""
    sql = ("SELECT disposition, count(*) FROM receipts "
           "WHERE disposition IS NOT NULL GROUP BY 1")
    with connect() as conn:
        return {k: int(v) for k, v in conn.execute(sql).fetchall()}


def dispositions_detail(limit_each: int = 2) -> list[dict]:
    """A few durable receipts per disposition, tagged so the demo can show
    accepted, delayed, and rejected requests side by side from PostgreSQL."""
    sql = """
        SELECT disposition, request_id, request_class, selected_model,
               provider_tier, total_tokens, cost_estimate_usd, provider_status
        FROM (
            SELECT *, row_number() OVER (PARTITION BY disposition
                                         ORDER BY created_at) AS rn
            FROM receipts WHERE disposition IS NOT NULL
        ) s WHERE rn <= %s
        ORDER BY CASE disposition
                   WHEN 'accepted' THEN 1 WHEN 'delayed' THEN 2 ELSE 3 END,
                 request_id
    """
    with connect() as conn:
        cur = conn.execute(sql, (limit_each,))
        cols = [d.name for d in cur.description]
        rows = [dict(zip(cols, row)) for row in cur.fetchall()]
    for r in rows:
        r["cost_estimate_usd"] = float(r["cost_estimate_usd"])
    return rows


def circuit_receipts() -> list[dict]:
    """Circuit-breaker receipts in order, tagged with what served each request
    (primary vs fallback) and the model it fell back from — the durable proof
    that failover happened and later recovered."""
    sql = """
        SELECT request_id, selected_model, provider_tier, route_reason,
               fallback_from, total_tokens, cost_estimate_usd, provider_status
        FROM receipts WHERE policy_name = 'circuit_breaker'
        ORDER BY created_at
    """
    with connect() as conn:
        cur = conn.execute(sql)
        cols = [d.name for d in cur.description]
        rows = [dict(zip(cols, row)) for row in cur.fetchall()]
    for r in rows:
        r["cost_estimate_usd"] = float(r["cost_estimate_usd"])
    return rows


def clear_circuit_receipts() -> None:
    """Remove prior circuit-breaker receipts so re-running the drill is
    idempotent and the failover reconciliation always matches the latest run."""
    with connect() as conn:
        conn.execute("DELETE FROM receipts WHERE policy_name = 'circuit_breaker'")


def count_circuit_roles() -> dict[str, int]:
    """Count circuit receipts by serving role: primary (fallback_from IS NULL)
    vs fallback (fallback_from set)."""
    sql = """
        SELECT CASE WHEN fallback_from IS NULL THEN 'primary' ELSE 'fallback' END
                 AS role, count(*)
        FROM receipts WHERE policy_name = 'circuit_breaker' GROUP BY 1
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
