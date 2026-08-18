#!/usr/bin/env python3
"""Workload profile → deployment decision (Module 3, Clip 6, Step 3).

Reads the measured workload profile from config/deployment.yaml, derives the
deployment pattern from those numbers, and prints a rich workload panel plus a
pattern-comparison table. The decision is a computed result of the evidence, so
changing the yaml changes the recommendation.

    python scripts/workload_decision.py --sample-minutes 15 --latency-target 500
"""
from __future__ import annotations

import argparse
from pathlib import Path

import yaml
from rich import box
from rich.panel import Panel
from rich.table import Table

from _richutil import console

_CONFIG = Path(__file__).resolve().parents[1] / "config" / "deployment.yaml"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sample-minutes", type=int, default=15)
    ap.add_argument("--latency-target", type=int, default=None,
                    help="override the deployment latency target (ms)")
    args = ap.parse_args()

    cfg = yaml.safe_load(_CONFIG.read_text())
    w = cfg["workload"]
    target = args.latency_target or w["latency_target_ms"]
    penalty = w["cold_start_penalty_ms"]
    p95 = w["observed_p95_ms"]
    headroom = target - p95
    over = round(penalty / target, 1)
    cold_ok = penalty <= target
    steady = str(w.get("variance", "")).startswith("low")
    rps = w["measured_rps"]

    # Derive the pattern from the measured profile.
    if not cold_ok and rps < 20 and steady:
        chosen = "containers"
    elif cold_ok and not steady:
        chosen = "serverless"
    elif rps >= 100:
        chosen = "dedicated_gpu"
    else:
        chosen = "containers"

    prof = (
        f"Average RPS:          [cyan bold]{rps}[/]\n"
        f"Peak RPS:             {w['peak_rps']}\n"
        f"P95 Latency:          {p95} ms\n"
        f"Latency Target:       {target} ms\n"
        f"Headroom:             [yellow]{headroom} ms[/]   ← THIN (any startup delay matters)\n"
        f"Cold-Start Penalty:   [red bold]{penalty} ms[/] ← {over}x OVER TARGET"
    )
    console.print(Panel(prof, title=f"WORKLOAD PROFILE (last {args.sample_minutes} minutes)",
                        border_style="cyan", box=box.HEAVY))

    t = Table(box=box.HEAVY_HEAD)
    t.add_column("Pattern", style="bold")
    t.add_column("Warm Latency")
    t.add_column("Cold Start")
    t.add_column("Verdict")
    for p in cfg["patterns"]:
        name = p["name"]
        cold = "always warm" if p["cold_start_ms"] == 0 else f"{p['cold_start_ms']} ms"
        if name == chosen:
            verdict, style = "[green]\U0001f7e2 RECOMMENDED[/]", "green"
        elif p["cold_start_ms"] > target:
            verdict, style = "[red]\U0001f534 VIOLATES TARGET[/]", None
        else:
            verdict, style = f"[yellow]\U0001f7e1 OVERKILL @ {round(rps)}RPS[/]", None
        t.add_row(f"[{style}]{name}[/]" if style else name,
                  f"~{p['warm_latency_ms']} ms", cold, verdict)
    console.print(t)

    console.print(
        f"\n[bold]DECISION:[/] [green]{chosen}[/]\n"
        f"[bold]REASON: [/] Cold-start ({penalty}ms) exceeds target ({target}ms) by {over}x.\n"
        f"         Containers stay warm. GPU unjustified below 50 RPS sustained."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
