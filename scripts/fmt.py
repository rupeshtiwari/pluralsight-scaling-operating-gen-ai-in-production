#!/usr/bin/env python3
"""Pluralsight-branded output formatter for the Scaling & Operating Gen AI demos.

Reads JSON on stdin and renders it with the Pluralsight brand palette so the
only thing on screen is what the narration reads. Every view carries a boxed
header (what we show + why), stars (★) the fields the learner should read,
shows full values with no truncation, and prints tokens as
prompt=N completion=N total=N.

    curl -s .../providers | python scripts/fmt.py --type providers
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
import textwrap
from typing import Any

# --- Pluralsight brand palette (ANSI true-color) --------------------------
PINK = "\033[38;2;255;22;117m"    # Transform Pink  - ★ marker / blocked / FAIL
LIME = "\033[38;2;207;255;110m"   # Lime Green      - healthy / PASS / true
LGRN = "\033[38;2;64;255;191m"    # Limited Green   - values / numbers / ids
BLUE = "\033[38;2;42;236;250m"    # Blue            - labels (field names)
ADA = "\033[38;2;41;130;111m"     # ADA Green       - secondary emphasis
GRAY = "\033[38;2;191;191;191m"   # Light Gray      - context / dim
WHITE = "\033[1;37m"              # White bold      - headings
RESET = "\033[0m"

_GOOD = {"healthy", "ok", "up", "pass", "true", "success", "accepted"}
_BAD = {"unhealthy", "down", "fail", "error", "quota_exceeded", "deprecated",
        "degraded_slow", "quality_degraded", "false", "rejected", "blocked"}


def _status_color(value: str) -> str:
    v = str(value).lower()
    if v in _GOOD:
        return LIME
    if v in _BAD:
        return PINK
    return LGRN


# Per-run header overrides from --title / --why (fall back to view defaults).
TITLE: str | None = None
WHY: str | None = None


def header(default_title: str, default_why: str) -> str:
    """View header, overridable per step with --title / --why."""
    return panel(TITLE or default_title, WHY or default_why)


def panel(title: str, why: str) -> str:
    """Boxed header: WHAT we show (white) + WHY we show it (blue). No truncation."""
    width = 74
    inner = width - 4
    top = "┌" + "─" * (width - 2) + "┐"
    bot = "└" + "─" * (width - 2) + "┘"

    def wrap(text: str) -> list[str]:
        return textwrap.wrap(text, width=inner, break_long_words=False,
                             break_on_hyphens=False) or [""]

    def row(text: str, color: str) -> str:
        pad = inner - len(text)
        return f"│ {color}{text}{RESET}{' ' * max(0, pad)} │"

    lines = [top]
    for ln in wrap(title):
        lines.append(row(ln, WHITE))
    for ln in wrap(why):
        lines.append(row(ln, BLUE))
    lines.append(bot)
    return "\n".join(lines)


def star(label: str, value: Any, color: str = LGRN) -> list[str]:
    """A highlighted, readable line + a trailing blank (the required padding)."""
    if isinstance(value, bool):
        value = str(value).lower()  # JSON fidelity: true / false
    return [f"  {PINK}★{RESET} {BLUE}{label}:{RESET} {color}{value}{RESET}", ""]


def ctx(label: str, value: Any) -> list[str]:
    """Dim context line (not narrated). No trailing blank."""
    return [f"    {GRAY}{label}: {value}{RESET}"]


def sect(text: str) -> list[str]:
    return [f"  {WHITE}{text}{RESET}", ""]


def tokens_line(est: dict) -> str:
    p = est.get("prompt", 0)
    c = est.get("completion", 0)
    t = est.get("total", p + c)
    if p == 0 and c == 0 and t == 0:
        body = f"{PINK}prompt=0{RESET}  {PINK}completion=0{RESET}  {PINK}total=0{RESET}"
    else:
        body = (f"{LGRN}prompt={p}{RESET}  {LGRN}completion={c}{RESET}  "
                f"{LGRN}total={t}{RESET}")
    return f"  {PINK}★{RESET} {BLUE}token_estimate:{RESET} {body}"


# --- Views ----------------------------------------------------------------

def fmt_health(d: dict) -> str:
    out = [header(
        "Bring the stack up and prove every layer is healthy (LO EO1a)",
        "Every layer of the dedicated AI service must be live before we route")]
    out += star("status", d.get("status"), _status_color(d.get("status", "")))
    comps = d.get("components", {})
    out += sect("components")
    for name in ("fastapi", "redis", "postgres", "provider_stubs"):
        if name in comps:
            out += star(name, comps[name], _status_color(comps[name]))
    return "\n".join(out)


def fmt_providers(d: dict) -> str:
    # One row per adapter so all three tiers fit on a single screen with no
    # scrolling. The teaching point is that every column is identical across
    # rows — the uniform contract — while the numbers differ per tier.
    out = [header(
        "Inspect the uniform adapter contract across three tiers (LO TO1, EO1a)",
        "The decoupling boundary: identical fields across every model")]
    out.append(f"  {PINK}★{RESET} {BLUE}default_model:{RESET} "
               f"{LGRN}{d.get('default_model')}{RESET}")
    out.append("")
    out.append(
        f"    {BLUE}{'model':<14}{'tier':<10}{'latency':<9}{'quota':<11}"
        f"{'cost/1k':<9}{'quality':<9}{'status'}{RESET}"
    )
    out.append("")  # gap between the header row and the first adapter
    for a in d.get("adapters", []):
        lat = f"{a['latency_target_ms']}ms"
        cost = f"${a['cost_per_1k_usd']:.2f}"
        qual = f"{a['quality_score']:.2f}"
        status = str(a["status"])
        scol = _status_color(status)
        out.append(
            f"  {PINK}★{RESET} {LGRN}{str(a['model']):<14}{str(a['tier']):<10}"
            f"{lat:<9}{str(a['quota_mode']):<11}{cost:<9}{qual:<9}{RESET}"
            f"{scol}{status}{RESET}"
        )
        out.append("")  # one blank line after each row so each is highlightable
    out.append("")  # extra breathing room before the shell prompt
    return "\n".join(out)


def fmt_probe(d: dict) -> str:
    out = [header(
        "Prove the adapter is a deterministic local simulation (LO EO1a)",
        "Zero external calls — same input, same result, every run")]
    out += star("model", d.get("model"))
    out += star("condition", d.get("condition"))
    out += star("status", d.get("status"), _status_color(d.get("status", "")))
    out += star("simulated_latency_ms", d.get("simulated_latency_ms"))
    out += star("external_api_calls", d.get("external_api_calls"),
                LIME if d.get("external_api_calls") == 0 else PINK)
    out += star("deterministic", d.get("deterministic"),
                LIME if d.get("deterministic") else PINK)
    return "\n".join(out)


def fmt_conditions(d: dict) -> str:
    out = [header(
        "Show the repeatable provider condition matrix (LO EO1a)",
        "Six named conditions make every scenario repeatable")]
    # One blank line between rows so each is independently highlightable, while
    # still fitting on one screen (two short sections).
    out.append(f"  {WHITE}active condition (per model){RESET}")
    out.append("")
    for model, cond in d.get("active", {}).items():
        color = LIME if cond == "healthy" else PINK
        out.append(f"  {PINK}★{RESET} {LGRN}{str(model):<14}{RESET}{color}{cond}{RESET}")
        out.append("")
    out.append(f"  {WHITE}supported conditions{RESET}")
    out.append("")
    for name, note in d.get("supported", {}).items():
        color = LIME if name == "healthy" else GRAY
        out.append(f"  {PINK}★{RESET} {color}{str(name):<13}{RESET}{GRAY}{note}{RESET}")
        out.append("")
    return "\n".join(out)


def fmt_route(d: dict) -> str:
    out = [header(
        "Send a baseline request through the boundary (LO TO1)",
        "One normalized decision the caller can trust")]
    out += star("selected_model", d.get("selected_model"))
    out += star("provider_tier", d.get("provider_tier"))
    out += star("provider_status", d.get("provider_status"),
                _status_color(d.get("provider_status", "")))
    est = d.get("token_estimate", {})
    out.append(tokens_line(est))
    out.append("")
    out += star("cost_estimate_usd", f"${d.get('cost_estimate_usd'):.6f}")
    out += star("latency_target_ms", d.get("latency_target_ms"))
    out += star("route_reason", d.get("route_reason"))
    out += ctx("request_id", d.get("request_id"))
    return "\n".join(out)


def fmt_receipt(d: Any) -> str:
    # Accept either a single row (row_to_json) or the /receipts wrapper.
    if isinstance(d, dict) and "receipts" in d:
        row = d["receipts"][0] if d["receipts"] else {}
    elif isinstance(d, list):
        row = d[0] if d else {}
    else:
        row = d
    out = [header(
        "Read the normalized receipt in PostgreSQL (LO TO1, EO1a)",
        "The decision persists in one shape regardless of provider")]
    if not row:
        out.append(f"  {GRAY}(no receipt row returned — check the psql connection "
                   f"line above, and that a request was routed first){RESET}")
        return "\n".join(out)
    out += star("selected_model", row.get("selected_model"))
    out += star("provider_tier", row.get("provider_tier"))
    out += star("provider_status", row.get("provider_status"),
                _status_color(row.get("provider_status", "")))
    tokline = {
        "prompt": row.get("prompt_tokens", 0),
        "completion": row.get("completion_tokens", 0),
        "total": row.get("total_tokens", 0),
    }
    out.append(tokens_line(tokline))
    out.append("")
    cost = row.get("cost_estimate_usd")
    out += star("cost_estimate_usd", f"${float(cost):.6f}" if cost is not None else "n/a")
    qual = row.get("quality_score")
    if qual is not None:
        out += star("quality_score", float(qual))
    out += star("policy_name", row.get("policy_name"))
    out += ctx("request_id", row.get("request_id"))
    return "\n".join(out)


VIEWS = {
    "health": fmt_health,
    "providers": fmt_providers,
    "probe": fmt_probe,
    "conditions": fmt_conditions,
    "route": fmt_route,
    "receipt": fmt_receipt,
}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--type", required=True, choices=sorted(VIEWS))
    ap.add_argument("--title", default=None, help="override the header title")
    ap.add_argument("--why", default=None, help="override the header 'why' line")
    args = ap.parse_args()
    global TITLE, WHY
    TITLE, WHY = args.title, args.why
    raw = sys.stdin.read().strip()
    try:
        data = json.loads(raw) if raw else {}
    except json.JSONDecodeError:
        print(f"{PINK}fmt.py: input was not valid JSON:{RESET}\n{raw}")
        sys.exit(1)
    # Normalize trailing whitespace, then add breathing room before the shell
    # prompt so no view ends flush against it.
    body = VIEWS[args.type](data).rstrip("\n")
    print(body)
    print()
    print()


if __name__ == "__main__":
    main()
