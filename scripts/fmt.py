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


def header(default_title: str, default_why: str, width: int = 74) -> str:
    """View header, overridable per step with --title / --why."""
    return panel(TITLE or default_title, WHY or default_why, width)


def panel(title: str, why: str, width: int = 74) -> str:
    """Boxed header: WHAT we show (white) + WHY we show it (blue). No truncation."""
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


# --- Clip 3 views (weighted routing) --------------------------------------

def fmt_policy(d: dict) -> str:
    out = [header(
        "Load the weighted routing policy",
        "Weights are set by cost and latency target — most traffic to the "
        "cheapest, fastest tier; least to the most expensive one")]
    out += star("policy_name", d.get("policy_name"))
    out.append(f"    {BLUE}{'tier':<14}{'weight':<9}{'latency target':<16}"
               f"{'cost estimate'}{RESET}")
    out.append("")
    for t in d.get("tiers", []):
        wt = f"{t.get('weight_pct')}%"
        lat = f"{t.get('latency_target_ms')}ms"
        cost = f"${float(t.get('cost_estimate_usd', 0)):.6f}"
        out.append(
            f"  {PINK}★{RESET} {LGRN}{str(t.get('model')):<14}{wt:<9}{lat:<16}"
            f"{cost}{RESET}")
        out.append("")
    ref_n = d.get("reference_total_tokens")
    if ref_n is not None:
        out += ctx("cost basis",
                   f"a fixed {ref_n}-token reference prompt for like-for-like comparison")
    return "\n".join(out)


def fmt_batch(d: dict) -> str:
    out = [header(
        "Run a controlled traffic batch",
        "One endpoint, many requests — the weighted policy decides each")]
    out += star("policy_name", d.get("policy_name"))
    out += star("route_reason", d.get("route_reason"))
    out += star("requests routed", d.get("count"))
    return "\n".join(out)


def fmt_samples(d: dict) -> str:
    out = [header(
        "Inspect the individual routed decisions",
        "Requests entering the same endpoint are distributed across different "
        "model tiers")]
    rows = d.get("samples", []) or []
    out.append(f"    {BLUE}{'request':<16}{'model':<14}{'tier':<10}"
               f"{'latency target':<16}{'cost'}{RESET}")
    out.append("")
    for r in rows:
        rid = str(r.get("request_id", ""))[:14]
        lat = f"{r.get('latency_target_ms')}ms"
        cost = f"${float(r.get('cost_estimate_usd', 0)):.6f}"
        out.append(
            f"  {PINK}★{RESET} {LGRN}{rid:<16}{str(r.get('selected_model')):<14}"
            f"{str(r.get('provider_tier')):<10}{lat:<16}{cost}{RESET}")
        out.append("")
    return "\n".join(out)


# Canonical tier order for datastore views that return an unordered map.
_TIER_ORDER = ["econo-mini", "balanced-std", "premium-max"]


def fmt_redis_counters(d: dict) -> str:
    # Input is `redis-cli --json HGETALL routing:counters` -> {model: "count"}.
    out = [header(
        "Read the routing counters straight from Redis",
        "The tally lives in the Redis datastore itself — read it directly, not "
        "through the application")]
    counts = {k: int(v) for k, v in d.items()} if isinstance(d, dict) else {}
    total = sum(counts.values())
    out += star("total requests", total)
    out += sect("distribution across tiers (HGETALL routing:counters)")
    ordered = [m for m in _TIER_ORDER if m in counts] + \
              [m for m in counts if m not in _TIER_ORDER]
    for model in ordered:
        out += star(model, counts[model])
    return "\n".join(out)


def fmt_counters(d: dict) -> str:
    out = [header(
        "Prove distribution across tiers with Redis counters",
        "Redis tallies every pick — the spread is measured, not assumed")]
    out += star("total requests", d.get("total"))
    out += sect("distribution across tiers")
    for model, n in d.get("counters", {}).items():
        out += star(model, n)
    return "\n".join(out)


def fmt_receipts(d: Any) -> str:
    # Accept a JSON array, the /receipts wrapper, or newline-separated objects
    # (psql -tA multi-row output is normalized to a list before we get here).
    if isinstance(d, dict) and "receipts" in d:
        rows = d["receipts"]
    elif isinstance(d, list):
        rows = d
    else:
        rows = [d]
    out = [header(
        "Connect each model choice to cost and policy",
        "Every tier lands in the same receipt columns — cost differs, the "
        "policy is identical")]
    out.append(f"    {BLUE}{'model':<14}{'tier':<10}{'cost':<12}{'policy'}{RESET}")
    out.append("")
    for r in rows:
        if not r:
            continue
        cost = f"${float(r.get('cost_estimate_usd', 0)):.6f}"
        out.append(
            f"  {PINK}★{RESET} {LGRN}{str(r.get('selected_model')):<14}"
            f"{str(r.get('provider_tier')):<10}{cost:<12}{RESET}"
            f"{LIME}{r.get('policy_name')}{RESET}")
        out.append("")
    return "\n".join(out)


def fmt_validate(d: dict) -> str:
    out = [header(
        "Confirm the distribution matches the configured weights",
        "Observed picks equal the configured weights — the balancing is "
        "intentional and repeatable")]
    out += star("total requests", d.get("total"))
    allm = d.get("all_match")
    out += star("all_match", allm, LIME if allm else PINK)
    out.append(f"    {BLUE}{'tier':<14}{'weight':<8}{'expected':<10}"
               f"{'observed':<10}{'match'}{RESET}")
    out.append("")
    for model, t in d.get("tiers", {}).items():
        mark = f"{LIME}✓{RESET}" if t.get("match") else f"{PINK}✗{RESET}"
        out.append(
            f"  {PINK}★{RESET} {LGRN}{model:<14}{str(t.get('weight_pct'))+'%':<8}"
            f"{str(t.get('expected')):<10}{str(t.get('observed')):<10}{RESET}{mark}")
        out.append("")
    return "\n".join(out)


# --- Clip 5 views (payload-based smart routing + overrides) ---------------

def fmt_rules(d: dict) -> str:
    out = [header(
        "Load the payload-based routing rules",
        "Three separate signals — size is evidence, declared complexity picks "
        "the tier, overrides pin it")]
    out += star("policy_name", d.get("policy_name"))
    thr = d.get("size_threshold_tokens")
    out += ctx("size (evidence only)",
               f"≤ {thr} tokens = short, > {thr} = long — shown for cost, never selects the tier")
    tiers = d.get("complexity_tiers", {})
    out += sect("complexity selects the tier (mapped from the declared task class)")
    out.append(f"    {BLUE}{'task class':<20}{'complexity':<12}{'tier'}{RESET}")
    for task, cx in d.get("task_complexity", {}).items():
        out.append(f"    {LGRN}{task:<20}{cx:<12}{tiers.get(cx, '')}{RESET}")
    out.append("")
    out += sect("deterministic overrides (bypass the decision)")
    out.append(f"    {BLUE}{'override class':<16}{'tier':<13}{'direction':<11}{'risk'}{RESET}")
    for cls, rule in d.get("overrides", {}).items():
        out.append(f"    {LGRN}{cls:<16}{str(rule.get('model')):<13}"
                   f"{str(rule.get('direction')):<11}{rule.get('risk')}{RESET}")
    out.append("")
    return "\n".join(out)


def fmt_smart(d: dict) -> str:
    out = [header(
        "Route a request by declared complexity",
        "Size, complexity, and risk are separate — complexity selects the tier")]
    out += star("selected_model", d.get("selected_model"))
    out += star("provider_tier", d.get("provider_tier"))
    out += star("size", d.get("size"))
    out += star("complexity", d.get("complexity"))
    out += star("risk", d.get("risk"), PINK if d.get("risk") == "high" else LGRN)
    est = d.get("token_estimate", {})
    out.append(tokens_line(est))
    out.append("")
    out += star("cost_estimate_usd", f"${d.get('cost_estimate_usd'):.6f}")
    out += star("route_reason", d.get("route_reason"))
    # Present only when a deterministic override fired (EO1d): the tier
    # complexity routing would have chosen, plus the override direction.
    if d.get("override_class"):
        out += star("would_have_selected", d.get("would_have_selected"), PINK)
        out += star("override_class", d.get("override_class"), PINK)
        # economy = saving money (green) · risk = protecting quality (pink)
        dirn = d.get("override_direction")
        out += star("override_direction", dirn, PINK if dirn == "risk" else LIME)
    out += ctx("cost basis", "synthetic local estimate for comparing routes, not a provider invoice")
    out += ctx("request_id", d.get("request_id"))
    return "\n".join(out)


def fmt_smart_pair(d: Any) -> str:
    # Two smart responses compared on one screen (Steps 2-4 route two requests
    # each). Payload rows show cost; override rows show would_have_selected.
    rows = [r for r in (d if isinstance(d, list) else [d]) if r]
    is_override = any(r.get("override_class") for r in rows)
    out = [header(
        "Route two requests and compare",
        "Same endpoint, two payloads side by side")]
    if is_override:
        out.append(f"    {BLUE}{'size':<6}{'tokens':<7}{'complexity':<11}"
                   f"{'selected':<14}{'would→':<13}{'route_reason'}{RESET}")
    else:
        out.append(f"    {BLUE}{'size':<6}{'tokens':<7}{'complexity':<11}"
                   f"{'selected':<14}{'cost':<11}{'route_reason'}{RESET}")
    out.append("")
    for r in rows:
        tok = str(r.get("token_estimate", {}).get("total", ""))
        size = str(r.get("size"))
        cx = str(r.get("complexity"))
        model = str(r.get("selected_model"))
        reason = str(r.get("route_reason"))
        if is_override:
            would = str(r.get("would_have_selected") or "-")
            out.append(
                f"  {PINK}★{RESET} {LGRN}{size:<6}{tok:<7}{cx:<11}{model:<14}"
                f"{would:<13}{reason}{RESET}")
        else:
            cost = f"${float(r.get('cost_estimate_usd', 0)):.6f}"
            out.append(
                f"  {PINK}★{RESET} {LGRN}{size:<6}{tok:<7}{cx:<11}{model:<14}"
                f"{cost:<11}{reason}{RESET}")
        out.append("")
    return "\n".join(out)


def fmt_smart_receipts(d: Any) -> str:
    # Accept a JSON array, the /receipts wrapper, or psql -tA multi-row output
    # normalized to a list before we get here.
    if isinstance(d, dict) and "receipts" in d:
        rows = d["receipts"]
    elif isinstance(d, list):
        rows = d
    else:
        rows = [d]
    out = [header(
        "Per-request audit receipts in PostgreSQL",
        "Durable per request: id, tokens, complexity, tier, reason, cost")]
    out.append(f"    {BLUE}{'request':<14}{'tokens':<7}{'complexity':<11}"
               f"{'model':<13}{'route_reason':<22}{'cost'}{RESET}")
    for r in rows:
        if not r:
            continue
        rid = str(r.get("request_id", ""))[:12]
        tok = str(r.get("total_tokens", ""))
        cx = str(r.get("complexity") or "-")
        model = str(r.get("selected_model"))
        reason = str(r.get("route_reason"))
        cost = f"${float(r.get('cost_estimate_usd', 0)):.6f}"
        out.append(
            f"  {PINK}★{RESET} {LGRN}{rid:<14}{tok:<7}{cx:<11}{model:<13}"
            f"{reason:<22}{cost}{RESET}")
    return "\n".join(out)


def fmt_smart_counters(d: dict) -> str:
    # Compact (single-spaced): Step 5 shows this alongside the receipts table, so
    # both must fit one screen.
    counts = {k: int(v) for k, v in d.items()} if isinstance(d, dict) else {}
    out = [header(
        "Smart-routing counters in Redis",
        "How each decision was made — complexity vs override — and proof the "
        "weighted path was bypassed")]
    weighted = counts.get("weighted", 0)
    payload = {k: v for k, v in counts.items() if k.startswith("payload:")}
    override = {k: v for k, v in counts.items() if k.startswith("override:")}
    out.append(star("total routed", sum(payload.values()) + sum(override.values()))[0])
    out.append(sect("routed by complexity")[0])
    for k in sorted(payload):
        out.append(star(k, payload[k])[0])
    out.append(sect("pinned by override")[0])
    out.append(star("override total", sum(override.values()))[0])
    for k in sorted(override):
        out.append(star(k, override[k])[0])
    out.append(star("weighted path (bypassed)", weighted,
                    LIME if weighted == 0 else PINK)[0])
    return "\n".join(out)


def fmt_smart_validate(d: dict) -> str:
    out = [header(
        "Confirm every payload lands on the tier its rules dictate",
        "Size, complexity, and overrides are deterministic and testable — same "
        "input, same tier, every run")]
    out.append(star("cases", d.get("total"))[0])
    allm = d.get("all_match")
    out.append(star("all_match", allm, LIME if allm else PINK)[0])
    out.append(star("policy_name", d.get("policy_name"))[0])
    out.append(f"    {BLUE}{'case':<20}{'size':<7}{'complexity':<11}"
               f"{'selected':<18}{'match'}{RESET}")
    for c in d.get("cases", []):
        mark = f"{LIME}✓{RESET}" if c.get("match") else f"{PINK}✗{RESET}"
        sel = str(c.get("selected_model"))
        exp = str(c.get("expected_model"))
        pair = sel if sel == exp else f"{sel} (want {exp})"
        out.append(
            f"  {PINK}★{RESET} {LGRN}{str(c.get('name')):<20}"
            f"{str(c.get('size')):<7}{str(c.get('complexity')):<11}"
            f"{pair:<18}{RESET}{mark}")
    return "\n".join(out)


# --- Clip 6 views (mixed batch + final disposition) -----------------------

def fmt_mixed(d: dict) -> str:
    out = [header(
        "Run a mixed routing batch",
        "Weighted, payload, and override requests through one service")]
    out += star("total requests", d.get("total"))
    out += sect("by routing kind")
    bk = d.get("by_kind", {})
    for k in ("weighted", "payload", "override"):
        out += star(k, bk.get(k))
    out += star("policies", ", ".join(d.get("policies", [])))
    return "\n".join(out)


def fmt_mixed_samples(d: dict) -> str:
    out = [header(
        "Inspect representative routing decisions",
        "Each request tagged with its kind, policy, model, and route reason")]
    out.append(f"    {BLUE}{'kind':<10}{'policy':<15}{'model':<13}"
               f"{'tier':<10}{'route_reason'}{RESET}")
    out.append("")
    for r in d.get("samples", []) or []:
        out.append(
            f"  {PINK}★{RESET} {LGRN}{str(r.get('kind')):<10}"
            f"{str(r.get('policy_name')):<15}{str(r.get('selected_model')):<13}"
            f"{str(r.get('provider_tier')):<10}{r.get('route_reason')}{RESET}")
        out.append("")
    return "\n".join(out)


def fmt_mixed_counters(d: dict) -> str:
    counts = {k: int(v) for k, v in d.items()} if isinstance(d, dict) else {}
    out = [header(
        "Aggregate routing kinds in Redis",
        "The datastore's per-kind tally — reconciles against the batch summary")]
    out += star("total", sum(counts.values()))
    out += sect("by routing kind")
    for k in ("weighted", "payload", "override"):
        if k in counts:
            out += star(k, counts[k])
    return "\n".join(out)


def fmt_mixed_receipts(d: Any) -> str:
    if isinstance(d, dict) and "receipts" in d:
        rows = d["receipts"]
    elif isinstance(d, list):
        rows = d
    else:
        rows = [d]
    out = [header(
        "Durable routing receipts in PostgreSQL",
        "Every routing kind: request ID, policy, provider, latency target, "
        "tokens, cost, quality", width=88)]
    out.append(f"    {BLUE}{'request':<18}{'policy':<16}{'tier':<14}"
               f"{'latency':<9}{'tokens':<8}{'cost':<11}{'quality'}{RESET}")
    out.append("")
    for r in rows:
        if not r:
            continue
        lat = f"{r.get('latency_target_ms')}ms"
        cost = f"${float(r.get('cost_estimate_usd', 0)):.6f}"
        qual = f"{float(r.get('quality_score', 0)):.2f}"
        out.append(
            f"  {PINK}★{RESET} {LGRN}{str(r.get('request_id')):<18}{str(r.get('policy_name')):<16}"
            f"{str(r.get('provider_tier')):<14}{lat:<9}{str(r.get('total_tokens')):<8}"
            f"{cost:<11}{qual}{RESET}")
        out.append("")
    return "\n".join(out)


def fmt_disposition(d: dict) -> str:
    out = [header(
        "Reconcile the evidence and confirm the disposition",
        "CONFIRMED only when the API, Redis, and receipt views agree, every "
        "request has a durable receipt, and every policy fits its route reason")]
    disp = d.get("disposition")
    out += star("disposition", disp, LIME if disp == "CONFIRMED" else PINK)
    out += star("counts_agree", d.get("counts_agree"),
                LIME if d.get("counts_agree") else PINK)
    out += star("receipts_complete", d.get("receipts_complete"),
                LIME if d.get("receipts_complete") else PINK)
    out += star("policies_consistent", d.get("policies_consistent"),
                LIME if d.get("policies_consistent") else PINK)
    out.append(f"    {BLUE}{'kind':<12}{'api':<7}{'redis':<8}{'receipts':<10}"
               f"{'agree'}{RESET}")
    out.append("")
    for k in ("weighted", "payload", "override"):
        t = d.get("kinds", {}).get(k, {})
        mark = f"{LIME}✓{RESET}" if t.get("agree") else f"{PINK}✗{RESET}"
        out.append(
            f"  {PINK}★{RESET} {LGRN}{k:<12}{str(t.get('api')):<7}"
            f"{str(t.get('redis')):<8}{str(t.get('receipts')):<10}{RESET}{mark}")
        out.append("")
    return "\n".join(out)


def _noted(label: str, value: Any, note: str, color: str = LGRN) -> list[str]:
    """A ★ line with a trailing dim note — e.g. accepted: 6  (served now)."""
    if isinstance(value, bool):
        value = str(value).lower()
    return [f"  {PINK}★{RESET} {BLUE}{label}:{RESET} {color}{value}{RESET}"
            f"   {GRAY}{note}{RESET}", ""]


# --- Admission control views (Module 2, Clip 2) ---------------------------

def fmt_k6_summary(d: dict) -> str:
    out = [header(
        "Run the k6 spike and read the HTTP outcomes",
        "Real concurrent k6 traffic against the service — the HTTP status "
        "distribution proves mixed outcomes with no failures", width=80)]
    out += star("requests submitted", d.get("submitted"))
    out += sect("HTTP outcomes")
    out += _noted("HTTP 200", d.get("http_200"), "admitted or queued", LIME)
    out += _noted("HTTP 429", d.get("http_429"), "rejected at capacity", PINK)
    out += _noted("HTTP 500", d.get("http_500"),
                  "server errors", LIME if not d.get("http_500") else PINK)
    out += _noted("connection failures", d.get("failed"),
                  "transport errors", LIME if not d.get("failed") else PINK)
    out += sect("admission split")
    out += _noted("accepted", d.get("accepted"), "served now", LIME)
    out += _noted("delayed", d.get("delayed"), "queued", BLUE)
    out += _noted("rejected", d.get("rejected"), "shed (fail fast)", PINK)
    return "\n".join(out)


def fmt_spike(d: dict) -> str:
    out = [header(
        "Run a controlled traffic spike",
        "A burst hits one tier: absorb what fits the rate limit, queue what "
        "fits the backlog, shed the rest")]
    out += star("submitted requests", d.get("submitted"))
    out += _noted("target", f"{d.get('provider')} / {d.get('model')}",
                  f"tier {d.get('tier')}, class {d.get('request_class')}")
    out += sect("outcomes")
    out += _noted("accepted", d.get("accepted"),
                  "within the rate limit — served now", LIME)
    out += _noted("delayed", d.get("delayed"),
                  "over the rate limit — waiting in the queue", BLUE)
    out += _noted("rejected", d.get("rejected"),
                  "over queue capacity — shed (fail fast)", PINK)
    out += sect("live state")
    full = "FULL" if d.get("queue_full") else "has room"
    out += _noted("queue depth", f"{d.get('queue_depth')} / {d.get('queue_capacity')}",
                  full, PINK if d.get("queue_full") else LGRN)
    out += _noted("rate limit", f"{d.get('rate_limit')} per {d.get('window_seconds')}s",
                  "immediate admits per window")
    return "\n".join(out)


def _by_model(hash_map: dict, suffix: str) -> dict:
    """Regroup a flat `<model>:field` Redis hash into {model: {field: value}}."""
    grouped: dict[str, dict] = {}
    for k, v in (hash_map or {}).items():
        if ":" not in k:
            continue
        model, field = k.rsplit(":", 1)
        grouped.setdefault(model, {})[field] = v
    return grouped


def fmt_queue(d: dict) -> str:
    depth = int(d.get("depth", 0)); cap = int(d.get("capacity", 0))
    full = depth >= cap > 0
    out = [header(
        "Inspect the real queue in Redis",
        "The actual list of queued request IDs — real parked work, not just a "
        "depth counter", width=80)]
    out += _noted("queue key", d.get("queue_key"), "a Redis LIST of request IDs")
    out += _noted("depth", f"{depth} / {cap}", "FULL" if full else "has room",
                  PINK if full else LGRN)
    out += sect("queued request IDs (actual work parked in the list)")
    for rid in d.get("queued_request_ids", []):
        out.append(f"  {PINK}★{RESET} {LGRN}{rid}{RESET}")
        out.append("")
    return "\n".join(out)


def fmt_queue_list(d: Any) -> str:
    """Render the raw queued request IDs — a Redis LIST read with LRANGE (a JSON
    array), or the /resilience/queue object."""
    if isinstance(d, list):
        ids, cap = d, None
    elif isinstance(d, dict):
        ids, cap = d.get("queued_request_ids", []), d.get("capacity")
    else:
        ids, cap = [], None
    out = [header(
        "Inspect the real queue in Redis",
        "The actual list of queued request IDs — real parked work, not just a "
        "depth counter", width=80)]
    note = "a real Redis LIST — actual parked work"
    depth_val = f"{len(ids)}" if cap is None else f"{len(ids)} / {cap}"
    out += _noted("queued", depth_val, note, PINK if ids else LGRN)
    out += sect("queued request IDs (actual work parked in the list)")
    for rid in ids:
        out.append(f"  {PINK}★{RESET} {LGRN}{rid}{RESET}")
        out.append("")
    return "\n".join(out)


def fmt_ratelimit(d: dict) -> str:
    adm = int(d.get("admitted", 0)); lim = int(d.get("limit", 0))
    at = adm >= lim > 0
    out = [header(
        "Compare the rate-limit count against its threshold",
        "The admitted count vs the configured limit and window — the gate that "
        "decides accept-now or queue", width=80)]
    out += _noted("limiter key", d.get("limiter_key"), "provider : tier : class")
    out += _noted("admitted", f"{adm} / {lim}", "AT LIMIT" if at else "under limit",
                  PINK if at else LGRN)
    out += _noted("window", f"{lim} requests per {d.get('window_seconds')}s",
                  "the immediate-admit budget and how long it lasts")
    return "\n".join(out)


def fmt_matrix(d: dict) -> str:
    out = [header(
        "Compare policies by provider, tier, and request class",
        "The same burst against every provider key — each has its own limit, so "
        "each sheds at a different point", width=92)]
    out += star("burst size", d.get("burst_size"))
    out.append(f"    {BLUE}{'provider':<13}{'tier':<10}{'class':<13}{'rate':<6}"
               f"{'queue':<7}{'accepted':<10}{'delayed':<9}{'rejected'}{RESET}")
    out.append("")
    for r in d.get("tiers", []):
        rej = r.get("rejected", 0)
        rej_c = PINK if rej else LGRN
        out.append(
            f"  {PINK}★{RESET} {LGRN}{str(r.get('provider')):<13}"
            f"{str(r.get('tier')):<10}{str(r.get('request_class')):<13}"
            f"{str(r.get('rate_limit')):<6}{str(r.get('queue_capacity')):<7}"
            f"{LIME}{str(r.get('accepted')):<10}{BLUE}{str(r.get('delayed')):<9}"
            f"{rej_c}{rej}{RESET}")
        out.append("")
    return "\n".join(out)


def fmt_failfast(d: Any) -> str:
    # curl appends a second JSON line ({"http_status": N}); fmt reads both.
    detail, http = {}, None
    rows = d if isinstance(d, list) else [d]
    for r in rows:
        if not isinstance(r, dict):
            continue
        if "http_status" in r:
            http = r["http_status"]
        elif "detail" in r and isinstance(r["detail"], dict):
            detail = r["detail"]
        elif "disposition" in r:
            detail = r
    out = [header(
        "Exceed the queue and prove the fail-fast 429",
        "With the queue full, one more request is rejected fast — a clean HTTP "
        "429 to the caller and a durable rejected receipt")]
    if http is not None:
        note = "Too Many Requests" if int(http) == 429 else ""
        out += _noted("http status", http, note,
                      PINK if int(http) == 429 else LGRN)
    out += _noted("admitted", detail.get("admitted"), "the request was shed", PINK)
    out += _noted("disposition", detail.get("disposition"), "fail fast, not served", PINK)
    out += star("reason", detail.get("reason"), PINK)
    out += _noted("queue", f"{detail.get('queue_depth')} / {detail.get('queue_capacity')}",
                  "backlog is full", PINK)
    if detail.get("retry_after_seconds") is not None:
        out += _noted("retry_after", f"{detail.get('retry_after_seconds')}s",
                      "the caller is told when to retry", LIME)
    out += star("request_id", detail.get("request_id"))
    out += _noted("receipt_persisted", detail.get("receipt_persisted"),
                  "the shed is auditable in PostgreSQL", LIME)
    return "\n".join(out)


def fmt_dispositions(d: dict) -> str:
    out = [header(
        "Distinguish every request's fate in the receipts",
        "Straight from PostgreSQL: accepted, delayed, and rejected — each a "
        "durable, distinguishable record", width=80)]
    out += star("total requests", d.get("total"))
    disp = d.get("dispositions", {})
    out += sect("by disposition")
    out += _noted("accepted", disp.get("accepted"), "served now", LIME)
    out += _noted("delayed", disp.get("delayed"), "queued", BLUE)
    out += _noted("rejected", disp.get("rejected"), "shed — never ran, zero cost", PINK)
    out += sect("sample receipts  (cost is an estimate; actual is zero until execution)")
    out.append(f"    {BLUE}{'disposition':<13}{'request':<18}{'model':<14}"
               f"{'est tokens':<12}{'est cost':<12}{'status'}{RESET}")
    out.append("")
    for r in d.get("samples", []):
        disp_v = str(r.get("disposition"))
        dc = {"accepted": LIME, "delayed": BLUE, "rejected": PINK}.get(disp_v, LGRN)
        cost = f"${float(r.get('cost_estimate_usd', 0)):.6f}"
        out.append(
            f"  {PINK}★{RESET} {dc}{disp_v:<13}{RESET}{LGRN}{str(r.get('request_id')):<18}"
            f"{str(r.get('selected_model')):<14}{str(r.get('total_tokens')):<12}"
            f"{cost:<12}{str(r.get('provider_status'))}{RESET}")
        out.append("")
    return "\n".join(out)


def fmt_admission_logs(d: dict) -> str:
    out = [header(
        "Correlate one request across logs and receipts",
        "Structured admission logs distinguish every disposition, and one "
        "request ID ties the caller, the log, and the receipt together", width=92)]
    out += sect("one structured log per disposition")
    out.append(f"    {BLUE}{'disposition':<13}{'request':<18}{'queue':<7}"
               f"{'rate':<6}{'http':<6}{'reason'}{RESET}")
    out.append("")
    for e in d.get("samples", []):
        disp_v = str(e.get("disposition"))
        dc = {"accepted": LIME, "delayed": BLUE, "rejected": PINK}.get(disp_v, LGRN)
        out.append(
            f"  {PINK}★{RESET} {dc}{disp_v:<13}{RESET}{LGRN}{str(e.get('request_id')):<18}"
            f"{str(e.get('queue_depth')):<7}{str(e.get('rate_limit_count')):<6}"
            f"{str(e.get('http_status')):<6}{str(e.get('reason'))}{RESET}")
        out.append("")
    c = d.get("correlate", {})
    out += sect("correlation — one rejected request ID, three places")
    out += star("request_id", c.get("request_id"))
    out += _noted("in structured log", c.get("in_log"), "the operator log stream",
                  LIME if c.get("in_log") else PINK)
    out += _noted("in PostgreSQL receipt", c.get("in_receipt"), "the durable ledger",
                  LIME if c.get("in_receipt") else PINK)
    out += _noted("dispositions match", c.get("match"),
                  "log and receipt agree on the outcome",
                  LIME if c.get("match") else PINK)
    return "\n".join(out)


# --- Circuit breaker views (Module 2, Clip 3) -----------------------------

_STATE_COLOR = {"closed": LIME, "open": PINK, "half_open": BLUE}


def fmt_circuit_config(d: dict) -> str:
    out = [header(
        "Load the circuit-breaker configuration",
        "The thresholds that trip and recover the circuit, the fallback routes, "
        "and the retry backoff schedule", width=80)]
    out += _noted("failure modes", ", ".join(d.get("failure_modes", [])),
                  "deterministic provider stubs — no real outage")
    out += sect("thresholds")
    out += _noted("failure_threshold", d.get("failure_threshold"),
                  "consecutive failures that trip the circuit open", PINK)
    out += _noted("cooldown_probes", d.get("cooldown_probes"),
                  "requests shed before a half-open probe")
    out += _noted("success_threshold", d.get("success_threshold"),
                  "successful probes that close the circuit", LIME)
    out += _noted("max_attempts", d.get("max_attempts"),
                  "retry cap, then fail over")
    out += sect("fallback routes")
    for primary, fb in (d.get("fallback_routes", {}) or {}).items():
        out.append(f"  {PINK}★{RESET} {LGRN}{primary}{RESET} {GRAY}→{RESET} {LIME}{fb}{RESET}")
        out.append("")
    out += sect("retry backoff schedule")
    out.append(f"    {BLUE}{'attempt':<10}{'base delay':<13}{'jitter':<10}{'wait'}{RESET}")
    out.append("")
    for s in d.get("backoff_schedule", []):
        out.append(
            f"  {PINK}★{RESET} {LGRN}{str(s.get('attempt')):<10}"
            f"{str(s.get('base_delay_ms'))+'ms':<13}{str(s.get('jitter_ms'))+'ms':<10}"
            f"{str(s.get('wait_ms'))}ms{RESET}")
        out.append("")
    return "\n".join(out)


def fmt_circuit(d: dict) -> str:
    out = [header(
        "Walk the circuit through its states",
        "One drill drives the primary from healthy to open to half-open to "
        "recovered — every transition visible", width=92)]
    out += star("primary", d.get("primary"))
    out += star("fallback", d.get("fallback"))
    out += _noted("tripped", d.get("tripped"), "the circuit opened under failures",
                  PINK if d.get("tripped") else LGRN)
    out += _noted("recovered", d.get("recovered"), "a half-open probe closed it again",
                  LIME if d.get("recovered") else PINK)
    out += sect("per-request state journey")
    out.append(f"    {BLUE}{'seq':<5}{'primary cond':<14}{'circuit':<12}"
               f"{'transition':<15}{'served by':<15}{'attempts'}{RESET}")
    out.append("")
    for r in d.get("timeline", []):
        cs = _STATE_COLOR.get(str(r.get("circuit")), LGRN)
        cond_c = PINK if r.get("primary_condition") != "healthy" else LIME
        out.append(
            f"  {PINK}★{RESET} {LGRN}{str(r.get('seq')):<5}{cond_c}"
            f"{str(r.get('primary_condition')):<14}{cs}{str(r.get('circuit')):<12}"
            f"{LGRN}{str(r.get('transition')):<15}{str(r.get('served_by')):<15}"
            f"{str(r.get('primary_attempts'))}{RESET}")
        out.append("")
    return "\n".join(out)


def fmt_fallback(d: dict) -> str:
    out = [header(
        "Prove fallback routing keeps the caller whole",
        "While the primary is unsafe, a healthy alternative serves — so primary "
        "failures never reach the caller", width=80)]
    out += _noted("primary (failed)", d.get("primary"),
                  "the tier whose provider was unsafe", PINK)
    out += _noted("fallback (healthy)", d.get("fallback"),
                  "the alternative that absorbed the traffic", LIME)
    out += sect("outcome for the caller")
    out += _noted("requests answered",
                  f"{d.get('requests_answered')} / {d.get('total')}",
                  "every caller got a response", LIME)
    out += _noted("caller errors", d.get("caller_errors"),
                  "primary failures that reached the caller", LIME)
    out += sect("routing split")
    out += _noted("served by primary", d.get("primary_served"),
                  "handled by the healthy primary")
    out += _noted("served by fallback", d.get("fallback_served"),
                  "rerouted while the primary was unsafe", BLUE)
    return "\n".join(out)


def fmt_retry_log(d: dict) -> str:
    out = [header(
        "Inspect retry backoff and prove no storm",
        "Retries are capped and spaced by exponential backoff; once the circuit "
        "opens, the primary is not retried at all", width=82)]
    out += _noted("retry cap", f"{d.get('max_attempts')} attempts",
                  "then fail over to the fallback")
    out += sect("exponential backoff schedule")
    out.append(f"    {BLUE}{'attempt':<10}{'base delay':<13}{'jitter':<10}{'wait'}{RESET}")
    out.append("")
    for s in d.get("backoff_schedule", []):
        out.append(
            f"  {PINK}★{RESET} {LGRN}{str(s.get('attempt')):<10}"
            f"{str(s.get('base_delay_ms'))+'ms':<13}{str(s.get('jitter_ms'))+'ms':<10}"
            f"{str(s.get('wait_ms'))}ms{RESET}")
        out.append("")
    out += sect("storm prevention")
    with_b = d.get("total_primary_attempts")
    without_b = d.get("attempts_without_breaker")
    avoided = (without_b - with_b) if (isinstance(with_b, int) and isinstance(without_b, int)) else "?"
    out += _noted("primary attempts WITH breaker", with_b, "capped and short-circuited", LIME)
    out += _noted("primary attempts WITHOUT breaker", without_b,
                  "every failure retried to the cap", PINK)
    out += _noted("retries avoided by opening", avoided,
                  "open state makes zero primary attempts", LIME)
    return "\n".join(out)


def fmt_failover_reconcile(d: dict) -> str:
    out = [header(
        "Reconcile caller response, receipt, and retry log",
        "CONFIRMED only when the caller response, the PostgreSQL fallback "
        "receipt, and the retry log agree and the circuit recovered", width=80)]
    disp = d.get("disposition")
    out += star("disposition", disp, LIME if disp == "CONFIRMED" else PINK)
    out += star("counts_agree", d.get("counts_agree"),
                LIME if d.get("counts_agree") else PINK)
    out += star("recovered", d.get("recovered"),
                LIME if d.get("recovered") else PINK)
    out += star("receipts_complete", d.get("receipts_complete"),
                LIME if d.get("receipts_complete") else PINK)
    out.append(f"    {BLUE}{'role':<12}{'caller':<9}{'receipt':<10}{'retry log':<11}"
               f"{'agree'}{RESET}")
    out.append("")
    for role in ("primary", "fallback"):
        t = d.get("roles", {}).get(role, {})
        mark = f"{LIME}✓{RESET}" if t.get("agree") else f"{PINK}✗{RESET}"
        out.append(
            f"  {PINK}★{RESET} {LGRN}{role:<12}{str(t.get('caller')):<9}"
            f"{str(t.get('receipt')):<10}{str(t.get('retry_log')):<11}{RESET}{mark}")
        out.append("")
    return "\n".join(out)


# --- Observability views (Module 2, Clip 5) -------------------------------

def _span_tree(spans: list, total: int, highlight: str = "provider_call") -> list:
    out = [f"    {BLUE}{'span':<16}{'duration':<11}{'share'}{RESET}", ""]
    for s in spans:
        name = str(s.get("span"))
        dur = int(s.get("duration_ms", 0))
        is_root = s.get("parent") is None
        share = (dur / total * 100) if total else 0
        bar = "█" * max(1, round(share / 100 * 24)) if not is_root else ""
        label = name if is_root else f"  {name}"   # indent children
        color = PINK if name == highlight else (WHITE if is_root else LGRN)
        barcol = PINK if name == highlight else ADA
        out.append(f"  {PINK}★{RESET} {color}{label:<16}{RESET}"
                   f"{LGRN}{str(dur)+'ms':<11}{RESET}{barcol}{bar}{RESET}")
        out.append("")
    return out


def fmt_trace(d: dict) -> str:
    out = [header(
        "Open the end-to-end trace",
        "One request across ingress, queue, routing, provider call, retry, "
        "fallback, and response", width=80)]
    out += star("trace id", d.get("trace_id"))
    out += star("total", f"{d.get('total_ms')} ms")
    out += sect("span timeline (child spans under the request)")
    out += _span_tree(d.get("spans", []), d.get("total_ms", 1))
    return "\n".join(out)


def fmt_obs_logs(d: dict) -> str:
    out = [header(
        "Inspect the structured logs",
        "Every request logs one record: request id, model, route reason, "
        "tokens, cost, latency, provider status, and quality", width=92)]
    for e in d.get("logs", []):
        qc = LIME if e.get("quality_status") == "pass" else PINK
        sc = _status_color(e.get("provider_status", ""))
        out.append(f"  {PINK}★{RESET} {LGRN}{str(e.get('request_id'))}{RESET}  "
                   f"{LGRN}{str(e.get('model'))}{RESET}  {GRAY}{e.get('route_reason')}{RESET}")
        out.append(f"      {BLUE}tokens{RESET} prompt={e.get('prompt_tokens')} "
                   f"completion={e.get('completion_tokens')} total={e.get('total_tokens')}   "
                   f"{BLUE}cost{RESET} ${float(e.get('cost_usd',0)):.4f}   "
                   f"{BLUE}latency{RESET} {e.get('latency_ms')}ms   "
                   f"{BLUE}status{RESET} {sc}{e.get('provider_status')}{RESET}   "
                   f"{BLUE}quality{RESET} {qc}{e.get('quality_status')}{RESET}")
        out.append("")
    return "\n".join(out)


def fmt_metrics(d: dict) -> str:
    out = [header(
        "Read the Prometheus service metrics",
        "Latency, availability, queue depth, fallback rate, retry rate, and "
        "cost — the operator's health signals", width=80)]
    out += star("requests observed", d.get("requests"))
    out += sect("latency")
    out += _noted("p50", f"{d.get('latency_p50_ms')} ms", "typical request", LIME)
    out += _noted("p95", f"{d.get('latency_p95_ms')} ms", "the slow tail", LGRN)
    out += sect("availability & flow")
    out += _noted("availability", f"{d.get('availability_pct')}%", "requests answered", LIME)
    out += _noted("queue depth", d.get("queue_depth"), "peak backlog")
    out += _noted("fallback rate", f"{d.get('fallback_rate_pct')}%", "served by an alternative", BLUE)
    out += _noted("retry rate", f"{d.get('retry_rate_pct')}%", "attempts that were retried", BLUE)
    out += _noted("cost estimate", f"${d.get('cost_estimate_usd')}", "for this window")
    return "\n".join(out)


def fmt_quality(d: dict) -> str:
    below = float(d.get("pass_rate_pct", 100)) < 90.0
    out = [header(
        "Sample output quality on live responses",
        "Automated checks on a representative subset — a successful response "
        "can still fail quality", width=88)]
    out += star("policy", d.get("policy"))
    out += star("schema", d.get("schema"))
    out += _noted("pass rate", f"{d.get('pass_rate_pct')}%  ({d.get('passed')}/{d.get('sample_size')})",
                  f"quality bar {d.get('quality_bar')}", PINK if below else LIME)
    out += sect("sampled responses")
    out.append(f"    {BLUE}{'request':<18}{'score':<8}{'status':<9}{'reviewer reason'}{RESET}")
    out.append("")
    for s in d.get("samples", []):
        st = str(s.get("quality_status"))
        sc = LIME if st == "pass" else PINK
        out.append(f"  {PINK}★{RESET} {LGRN}{str(s.get('request_id')):<18}"
                   f"{str(s.get('quality_score')):<8}{sc}{st:<9}{RESET}{GRAY}{s.get('reviewer_reason')}{RESET}")
        out.append("")
    return "\n".join(out)


def fmt_slo(d: dict) -> str:
    disp = d.get("disposition")
    out = [header(
        "Confirm the SLO alert rules",
        "Latency, availability, and output quality each get an objective — a "
        "breach fires an alert", width=90)]
    out += star("disposition", disp, PINK if disp == "ALERT" else LIME)
    out.append(f"    {BLUE}{'slo':<20}{'dimension':<16}{'value':<10}{'objective':<14}"
               f"{'status':<9}{'severity'}{RESET}")
    out.append("")
    for s in d.get("slos", []):
        ok = s.get("status") == "ok"
        stc = LIME if ok else PINK
        obj = f"{s.get('comparator')} {s.get('threshold')}"
        out.append(f"  {PINK}★{RESET} {LGRN}{str(s.get('slo')):<20}"
                   f"{str(s.get('dimension')):<16}{str(s.get('value')):<10}{obj:<14}"
                   f"{stc}{str(s.get('status')):<9}{s.get('severity')}{RESET}")
        out.append("")
    return "\n".join(out)


def fmt_diagnose(d: dict) -> str:
    out = [header(
        "Diagnose the slow request from its trace",
        "Nested span timings point at the exact stage that owns the latency",
        width=80)]
    out += star("trace id", d.get("trace_id"))
    out += star("total", f"{d.get('total_ms')} ms")
    out += sect("span timeline")
    out += _span_tree(d.get("spans", []), d.get("total_ms", 1), d.get("slowest_span", ""))
    out += _noted("slowest span", f"{d.get('slowest_span')} — {d.get('slowest_ms')}ms "
                  f"({d.get('slowest_share_pct')}%)", "owns the latency", PINK)
    out += _noted("provider status", d.get("provider_status"), "the fault mode", PINK)
    out += star("root cause", d.get("root_cause"), PINK)
    return "\n".join(out)


def fmt_correlate(d: dict) -> str:
    fail = d.get("quality_status") == "fail"
    out = [header(
        "Correlate cost, quality, and the operator action",
        "One structured record ties tokens and cost to the quality verdict and "
        "what the operator did about it", width=80)]
    out += star("request id", d.get("request_id"))
    out += _noted("total tokens", d.get("total_tokens"), "the work that was billed")
    out += _noted("cost", f"${float(d.get('cost_usd',0)):.4f}", "spent on this response")
    out += _noted("quality status", f"{d.get('quality_status')} (score {d.get('quality_score')})",
                  "trustworthy or not", PINK if fail else LIME)
    out += star("operator action", d.get("operator_action"))
    return "\n".join(out)


# --- Incident diagnosis views (Module 2, Clip 6) --------------------------

def _cell_value(v: Any, unit: str) -> str:
    if unit == "$":
        return f"${float(v):.4f}"
    if unit == "%":
        return f"{v}%"
    if unit == "ms":
        return f"{v}ms"
    return str(v)


def fmt_incident_alerts(d: dict) -> str:
    out = [header(
        "Read the alert timeline",
        "Which signal fired first — the first alert is a symptom, not the root "
        "cause", width=86)]
    out += star("first signal", d.get("first_signal"), PINK)
    out += sect("alerts in fire order")
    for a in d.get("alerts", []):
        sev = str(a.get("severity"))
        sc = PINK if sev == "page" else LGRN
        tag = f"   {PINK}← first bad signal{RESET}" if a.get("first_signal") else ""
        out.append(f"  {PINK}★{RESET} {LGRN}{str(a.get('at')):<8}{RESET}"
                   f"{WHITE}{str(a.get('alert'))}{RESET}{tag}")
        out.append(f"      {BLUE}dimension{RESET} {a.get('dimension')}   "
                   f"{BLUE}severity{RESET} {sc}{sev}{RESET}   "
                   f"{GRAY}{a.get('detail')}{RESET}")
        out.append("")
    return "\n".join(out)


def fmt_incident_dashboard(d: dict) -> str:
    out = [header(
        "Open the operator dashboard",
        "Latency, quota saturation, cost per request, and quality pass rate — "
        "each baseline versus current against its objective", width=100)]
    out += star("window requests", d.get("window_requests"))
    out.append(f"    {BLUE}{'metric':<24}{'dimension':<16}{'baseline':<12}"
               f"{'current':<12}{'objective':<14}{'status'}{RESET}")
    out.append("")
    for p in d.get("panels", []):
        unit = p.get("unit", "")
        breach = p.get("status") == "breach"
        curcol = PINK if breach else LIME
        stc = PINK if breach else LIME
        base_s = _cell_value(p.get("baseline"), unit)
        cur_s = _cell_value(p.get("current"), unit)
        obj_s = f"{p.get('comparator')} {_cell_value(p.get('objective'), unit)}"
        out.append(f"  {PINK}★{RESET} {LGRN}{str(p.get('metric')):<24}{RESET}"
                   f"{GRAY}{str(p.get('dimension')):<16}{RESET}"
                   f"{GRAY}{base_s:<12}{RESET}{curcol}{cur_s:<12}{RESET}"
                   f"{BLUE}{obj_s:<14}{RESET}{stc}{p.get('status')}{RESET}")
        out.append("")
    out.append(f"  {GRAY}{d.get('note')}{RESET}")
    return "\n".join(out)


def fmt_incident_isolate(d: dict) -> str:
    out = [header(
        "Isolate the latency from one trace",
        "Queueing, retry, and fallback are innocent — the degraded provider call "
        "owns the time", width=88)]
    out += star("trace id", d.get("trace_id"))
    out += star("total", f"{d.get('total_ms')} ms")
    out += sect("who owns the time (queueing / retry / fallback / provider)")
    out.append(f"    {BLUE}{'stage':<16}{'duration':<11}{'share':<9}{'verdict'}{RESET}")
    out.append("")
    for c in d.get("contributors", []):
        root = c.get("verdict") == "root cause"
        vc = PINK if root else LIME
        barcol = PINK if root else ADA
        share = float(c.get("share_pct", 0))
        bar = "█" * max(1, round(share / 100 * 20))
        out.append(f"  {PINK}★{RESET} {LGRN}{str(c.get('stage')):<16}"
                   f"{str(c.get('ms'))+'ms':<11}{str(c.get('share_pct'))+'%':<9}{RESET}"
                   f"{barcol}{bar}{RESET} {vc}{c.get('verdict')}{RESET}")
        out.append("")
    out += _noted("provider", f"{d.get('provider')} ({d.get('provider_status')})",
                  "the fault mode", PINK)
    out += star("root cause", d.get("root_cause"), PINK)
    return "\n".join(out)


def fmt_incident_quota(d: dict) -> str:
    out = [header(
        "Prove the quota pressure and the shed",
        "Admission control sheds excess load with a 429 and a Retry-After, "
        "protecting the provider behind its quota", width=88)]
    out += _noted("provider", f"{d.get('provider')} · {d.get('tier')}",
                  f"{d.get('quota_mode')} quota, {d.get('request_class')} class")
    out += _noted("rate limit", f"{d.get('rate_limit')} per {d.get('window_seconds')}s",
                  "the operator's shed knob")
    out += sect("what happened to the burst")
    out += _noted("submitted", d.get("submitted"), "requests in the window")
    out += _noted("accepted", d.get("accepted"), "admitted and served", LIME)
    out += _noted("rejected (429)", d.get("rejected_429"),
                  f"shed with Retry-After {d.get('retry_after_seconds')}s", PINK)
    out += _noted("quota utilization", f"{d.get('quota_utilization_pct')}%",
                  "the provider, held below exhaustion", PINK)
    out += star("provider status", d.get("provider_status"),
                _status_color(d.get("provider_status", "")))
    out.append(f"  {GRAY}{d.get('note')}{RESET}")
    return "\n".join(out)


def fmt_incident_cost(d: dict) -> str:
    up = float(d.get("current_per_request_usd", 0)) > float(d.get("baseline_per_request_usd", 0))
    out = [header(
        "Trace the cost drift to its cause",
        "The extra dollars tie to retries and failover on the degraded provider "
        "— reconciled to the cent, not hand-waved", width=90)]
    out += _noted("baseline", f"${float(d.get('baseline_per_request_usd',0)):.4f} / request",
                  "before the incident")
    out += _noted("current", f"${float(d.get('current_per_request_usd',0)):.4f} / request",
                  f"+{d.get('drift_pct')}%", PINK if up else LIME)
    out += _noted("objective", f"${float(d.get('objective_per_request_usd',0)):.4f} / request",
                  "the cost budget", BLUE)
    out += sect("where the extra dollars went")
    out.append(f"    {BLUE}{'driver':<26}{'add / request':<16}{'why'}{RESET}")
    out.append("")
    for dr in d.get("drivers", []):
        out.append(f"  {PINK}★{RESET} {LGRN}{str(dr.get('driver')):<26}"
                   f"+${float(dr.get('add_per_request_usd',0)):.4f}{RESET}")
        out.append(f"      {GRAY}{dr.get('detail')}{RESET}")
        out.append("")
    rc = LIME if d.get("reconciles") else PINK
    out += star("reconciles to current", str(d.get("reconciles")).lower(), rc)
    out.append(f"  {GRAY}{d.get('note')}{RESET}")
    return "\n".join(out)


def fmt_incident_quality(d: dict) -> str:
    below = float(d.get("pass_rate_pct", 100)) < float(d.get("objective_pass_rate_pct", 90))
    out = [header(
        "Confirm the quality regression from sampling",
        "Grouped failure reasons that cluster on the degraded provider — every "
        "failure is a confident, wrong 200", width=90)]
    out += _noted("pass rate",
                  f"{d.get('pass_rate_pct')}%  ({d.get('passed')}/{d.get('sample_size')})",
                  f"baseline {d.get('baseline_pass_rate_pct')}%, objective "
                  f">= {d.get('objective_pass_rate_pct')}%", PINK if below else LIME)
    out += sect("failure reasons (grouped)")
    for r in d.get("failure_reasons", []):
        out.append(f"  {PINK}★{RESET} {LGRN}{str(r.get('reason')):<34}{RESET}"
                   f"{PINK}×{r.get('count')}{RESET}")
        out.append("")
    out += _noted("cluster", d.get("cluster"), "not random — the degraded provider", PINK)
    out.append(f"  {GRAY}{d.get('note')}{RESET}")
    return "\n".join(out)


def fmt_incident_action(d: dict) -> str:
    out = [header(
        "Choose the operator action from the evidence",
        "Four alerts, one provider fault, one evidence-based decision per "
        "dimension — act on the cause, not each symptom", width=94)]
    out += star("root cause", d.get("root_cause"), PINK)
    out += sect("decisions (evidence → action → expected effect)")
    for dec in d.get("decisions", []):
        out.append(f"  {PINK}★{RESET} {WHITE}{str(dec.get('dimension'))}{RESET}   "
                   f"{GRAY}{dec.get('evidence')}{RESET}")
        out.append(f"      {BLUE}action{RESET} {LGRN}{dec.get('action')}{RESET}")
        out.append(f"      {BLUE}expected{RESET} {ADA}{dec.get('expected_effect')}{RESET}")
        out.append("")
    disp = d.get("disposition")
    out += star("disposition", disp, LIME if disp == "ACT" else PINK)
    out.append(f"  {GRAY}{d.get('note')}{RESET}")
    return "\n".join(out)


VIEWS = {
    "health": fmt_health,
    "providers": fmt_providers,
    "probe": fmt_probe,
    "conditions": fmt_conditions,
    "route": fmt_route,
    "receipt": fmt_receipt,
    "policy": fmt_policy,
    "batch": fmt_batch,
    "samples": fmt_samples,
    "counters": fmt_counters,
    "receipts": fmt_receipts,
    "validate": fmt_validate,
    "rules": fmt_rules,
    "smart": fmt_smart,
    "smart-validate": fmt_smart_validate,
    "smart-pair": fmt_smart_pair,
    "smart-receipts": fmt_smart_receipts,
    "smart-counters": fmt_smart_counters,
    "redis-counters": fmt_redis_counters,
    "mixed": fmt_mixed,
    "mixed-samples": fmt_mixed_samples,
    "mixed-counters": fmt_mixed_counters,
    "mixed-receipts": fmt_mixed_receipts,
    "disposition": fmt_disposition,
    "spike": fmt_spike,
    "k6-summary": fmt_k6_summary,
    "queue": fmt_queue,
    "queue-list": fmt_queue_list,
    "ratelimit": fmt_ratelimit,
    "matrix": fmt_matrix,
    "failfast": fmt_failfast,
    "dispositions": fmt_dispositions,
    "admission-logs": fmt_admission_logs,
    "circuit-config": fmt_circuit_config,
    "circuit": fmt_circuit,
    "fallback": fmt_fallback,
    "retry-log": fmt_retry_log,
    "failover-reconcile": fmt_failover_reconcile,
    "trace": fmt_trace,
    "obs-logs": fmt_obs_logs,
    "metrics": fmt_metrics,
    "quality": fmt_quality,
    "slo": fmt_slo,
    "diagnose": fmt_diagnose,
    "correlate": fmt_correlate,
    "incident-alerts": fmt_incident_alerts,
    "incident-dashboard": fmt_incident_dashboard,
    "incident-isolate": fmt_incident_isolate,
    "incident-quota": fmt_incident_quota,
    "incident-cost": fmt_incident_cost,
    "incident-quality": fmt_incident_quality,
    "incident-action": fmt_incident_action,
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
        # psql -tA emits one JSON object per row; treat multiple lines as a list.
        lines = [ln for ln in raw.splitlines() if ln.strip()]
        try:
            data = [json.loads(ln) for ln in lines]
            if len(data) == 1:
                data = data[0]
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
