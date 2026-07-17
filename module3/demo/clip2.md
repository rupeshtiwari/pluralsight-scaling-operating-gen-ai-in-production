# Module 3 — Demo: Prove prompt versioning and reproducible rollback

## Why this matters

**The problem:** A prompt is not a comment — it is production code that shapes
every answer your service returns, and yet teams routinely edit prompts live, in a
console, with no version, no owner, and no way back. Then quality drops, nobody can
say what changed, and "roll it back" means retyping a prompt from memory. That is
not an operation, it is a gamble. If you cannot name the exact prompt, model, and
fixture behind a result, you cannot reproduce it, and if you cannot reproduce it,
you cannot safely roll back to it. Treating prompts like code — versioned, owned,
released, and reversible — is the first discipline of LLMOps. How do you make every
prompt change traceable, isolate an untested change from customers, and roll back
to a known-good release that reproduces exactly?

**What you will see:** Six moves that turn prompts into managed releases — the
version registry where each prompt version carries an owner, a fixture, a model
pin, an evaluation run, a release tag, and a lifecycle status; the receipts that
stamp that release identity onto every request; a candidate change deployed into an
isolated lane that approved production traffic never touches; a rollback that
returns production to the approved release id; the reproducibility proof where the
preserved prompt, fixture, and model regenerate the exact same result hash; and the
reconciliation that shows the release state is provable, not hoped for.

**What you walk away with:** Prompt version control that enables reproducible
experiments and safe rollback (EO4a) — the foundation of managing the operational
lifecycle of prompts and models (TO4).

## Learning objectives covered

| Step | LO sub-element | What proves it |
|------|----------------|----------------|
| 1 | EO4a | Prompts are versioned like code, each with owner, fixture, model pin, eval run, release, and status |
| 2 | EO4a | Every request receipt links a prompt version, model version, and evaluation run id |
| 3 | EO4a | A candidate change is isolated so approved production traffic never reaches it |
| 4 | EO4a | A rollback returns production to the approved release id, targeting a retained version |
| 5 | EO4a | The rollback is reproducible — preserved prompt, fixture, and model reproduce the result hash |
| 6 | TO4, EO4a | The release state reconciles to a provable, approved production state |

## What this demo proves — and each step is unique

| Step | Command | What it teaches (nothing repeats) |
|------|---------|-----------------------------------|
| 1 | `/lifecycle/prompts/registry` | A prompt version is a release with metadata, not a string |
| 2 | `/lifecycle/prompts/receipts` | Every request carries its release identity |
| 3 | `/lifecycle/prompts/isolation` | A candidate change reaches zero customers |
| 4 | `/lifecycle/prompts/rollback` | Rollback targets a retained, immutable release |
| 5 | `/lifecycle/prompts/reproducibility` | Preserved inputs reproduce the exact result |
| 6 | `/lifecycle/prompts/reconcile` | The production release state is provable |

## Prerequisites

### Software this clip needs — do you have it?

This clip uses **Docker Desktop** (with Compose), **curl**, **jq**, **python3**,
**psql**, and **tmux**. Two commands cover every case:

```bash
bash scripts/ensure-ready.sh       # CHECK  — ✔ / ✗ for each tool, with a fix for anything missing
bash environment-setup/setup.sh    # INSTALL — one step: installs everything the course uses, then the pinned deps
```

- **First time on this Mac?** Run the install step once. When it prints `READY`,
  you have everything this clip needs.
- **Already set up?** The check confirms you're good in seconds.

### Start the stack

**Start the stack first.** This brings up FastAPI, Redis, and PostgreSQL and waits
until healthy:

```bash
bash module3/scripts/demo_up.sh
```

The prompt repository this clip inspects lives in the source tree under
`prompts/` — the version files and the `prompts/registry.yaml` manifest are real
files the service reads. Reset before you start:

```bash
./scripts/module3-demo-reset.sh
```

## Demo steps

### Step 1: Inspect the prompt version registry

**Goal:** Read the prompt repository and see each version as a release — with its
owner, fixture, model pin, evaluation run, release tag, and lifecycle status.

```bash
curl -s -X POST http://localhost:8000/lifecycle/prompts/run >/dev/null
curl -s http://localhost:8000/lifecycle/prompts/registry | python3 scripts/fmt.py --type lc-registry \
  --title "Inspect the prompt version registry" \
  --why "Prompts versioned like code — owner, fixture, model pin, eval run, release tag, and status"
```

**Expected output:** ★ `prompt id: support_summary`, ★ `approved release:
rel-2026.06`, then three versions — `v1.0.0` (`superseded`), `v2.0.0` (`approved`,
marked `← approved`), and `v3.0.0-rc1` (`candidate`) — each with its model version,
eval run id, release tag, and a `result hash`.

**What the learner should notice:** This is the whole mindset shift in one screen:
a prompt is a *release*, not a string you paste. Every version has an owner who is
accountable, a fixture it was tested against, the exact model it was pinned to, the
evaluation run that graded it, and a release tag you can name in an incident. One
version — `v2.0.0` — is marked approved, and that single flag is the source of
truth for what production runs. The candidate, `v3.0.0-rc1`, exists in the registry
but is explicitly not approved. You are looking at prompt management that a
regulated team could audit, and it starts by refusing to treat prompts casually.

### Step 2: Link prompt version, model, and eval run to receipts

**Goal:** Confirm every request receipt stamps the full release identity, so any
answer can be traced back to the exact prompt, model, and evaluation behind it.

```bash
curl -s http://localhost:8000/lifecycle/prompts/receipts | python3 scripts/fmt.py --type lc-prompt-receipts \
  --title "Link prompt version, model, and eval run to receipts" \
  --why "Every receipt carries the release identity — prompt version, model version, evaluation run, release tag, and result hash"
```

**Expected output:** ★ `approved version: v2.0.0` (`release rel-2026.06`), then six
receipts — each on `v2.0.0` with model `balanced-std@2026-06`, eval run `ev-1042`,
release `rel-2026.06`, and the same `result hash`.

**What the learner should notice:** Here is why the registry matters in practice.
Every receipt carries the release identity, so you can take any single answer your
service returned and say exactly which prompt version, which model version, and
which evaluation run produced it. Notice that all six receipts share one result
hash — that is not a coincidence, it is determinism: the same prompt, fixture, and
model produce the same result identity every time. That property is what makes the
next four steps possible. Without a stamped release identity on every request, an
audit is archaeology; with it, an audit is a database query.

### Step 3: Deploy the prompt change to an isolated lane

**Goal:** Deploy the candidate version and prove it runs in an isolated lane that
approved production traffic never enters.

```bash
curl -s http://localhost:8000/lifecycle/prompts/isolation | python3 scripts/fmt.py --type lc-isolation \
  --title "Deploy the prompt change to an isolated lane" \
  --why "A candidate enters isolated — approved production traffic never reaches it, so an untested prompt cannot affect a customer"
```

**Expected output:** ★ `candidate: v3.0.0-rc1`, ★ `approved: v2.0.0`, then two
traffic lanes — `production` on `v2.0.0` serving customers `true`, and
`isolated_candidate` on `v3.0.0-rc1` serving customers `false` — and ★ `candidate
in production: 0`.

**What the learner should notice:** This is blast-radius control for prompts. The
candidate is deployed — it is running, it is receiving traffic in its own lane —
but that lane is isolated, and the "serves customers" column tells the whole story:
`true` for production, `false` for the candidate. The number that matters is
`candidate in production: 0`. An untested prompt change cannot touch a single real
customer, no matter how confident the author is. This is the difference between
"we pushed a prompt and we'll watch" and "we deployed a candidate and it is
structurally incapable of harming production." One of those is a hope; the other is
a control.

### Step 4: Roll back production to the approved release

**Goal:** Roll the candidate back and confirm production returns to the approved
release id, targeting a version that was retained, not reconstructed.

```bash
curl -s http://localhost:8000/lifecycle/prompts/rollback | python3 scripts/fmt.py --type lc-rollback \
  --title "Roll back production to the approved release" \
  --why "The rollback targets a retained, immutable release id — production returns to the approved version with zero candidate traffic"
```

**Expected output:** ★ `from: v3.0.0-rc1`, ★ `to: v2.0.0 (rel-2026.06)`, ★ `active
release after: rel-2026.06`, ★ `candidate in production after: 0`, with the
retained versions listed.

**What the learner should notice:** Watch what rollback actually means here. It is
not "retype the old prompt and hope" — it is a pointer move back to a release id
that still exists, byte for byte, in the registry. The candidate is withdrawn but
retained, so nothing is lost and the history stays intact. The active release
returns to `rel-2026.06`, and candidate traffic in production is zero. Because every
prior version is kept, your rollback target is always a known, immutable artifact.
This is the payoff of versioning prompts like code: the same `git revert` safety you
expect from application code now applies to the prompt that steers your model.

### Step 5: Prove the rollback is reproducible

**Goal:** Replay the approved version with its preserved prompt, fixture, and model,
and confirm the result hash matches — proving the rollback is reproducible, not
approximate.

```bash
curl -s http://localhost:8000/lifecycle/prompts/reproducibility | python3 scripts/fmt.py --type lc-reproducibility \
  --title "Prove the rollback is reproducible" \
  --why "Preserved prompt, fixture, and model reproduce the same result hash — reproducible, not merely re-run"
```

**Expected output:** ★ `version: v2.0.0`, ★ `recorded result hash` and ★ `replayed
result hash` — identical — and ★ `reproducible: true`, with the preserved inputs
listed (`prompt_text`, `fixture`, `model_version`, `result_hash`).

**What the learner should notice:** This is the step that separates a real rollback
from a superstitious one. Anyone can re-run an old prompt; the question is whether
you get the *same thing back*. Here the recorded hash and the replayed hash are
identical, and `reproducible` is `true`. That works only because the release
preserved everything that determines the output — the prompt text, the fixture, and
the model version — so replaying them regenerates the exact same result identity.
Reproducibility is not a nice-to-have here; it is the definition of a trustworthy
rollback. If replaying the approved release produced a different hash, your "known
good" release would not actually be known, and you would be one bad prompt away from
an incident you cannot undo.

### Step 6: Reconcile the release state

**Goal:** Confirm the whole release state is provable — the active release matches
approved, no candidate traffic reached production, and the result reproduces.

```bash
curl -s http://localhost:8000/lifecycle/prompts/reconcile | python3 scripts/fmt.py --type lc-reconcile \
  --title "Reconcile the release state" \
  --why "Active release matches approved, no candidate traffic leaked, and the result reproduces — the release state is provable"
```

**Expected output:** ★ `disposition: CONFIRMED`, ★ `active release: rel-2026.06`
(`approved rel-2026.06`), ★ `candidate in production: 0`, and ★ `reproducible:
true`.

**What the learner should notice:** This is the operator's sign-off, and it is one
word: `CONFIRMED`. It is confirmed because three independent facts all line up — the
active release equals the approved release, candidate traffic in production is zero,
and the result reproduces. Any one of those failing would flip the disposition to
`BLOCKED` and stop you from calling the release safe. That is the standard you want:
not "it looks fine," but "here are three checks that each had to pass, and they
did." Prompt versioning gives you reproducible experiments; safe rollback gives you
a way back; and this reconciliation gives you the evidence to prove, to a teammate
or an auditor, that production is exactly where it should be.

## Preflight check

```bash
bash module3/scripts/clip2_preflight_check.sh
```

Runs every step above, captures each command and its output, maps each step to
TO4 / EO4a, and writes a readable log to `module3/clip2_preflight_log.txt`. Expect
`PASS: 6  FAIL: 0`.

## Cleanup

```bash
./scripts/module3-demo-reset.sh
```

## Key files

- `prompts/` — the prompt repository: the immutable version files under
  `prompts/support_summary/` and the `prompts/registry.yaml` manifest
- `app/lifecycle/prompts.py` — reads the repository and builds the deterministic
  registry, receipts, isolation, rollback, reproducibility, and reconcile state
- `app/main.py` — the `/lifecycle/prompts/run`, `/lifecycle/prompts/registry`,
  `/lifecycle/prompts/receipts`, `/lifecycle/prompts/isolation`,
  `/lifecycle/prompts/rollback`, `/lifecycle/prompts/reproducibility`, and
  `/lifecycle/prompts/reconcile` endpoints
- `scripts/fmt.py` — the `lc-registry` / `lc-prompt-receipts` / `lc-isolation` /
  `lc-rollback` / `lc-reproducibility` / `lc-reconcile` views
