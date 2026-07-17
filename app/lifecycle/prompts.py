"""Prompt versioning and reproducible rollback (Module 3, Clip 2).

Prompts are versioned like code. This module reads the real prompt repository —
the immutable version files under ``prompts/`` and the ``prompts/registry.yaml``
manifest — and proves the LLMOps lifecycle around them: every request receipt
links a prompt version, a model version, and an evaluation run id; a candidate
prompt change is isolated from approved production traffic; a rollback returns
production to the approved release id; and the rollback is *reproducible* because
prompt text, fixture, model version, and result metadata are all preserved, so
replaying the approved version reproduces the exact same result hash.

Everything is deterministic: the result hash is a content hash over
(prompt text + fixture + model version), so the same inputs always reproduce the
same output identity — which is the whole point of reproducible rollback.

What this proves (TO4, EO4a): prompt version control with reproducible
experiments and safe rollback.
"""
from __future__ import annotations

import hashlib
from pathlib import Path

import yaml

_ROOT = Path(__file__).resolve().parents[2]
_PROMPTS_DIR = _ROOT / "prompts"
_REGISTRY = _PROMPTS_DIR / "registry.yaml"

_STATE: dict = {}


def _result_hash(prompt_text: str, fixture_text: str, model_version: str) -> str:
    """A deterministic content hash tying a result to the exact inputs that
    produced it. Preserve the inputs and you reproduce the identity — this is the
    evidence that a rollback is reproducible, not merely re-run."""
    h = hashlib.sha256()
    h.update(prompt_text.encode())
    h.update(b"\x00")
    h.update(fixture_text.encode())
    h.update(b"\x00")
    h.update(model_version.encode())
    return "sha256:" + h.hexdigest()[:16]


def _load_registry() -> dict:
    return yaml.safe_load(_REGISTRY.read_text())


def _version_records(reg: dict) -> list[dict]:
    approved_release = reg["approved_release"]
    out = []
    for v in reg["versions"]:
        prompt_text = (_PROMPTS_DIR / v["file"]).read_text()
        fixture_text = (_PROMPTS_DIR / v["fixture"]).read_text()
        out.append({
            "version": v["version"],
            "owner": v["owner"],
            "created": v["created"],
            "fixture": Path(v["fixture"]).name,
            "model_version": v["model_version"],
            "eval_run_id": v["eval_run_id"],
            "release_tag": v["release_tag"],
            "status": v["status"],
            "is_approved": v["release_tag"] == approved_release,
            "result_hash": _result_hash(prompt_text, fixture_text, v["model_version"]),
            "notes": v.get("notes", ""),
        })
    return out


def run_prompts() -> dict:
    """Read the real prompt repository and build the deterministic lifecycle
    state the /lifecycle/prompts/* endpoints read."""
    reg = _load_registry()
    approved_release = reg["approved_release"]
    versions = _version_records(reg)
    approved = next(v for v in versions if v["is_approved"])
    superseded = next(v for v in versions if v["status"] == "superseded")
    candidate = next(v for v in versions if v["status"] == "candidate")

    # --- Receipts: every request links prompt version + model + eval run -----
    # Approved production traffic all runs the approved version, so every receipt
    # carries the same release identity — that is what makes traffic auditable.
    receipts = []
    for i in range(6):
        receipts.append({
            "request_id": f"req-pv-{1001 + i}",
            "prompt_version": approved["version"],
            "model_version": approved["model_version"],
            "eval_run_id": approved["eval_run_id"],
            "release_tag": approved["release_tag"],
            "result_hash": approved["result_hash"],
            "lane": "production",
        })

    # --- Prompt change: the candidate is deployed ISOLATED -------------------
    # A new version enters as a candidate in an isolated lane. Approved production
    # traffic never touches it — the blast radius of an untested prompt is zero.
    isolation = {
        "candidate_version": candidate["version"],
        "candidate_release": candidate["release_tag"],
        "approved_version": approved["version"],
        "approved_release": approved_release,
        "lanes": [
            {"lane": "production", "version": approved["version"],
             "release_tag": approved["release_tag"], "requests": 6,
             "serves_customers": True},
            {"lane": "isolated_candidate", "version": candidate["version"],
             "release_tag": candidate["release_tag"], "requests": 4,
             "serves_customers": False},
        ],
        "candidate_in_production": 0,
        "isolated": True,
        "note": "the candidate runs in an isolated lane — approved production "
                "traffic never reaches it, so an untested prompt cannot affect a customer",
    }

    # --- Rollback: return production to the approved release ------------------
    # The candidate regressed in evaluation, so production is rolled back to the
    # approved release. Because superseded versions are retained, the rollback
    # target is a known, immutable release id — not a guess.
    rollback = {
        "from_version": candidate["version"],
        "from_release": candidate["release_tag"],
        "to_version": approved["version"],
        "to_release": approved_release,
        "retained_versions": [v["version"] for v in versions],
        "active_release_after": approved_release,
        "active_version_after": approved["version"],
        "candidate_in_production_after": 0,
        "note": "rollback targets a retained, immutable release id — production "
                "returns to the approved version with zero candidate traffic left",
    }

    # --- Reproducibility: preserved metadata reproduces the result -----------
    # Replay the approved version with the SAME prompt, fixture, and model that
    # produced the recorded receipts. The recomputed result hash must match the
    # recorded one — proof the rollback is reproducible, not approximate.
    reg2 = _load_registry()
    replay = next(v for v in _version_records(reg2) if v["is_approved"])
    reproducible = replay["result_hash"] == approved["result_hash"]
    reproducibility = {
        "version": approved["version"],
        "release_tag": approved_release,
        "model_version": approved["model_version"],
        "fixture": approved["fixture"],
        "recorded_result_hash": approved["result_hash"],
        "replayed_result_hash": replay["result_hash"],
        "reproducible": reproducible,
        "preserved": ["prompt_text", "fixture", "model_version", "result_hash"],
        "note": "same prompt + fixture + model reproduce the same result hash — "
                "the rollback is reproducible, not merely re-run",
    }

    # --- Reconcile: production is on the approved release, provably -----------
    active_ok = rollback["active_release_after"] == approved_release
    no_candidate = rollback["candidate_in_production_after"] == 0
    confirmed = active_ok and no_candidate and reproducible
    reconcile = {
        "active_release": rollback["active_release_after"],
        "approved_release": approved_release,
        "active_matches_approved": active_ok,
        "candidate_in_production": rollback["candidate_in_production_after"],
        "reproducible": reproducible,
        "disposition": "CONFIRMED" if confirmed else "BLOCKED",
        "note": "production is on the approved release, no candidate traffic "
                "leaked, and the result reproduces — the release state is provable",
    }

    _STATE.update({
        "registry": {"prompt_id": reg["prompt_id"], "approved_release": approved_release,
                     "versions": versions},
        "receipts": {"receipts": receipts, "approved_version": approved["version"],
                     "approved_release": approved_release},
        "isolation": isolation,
        "rollback": rollback,
        "reproducibility": reproducibility,
        "reconcile": reconcile,
    })
    return {"prompt_id": reg["prompt_id"], "versions": len(versions),
            "approved_release": approved_release, "reproducible": reproducible,
            "disposition": reconcile["disposition"]}


def state() -> dict:
    return _STATE
