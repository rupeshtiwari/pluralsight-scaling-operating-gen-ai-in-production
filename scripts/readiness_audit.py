#!/usr/bin/env python3
"""Production readiness audit (Module 3, Clip 6, Step 2).

Scores five readiness dimensions and prints a colour-coded rich table plus a
blocking-gap detail box for the one dimension that is not ready. Reads the
deterministic audit the service computes (GET /lifecycle/readiness/audit).

    python scripts/readiness_audit.py --format rich
"""
from __future__ import annotations

import argparse

from rich import box
from rich.panel import Panel
from rich.table import Table

from _richutil import console, get_json


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--format", default="rich", choices=["rich"])
    ap.parse_args()

    d = get_json("/lifecycle/readiness/audit")

    t = Table(title="PRODUCTION READINESS AUDIT", box=box.HEAVY_HEAD, title_style="bold")
    t.add_column("Dimension", style="bold")
    t.add_column("Score", justify="center")
    t.add_column("Status")
    t.add_column("Evidence")
    for r in d.get("rows", []):
        ready = r.get("status") == "ready"
        status = "[green]✅ READY[/]" if ready else "[red bold]\U0001f534 GAP[/]"
        t.add_row(str(r.get("dimension")), f"{r.get('score')}/{r.get('max')}",
                  status, str(r.get("evidence")))
    ready_n = d.get("ready_dimensions", 0)
    t.add_section()
    t.add_row("[bold]TOTAL[/]", f"[bold]{d.get('score')}/{d.get('max_score')}[/]",
              f"{ready_n}/5 READY", "")
    console.print(t)

    rs = d.get("redaction_sample") or {}
    if rs:
        cov = rs.get("coverage_pct")
        req = rs.get("required_pct")
        body = (
            f"[bold]Security:[/] PII redaction covers {cov}% of sampled traffic.\n\n"
            f"  Verified requests:   [green]{rs.get('verified_requests'):,} / {rs.get('total_requests'):,} ({cov}%)[/]\n"
            f"  Unverified requests:   [red bold]{rs.get('unverified_requests'):,} / {rs.get('total_requests'):,} "
            f"({100 - cov}%)[/]  ← NO REDACTION PROOF\n\n"
            f"  Example redaction:   {rs.get('raw')} → {rs.get('redacted')}  "
            f"([dim]{rs.get('rule')}[/])\n"
            f"  Required for READY:  [yellow]>= {req}% coverage[/]\n"
            f"  Gap to close:        [red]+{rs.get('gap_pp')} percentage points[/]\n\n"
            f"[bold]ACTION:[/] {rs.get('action')}"
        )
        console.print(Panel(body, title="⚠️  BLOCKING GAP DETAIL",
                            border_style="yellow", box=box.ROUNDED))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
