# Module 3 — Demo: Validate model updates against quality baselines

## Why this matters

**The problem:** A provider ships a new model version, or your team fine-tunes one,
and the temptation is to swap it in because the demo looked better. That is how you
ship a regression to production. A newer model is not automatically a better one — it
can be cheaper but dumber, faster but off-contract, or higher quality but too slow
for your latency budget. "It felt better in a few prompts" is not a release
criterion. The only safe way to promote a model is to make it earn the promotion
against a written baseline — quality, latency, cost, failure rate, and output-contract
compliance — enforced by a test that fails the build when a candidate falls short.
How do you stop a plausible-looking model update from becoming a silent production
regression?

**What you will see:** Four moves that turn a model swap into a gated release — the
real Pytest baseline suite that enforces the gate and the baseline it asserts, five
dimensions each with a floor or a ceiling; a passing candidate that clears every
threshold and earns eligibility; a failing candidate that drifts on four dimensions
and is blocked with the breaches named; and the release decision that promotes one and
blocks the other while making neither the default, reconciled against a production
state that stays on the approved model until a candidate truly earns its place.

**What you walk away with:** A model update validation workflow that tests
candidates against quality and performance baselines before promotion (EO4b) — so no
model becomes the default on a hunch.

## Learning objectives covered

| Step | LO sub-element | What proves it |
|------|----------------|----------------|
| 1 | EO4b | A real Pytest suite enforces the baseline gate — the criteria are code, not a claim — and the baseline spans quality, latency, cost, failure rate, and output-contract compliance |
| 2 | EO4b | A candidate within every threshold is eligible for promotion |
| 3 | EO4b | A candidate that drifts on any dimension is blocked, with the breaches named |
| 4 | EO4b | The release decision promotes the passer, blocks the failer, defaults neither — and production stays on the approved model until a candidate earns promotion |

## What this demo proves — and each step is unique

| Step | Command | What it teaches (nothing repeats) |
|------|---------|-----------------------------------|
| 1 | `.venv/bin/python -m pytest tests/baseline` + `/lifecycle/validation/gate` + `/lifecycle/validation/baseline` | The gate is a real, runnable test, and the written criteria a candidate must meet |
| 2 | `/lifecycle/validation/pass` | What clearing every threshold looks like |
| 3 | `/lifecycle/validation/fail` | How a drift is caught and named |
| 4 | `/lifecycle/validation/decision` + `/lifecycle/validation/reconcile` | Eligibility is not the same as default, and the default holds until promotion is earned |

## Prerequisites

### Software this clip needs — do you have it?

This clip uses **Docker Desktop** (with Compose), **curl**, **jq**, **python3**,
**Pytest**, **psql**, and **tmux**. Two commands cover every case:

```bash
bash scripts/ensure-ready.sh       # CHECK  — ✔ / ✗ for each tool, with a fix for anything missing
bash environment-setup/setup.sh    # INSTALL — one step: installs everything the course uses, then the pinned deps
```

- **First time on this Mac?** Run the install step once. When it prints `READY`,
  you have everything this clip needs, including Pytest.
- **Already set up?** The check confirms you're good in seconds.

> **Why the suite runs as `.venv/bin/python -m pytest`:** `setup.sh` installs the
> pinned `pytest==9.1.1` into the project virtualenv at `.venv/`, not your system
> Python. Invoking the venv's interpreter directly runs that pinned Pytest with no
> `pip install` on your host and no dependence on what `python3` resolves to — which
> is exactly why a bare `pytest` or a Homebrew `python3 -m pytest` can report
> `command not found` / `No module named pytest` even though the gate is installed.

### Start the stack

**Start the stack first.** This brings up FastAPI, Redis, and PostgreSQL and waits
until healthy:

```bash
bash module3/scripts/demo_up.sh
```

The baseline gate is a real Pytest suite under `tests/baseline/`; the API endpoints
read the same validation logic the tests assert. Reset before you start:

```bash
./scripts/module3-demo-reset.sh
```

## Demo steps

### Step 1: Run the baseline gate (Pytest) and inspect the thresholds

**Goal:** Run the real Pytest baseline suite and read the gate summary, so the
promotion criteria are a runnable test rather than a promise — then read the baseline
itself, the five dimensions and the floor or ceiling each candidate must respect.

```bash
curl -s -X POST http://localhost:8000/lifecycle/validation/run >/dev/null
.venv/bin/python -m pytest tests/baseline -q
curl -s http://localhost:8000/lifecycle/validation/gate | python3 scripts/fmt.py --type validation-gate \
  --title "Run the baseline gate" \
  --why "A candidate must clear a five-dimension baseline — enforced by a real Pytest suite — before promotion"
curl -s http://localhost:8000/lifecycle/validation/baseline | python3 scripts/fmt.py --type validation-baseline \
  --title "Inspect the baseline thresholds" \
  --why "The approved baseline every candidate is measured against — quality, latency, cost, failure rate, and contract compliance"
```

**Expected output:** first Pytest reports the baseline suite passing, then ★ `approved
model: balanced-std@2026-06`, ★ `checks: 10` (`5 dimensions × 2 candidates`), and
the two candidates — `balanced-std@2026-07` `eligible`, `econo-fast@2026-07`
`blocked (4 breaches)` — with ★ `gate enforced: true`. Then the baseline itself —
★ `approved model: balanced-std@2026-06`, and five dimensions, each showing the
**approved model's own measured value** against its floor or ceiling: quality `0.91`
(`>= 0.90`), latency `790ms` (`<= 800ms`), cost `$0.34` (`<= $0.35`), failure `0.7%`
(`<= 1.0%`), and contract `99.5%` (`>= 99.0%`) — the approved model clears every
threshold, which is why it holds the production default.

**What the learner should notice:** The most important thing on this screen is that
the gate is a *test*, not a spreadsheet. When Pytest goes green, it is asserting the
exact thresholds you are looking at, which means the gate runs in CI and fails the
build when a candidate falls short — no human has to remember to check. The gate
evaluates two candidates across five dimensions, ten checks in all, and it has
already reached a verdict: one candidate is eligible, one is blocked with four
breaches. And that baseline is written down before you have a candidate, so nobody
moves the goalposts to fit the model they already like. Read the directions carefully:
two of these are floors — quality and contract compliance must be *at least* their
threshold — and three are ceilings — latency, cost, and failure rate must be *at most*
theirs. That mix is the point. A model can win on cost and still lose the release by
being slow or off-contract. The baseline refuses to let one good number paper over a
bad one, and that is exactly the discipline that keeps a model swap from becoming a
regression. And notice you are not measuring against an abstract limit alone: the
approved model's *own* five numbers are on screen, so when you read each candidate's
scorecard next you are comparing model to model — approved → candidate → threshold —
not model to a bare line in the sand.

### Step 2: Validate the passing candidate

**Goal:** Read the passing candidate's scorecard and confirm every dimension lands
inside its threshold.

```bash
curl -s http://localhost:8000/lifecycle/validation/pass | python3 scripts/fmt.py --type validation-candidate \
  --title "Validate the passing candidate" \
  --why "Every dimension is within its threshold — the candidate is eligible for promotion"
```

**Expected output:** ★ `candidate: balanced-std@2026-07`, ★ `verdict: eligible`, then
five rows all `pass`, each read as **approved → candidate → objective**: quality
`0.91 → 0.93` (`>= 0.90`), latency `790 → 760ms` (`<= 800ms`), cost `$0.34 → $0.32`
(`<= $0.35`), failure `0.7 → 0.4%` (`<= 1.0%`), contract `99.5 → 100.0%` (`>= 99.0%`) —
the candidate matches or beats the approved model on every dimension.

**What the learner should notice:** This is what earning a promotion looks like:
every single row is green, with real margin on each one. Notice it is not close — the
candidate is not squeaking past on quality while barely holding latency; it is
comfortably inside all five. That margin matters, because production is noisier than a
test fixture, and a candidate that only just clears the bar in evaluation will drift
below it under real traffic. When you promote this model, you are not hoping it is
good enough — you have five independent measurements that each said yes.

### Step 3: Validate the failing candidate

**Goal:** Read the failing candidate's scorecard and see exactly which dimensions
drifted past their thresholds.

```bash
curl -s http://localhost:8000/lifecycle/validation/fail | python3 scripts/fmt.py --type validation-candidate \
  --title "Validate the failing candidate" \
  --why "The dimensions that drifted past threshold block the candidate from promotion"
```

**Expected output:** ★ `candidate: econo-fast@2026-07`, ★ `verdict: blocked`, then the
rows as **approved → candidate → objective**: quality `0.91 → 0.86` breach, latency
`790 → 900ms` breach, cost `$0.34 → $0.30` pass, failure `0.7 → 2.1%` breach, contract
`99.5 → 96.5%` breach — and ★ `breaches: quality_score, latency_p95_ms,
failure_rate_pct, contract_compliance_pct`. Cost is the only dimension where this
candidate beats the approved model — cheaper, but worse on the other four.

**What the learner should notice:** This is the model that "felt fast," and the
scorecard shows why fast is not enough. Cost passes — it is genuinely cheaper — but it
breaches four of the five dimensions: lower quality, slower tail latency, a higher
failure rate, and worse contract compliance. This is exactly the trap the baseline
exists to catch. Without it, someone sees the lower cost, swaps the model in, and
ships four regressions to defend one improvement. The gate names every breach, so the
block is not a vibe — it is a list you could hand to the model's owner and say "fix
these four things and come back."

### Step 4: Record the release decision and reconcile the release state

**Goal:** Read the release decision for each candidate and confirm eligibility does
not automatically make a model the default — then confirm production still runs the
approved model and only baseline-passing candidates are eligible to move forward.

```bash
curl -s http://localhost:8000/lifecycle/validation/decision | python3 scripts/fmt.py --type validation-decision \
  --title "Record the release decision" \
  --why "Promote the candidate that cleared the baseline, block the one that did not — neither becomes the default without passing"
curl -s http://localhost:8000/lifecycle/validation/reconcile | python3 scripts/fmt.py --type validation-reconcile \
  --title "Reconcile the release state" \
  --why "The default stays on the approved model; only a baseline-passing candidate is eligible for promotion, and the production default does not change until one earns it"
```

**Expected output:** first the decision — `balanced-std@2026-07` →
`promote_to_candidate_default` with `becomes default: false`; `econo-fast@2026-07` →
`blocked` with `becomes default: false` and the breaches listed. Then the
reconciliation — ★ `disposition: CONFIRMED`, ★ `approved model:
balanced-std@2026-06` (`default unchanged`), ★ `eligible candidates:
balanced-std@2026-07`, ★ `blocked candidates: econo-fast@2026-07`, ★ `gate enforced:
true`.

**What the learner should notice:** Here is the subtlety that separates a mature
release process from a naive one: passing the baseline makes a candidate *eligible*,
not *live*. The passing model is promoted to candidate default — but `becomes default`
is `false`, because eligibility is not the same as being the production default.
Clearing the baseline earns a candidate the right to move forward, not a coronation.
The failing model is blocked outright. Two candidates, two decisions, and neither one
flips the production default. The reconciliation makes that safety property explicit:
the disposition is `CONFIRMED`, and read what it is confirming: production never moved.
Through this entire evaluation — a passing candidate, a failing candidate, two
decisions — the default stayed on the approved model. A model update process should be
boring from production's point of view: candidates are measured, some become eligible,
some are sent back, and the live default does not budge until a candidate has earned it
against the baseline. The gate is enforced by a test, the default is protected by
policy, and nothing ships on a hunch.

## Preflight check

```bash
bash module3/scripts/m3-demo3-model-update-validation.preflight.sh
```

Runs every step above (including the real Pytest suite), captures each command and
its output, maps each step to EO4b, and writes a readable log to
`preflight-logs/m3-demo3-model-update-validation.log`. Expect `PASS: 4  FAIL: 0`.

## Cleanup

```bash
./scripts/module3-demo-reset.sh
```

## Key files

- `tests/baseline/test_model_baseline.py` — the real Pytest suite that enforces the
  baseline gate
- `app/lifecycle/validation.py` — the baseline thresholds, the per-candidate
  evaluation, and the promotion gate (the same logic the tests assert)
- `app/main.py` — the `/lifecycle/validation/run`, `/lifecycle/validation/gate`,
  `/lifecycle/validation/baseline`, `/lifecycle/validation/pass`,
  `/lifecycle/validation/fail`, `/lifecycle/validation/decision`, and
  `/lifecycle/validation/reconcile` endpoints
- `scripts/fmt.py` — the `validation-gate` / `validation-baseline` /
  `validation-candidate` / `validation-decision` / `validation-reconcile` views
