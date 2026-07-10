"""Runtime configuration for the GenAI AI service layer.

Every value is environment driven so the same application image runs under
Docker Compose (service hostnames ``redis`` / ``postgres``) and against a
native local stack (``127.0.0.1`` with custom ports) without code changes.
That environment-only wiring is what lets the service scale independently of
any model provider — the EO1a decoupling goal.
"""
from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    # --- Redis (routing counters, live provider conditions) ---------------
    redis_host: str = os.getenv("REDIS_HOST", "redis")
    redis_port: int = int(os.getenv("REDIS_PORT", "6379"))

    # --- PostgreSQL (request receipts) ------------------------------------
    pg_host: str = os.getenv("POSTGRES_HOST", "postgres")
    pg_port: int = int(os.getenv("POSTGRES_PORT", "5432"))
    pg_db: str = os.getenv("POSTGRES_DB", "genai")
    pg_user: str = os.getenv("POSTGRES_USER", "genai")
    pg_password: str = os.getenv("POSTGRES_PASSWORD", "genai")

    # --- Service identity -------------------------------------------------
    service_name: str = os.getenv("SERVICE_NAME", "genai-ai-service-layer")
    version: str = os.getenv("SERVICE_VERSION", "1.0.0")

    @property
    def pg_dsn(self) -> str:
        return (
            f"host={self.pg_host} port={self.pg_port} dbname={self.pg_db} "
            f"user={self.pg_user} password={self.pg_password}"
        )


settings = Settings()
