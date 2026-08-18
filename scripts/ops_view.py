#!/usr/bin/env python3
"""Rich renderer for the Module 3 Clip 6 operational endpoints (Steps 1 and 3).

Reads a JSON response on stdin and prints a colour-coded rich table:

    curl -s .../receipts/migration | python3 scripts/ops_view.py --type receipt
    curl -s .../admin/alerts       | python3 scripts/ops_view.py --type alert
"""
from __future__ import annotations

import argparse

from rich import box
from rich.panel import Panel
from rich.table import Table

from _richutil import console, read_stdin_json


def _receipt(d: dict) -> None:
    t = Table(title="MIGRATION COMPATIBILITY RECEIPT", box=box.DOUBLE_EDGE, title_style="bold")
    t.add_column("Check", style="bold")
    t.add_column("Result", justify="center")
    t.add_column("Measured")
    t.add_column("Threshold")
    for c in d.get("checks", []):
        ok = c.get("result") == "pass"
        res = "[green]✅ PASS[/]" if ok else "[red bold]❌ FAIL[/]"
        t.add_row(str(c.get("check")), res, str(c.get("measured")), str(c.get("threshold")))
    header = (
        f"[cyan bold]Receipt ID:[/]        {d.get('receipt_id')}\n"
        f"Retiring Model:    {d.get('retiring_model')}\n"
        f"Replacement Model: {d.get('replacement_model')}\n"
        f"Requests Migrated: {d.get('requests_migrated')}"
    )
    console.print(Panel(header, box=box.DOUBLE_EDGE, border_style="cyan"))
    console.print(t)
    disp = d.get("disposition")
    style = "green bold" if disp == "MIGRATED" else "red bold"
    console.print(f"[{style}]DISPOSITION: ✅ {disp}[/]" if disp == "MIGRATED"
                  else f"[{style}]DISPOSITION: ❌ {disp}[/]")


def _alert(d: dict) -> None:
    latest = d.get("latest", d)
    if not latest.get("fired"):
        console.print(Panel(
            f"[green]No alert fired.[/]  measured {latest.get('measured_ms', '?')}ms is within "
            f"the {latest.get('threshold_ms')}ms SLO — the control is a live threshold, not a canned response.",
            title="RUNBOOK ALERT", border_style="green", box=box.ROUNDED))
        return
    body = (
        f"Alert:           [red bold]{latest.get('alert')}[/]\n"
        f"Measured:        [red bold]{latest.get('measured_ms')} ms[/]\n"
        f"Threshold:       {latest.get('threshold_ms')} ms\n"
        f"Breach Window:   {latest.get('breach_window_s')} s\n"
        f"Action Taken:    [green]\U0001f7e2 {latest.get('action_taken')}[/]\n"
        f"Escalation:      {latest.get('escalation')}\n"
        f"Diagnosis Path:  {latest.get('diagnosis_path')}\n"
        f"Rollback:        {latest.get('rollback')}"
    )
    console.print(Panel(body, title="🚨 RUNBOOK ALERT FIRED",
                        border_style="red", box=box.HEAVY))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--type", required=True, choices=["receipt", "alert"])
    args = ap.parse_args()
    d = read_stdin_json()
    (_receipt if args.type == "receipt" else _alert)(d)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
