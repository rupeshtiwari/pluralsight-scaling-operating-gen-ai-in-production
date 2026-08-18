#!/usr/bin/env python3
"""Operational maturity assessment (Module 3, Clip 6, Step 4).

Combines the readiness audit and the accumulated receipts into a maturity level,
and prints the ladder, the proven capabilities, and the gaps to scale-ready with
the investment each one needs. Reads GET /lifecycle/readiness/maturity.

    python scripts/maturity_check.py --format rich
"""
from __future__ import annotations

import argparse

from rich import box
from rich.table import Table

from _richutil import console, get_json

_LEVEL_STYLE = {"prototype": "dim", "managed_production": "yellow bold", "scale_ready": "dim"}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--format", default="rich", choices=["rich"])
    ap.parse_args()

    d = get_json("/lifecycle/readiness/maturity")
    current = d.get("current")

    console.print(f"\n[bold]MATURITY ASSESSMENT[/]\n")
    console.print(f"  Current Level:  [yellow bold]\U0001f7e1 {str(current).replace('_', '-').upper()}[/]\n")

    ladder = Table(box=box.SIMPLE_HEAVY, show_header=False)
    for lvl in d.get("levels", []):
        mark = "  [yellow bold]▲ YOU ARE HERE[/]" if lvl == current else ""
        ladder.add_row(f"[{_LEVEL_STYLE.get(lvl, '')}]{lvl.replace('_', '-')}[/]{mark}")
    console.print(ladder)

    caps = Table(title="PROVEN CAPABILITIES", box=box.HEAVY_HEAD, title_style="bold green")
    caps.add_column("", justify="center")
    caps.add_column("Capability", style="bold")
    caps.add_column("Evidence")
    for c in d.get("proven_capabilities", []):
        caps.add_row("[green]✅[/]", str(c.get("capability")), str(c.get("evidence")))
    console.print(caps)

    gaps = Table(title="GAPS BLOCKING SCALE-READY", box=box.HEAVY_HEAD, title_style="bold red")
    gaps.add_column("", justify="center")
    gaps.add_column("Gap", style="bold")
    gaps.add_column("Investment needed")
    for g in d.get("gap_to_next", []):
        gaps.add_row("[red]\U0001f534[/]", str(g.get("gap")), str(g.get("investment")))
    console.print(gaps)

    console.print(
        "\n[bold]NEXT LEVEL (scale-ready) REQUIRES:[/]\n"
        "  Close all gaps. Each gap names the investment.\n"
        "  Do not claim scale-ready until the evidence exists.\n"
        f"\n[bold]DISPOSITION:[/] [yellow]{d.get('disposition')}[/]"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
