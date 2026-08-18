"""Shared helpers for the Module 3 Clip 6 rich CLIs (readiness_audit,
workload_decision, maturity_check, ops_view).

Deterministic and dependency-light: fetches JSON from the local FastAPI service
with the stdlib (no httpx needed) and hands back a configured rich Console. The
API base defaults to http://localhost:8000 and can be overridden with API_BASE."""
from __future__ import annotations

import json
import os
import sys
import urllib.request

from rich.console import Console

API_BASE = os.environ.get("API_BASE", "http://localhost:8000")

# force_terminal keeps ANSI colour when the output is piped or recorded.
console = Console(force_terminal=True)


def get_json(path: str) -> dict:
    """GET API_BASE+path and return parsed JSON, or exit with a clear message."""
    url = f"{API_BASE}{path}"
    try:
        with urllib.request.urlopen(url, timeout=5) as resp:
            return json.loads(resp.read().decode())
    except Exception as exc:  # noqa: BLE001 — surface any transport error clearly
        console.print(
            f"[red]Could not reach {url}[/] — is the stack up? "
            f"Start it with [green]bash module3/scripts/demo_up.sh[/].  ({exc})"
        )
        sys.exit(2)


def read_stdin_json() -> dict:
    """Parse JSON piped in on stdin (for the curl | script pattern)."""
    data = sys.stdin.read()
    try:
        return json.loads(data)
    except Exception:  # noqa: BLE001
        console.print("[red]No valid JSON on stdin.[/] Pipe a curl response into this script.")
        sys.exit(2)
