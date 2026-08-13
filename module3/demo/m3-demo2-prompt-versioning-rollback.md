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

**What you will see:** Four moves that turn prompts into managed releases — the
source-controlled `prompts/registry.yaml` where each version carries an owner, a
fixture, a model pin, an evaluation run, a release tag, and a lifecycle status, and
the receipts that stamp that release identity onto every request; a candidate change
deployed into an isolated lane that approved production traffic never touches; a
rollback that returns production to the approved release id, a fresh post-rollback
request whose receipt lands on that approved release, and a reproducibility proof
where the preserved prompt, fixture, and model regenerate the exact same result hash;
and the reconciliation that shows the release state is provable, not hoped for.

**What you walk away with:** Prompt version control that enables reproducible
experiments and safe rollback (EO4a) — the foundation of managing the operational
lifecycle of prompts and models (TO4).

## Learning objectives covered

| Step | LO sub-element | What proves it |
|------|----------------|----------------|
| 1 | EO4a | The source-controlled `prompts/registry.yaml` versions prompts like code — owner, fixture, model pin, eval run, release, status — and every request receipt links a prompt version, model version, and evaluation run id |
| 2 | EO4a | A candidate change is isolated so approved production traffic never reaches it |
| 3 | EO4a | A rollback returns production to the approved release id, a fresh post-rollback request's receipt lands on that approved release, and the preserved prompt, fixture, and model reproduce the exact result hash |
| 4 | TO4, EO4a | The release state reconciles to a provable, approved production state |

## What this demo proves — and each step is unique

| Step | Command | What it teaches (nothing repeats) |
|------|---------|-----------------------------------|
| 1 | `prompts/registry.yaml` + `/registry` + `/receipts` | The registry is a source-controlled file; every version is a release with metadata, and every request carries that release identity |
| 2 | `/lifecycle/prompts/isolation` | A candidate change reaches zero customers |
| 3 | `/lifecycle/prompts/rollback` + `/post-rollback-receipt` + `/reproducibility` | Rollback returns to a retained release, fresh traffic lands on it, and it reproduces the exact result |
| 4 | `/lifecycle/prompts/reconcile` | The production release state is provable |

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

### Step 1: Inspect the source-controlled registry and link receipts to releases

**Goal:** Show the prompt repository is *source-controlled* — read the real
`prompts/registry.yaml` manifest so each version's owner, fixture, model pin,
evaluation run, release tag, and status are visible as versioned files in the repo —
then read that same registry through the service and confirm every request receipt
stamps the full release identity, so any answer traces back to the exact prompt,
model, and evaluation behind it.

```bash
cat prompts/registry.yaml                      # the source-controlled manifest, tracked in the repo
curl -s -X POST http://localhost:8000/lifecycle/prompts/run >/dev/null
curl -s http://localhost:8000/lifecycle/prompts/registry | python3 scripts/fmt.py --type lc-registry \
  --title "Inspect the prompt version registry" \
  --why "Prompts versioned like code — owner, fixture, model pin, eval run, release tag, and status"
curl -s http://localhost:8000/lifecycle/prompts/receipts | python3 scripts/fmt.py --type lc-prompt-receipts \
  --title "Link prompt version, model, and eval run to receipts" \
  --why "Every receipt carries the release identity — prompt version, model version, evaluation run, release tag, and result hash"
```

**Expected output:** first the **source file** `prompts/registry.yaml` — the raw,
version-controlled manifest: `prompt_id: support_summary`, `approved_release:
rel-2026.06`, and three `versions` blocks, each carrying `owner`, `fixture`,
`model_version`, `eval_run_id`, `release_tag`, and `status`
(`superseded` / `approved` / `candidate`). Then the same registry read through the
service — ★ `prompt id: support_summary`, ★ `approved release: rel-2026.06`, and three
versions — `v1.0.0` (`superseded`), `v2.0.0` (`approved`, marked `← approved`), and
`v3.0.0-rc1` (`candidate`) — each with its model version, eval run id, release tag,
and a `result hash`. Then the receipts — ★ `approved version: v2.0.0` (`release
rel-2026.06`) and six receipts, each on `v2.0.0` with model `balanced-std@2026-06`,
eval run `ev-1042`, release `rel-2026.06`, and the same `result hash`.

**What the learner should notice:** This is the whole mindset shift, and it starts in
the repo: `prompts/registry.yaml` is a real **source-controlled** file — the versions
are immutable files under `prompts/`, tracked in git like code, and the manifest
records the metadata that makes an experiment reproducible. A prompt is a *release*,
not a string you paste. Every version has an owner who is
accountable, a fixture it was tested against, the exact model it was pinned to, the
evaluation run that graded it, and a release tag you can name in an incident. One
version — `v2.0.0` — is marked approved, and that single flag is the source of truth
for what production runs; the candidate, `v3.0.0-rc1`, exists but is explicitly not
approved. The receipts are why that registry matters in practice: every request
carries the release identity, so you can take any single answer and say exactly which
prompt version, model version, and evaluation run produced it. Notice all six
receipts share one result hash — that is not coincidence, it is determinism: the same
prompt, fixture, and model produce the same result identity every time, and that
property is what makes the next three steps possible. Without a stamped release
identity on every request, an audit is archaeology; with it, an audit is a database
query.

### Step 2: Deploy the prompt change to an isolated lane

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

### Step 3: Roll back to the approved release and prove it reproduces

**Goal:** Roll the candidate back so production returns to the approved release id —
targeting a version that was retained, not reconstructed — then send one fresh request
and show its receipt lands on the approved release (proving the rollback took effect
for live traffic, not just the stored pointer), and finally replay the approved
version with its preserved prompt, fixture, and model and confirm the result hash
matches — proving the rollback is reproducible, not approximate.

```bash
curl -s http://localhost:8000/lifecycle/prompts/rollback | python3 scripts/fmt.py --type lc-rollback \
  --title "Roll back production to the approved release" \
  --why "The rollback targets a retained, immutable release id — production returns to the approved version with zero candidate traffic"
curl -s http://localhost:8000/lifecycle/prompts/post-rollback-receipt | python3 scripts/fmt.py --type lc-post-rollback-receipt \
  --title "Send a fresh request after the rollback" \
  --why "A new request after the rollback gets a receipt on the approved release — the rollback took effect for live traffic, not just state"
curl -s http://localhost:8000/lifecycle/prompts/reproducibility | python3 scripts/fmt.py --type lc-reproducibility \
  --title "Prove the rollback is reproducible" \
  --why "Preserved prompt, fixture, and model reproduce the same result hash — reproducible, not merely re-run"
```

**Expected output:** first the rollback — ★ `from: v3.0.0-rc1`, ★ `to: v2.0.0
(rel-2026.06)`, ★ `active release after: rel-2026.06`, ★ `candidate in production
after: 0`, with the retained versions listed. Then the fresh post-rollback receipt —
★ `fresh request: req-pv-1007` (`sent after rollback`), on `v2.0.0` with model
`balanced-std@2026-06`, eval `ev-1042`, release `rel-2026.06`, and ★ `on approved
release: true`. Then the reproducibility proof — ★ `version: v2.0.0`, ★ `recorded
result hash` and ★ `replayed result hash` — identical — and ★ `reproducible: true`,
with the preserved inputs listed (`prompt_text`, `fixture`, `model_version`,
`result_hash`).

**What the learner should notice:** Watch what rollback actually means here. It is
not "retype the old prompt and hope" — it is a pointer move back to a release id that
still exists, byte for byte, in the registry. The candidate is withdrawn but
retained, so nothing is lost and the history stays intact; the active release returns
to `rel-2026.06` and candidate traffic in production is zero. But state alone is not
proof — so a fresh request goes out *after* the rollback, and its receipt
(`req-pv-1007`) lands on the approved release `rel-2026.06`, showing the rollback took
effect for live traffic, not just a stored pointer. Then the last part separates a
real rollback from a superstitious one: anyone can re-run an old prompt,
but the question is whether you get the *same thing back*. Here the recorded hash and
the replayed hash are identical and `reproducible` is `true`, and that works only
because the release preserved everything that determines the output — prompt text,
fixture, and model version. This is the payoff of versioning prompts like code: the
same `git revert` safety you expect from application code now applies to the prompt
that steers your model, and the rollback target is a known, immutable artifact that
regenerates the exact same result.

### Step 4: Reconcile the release state

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
bash module3/scripts/m3-demo2-prompt-versioning-rollback.preflight.sh
```

Runs every step above, captures each command and its output, maps each step to
TO4 / EO4a, and writes a readable log to `preflight-logs/m3-demo2-prompt-versioning-rollback.log`. Expect
`PASS: 4  FAIL: 0`.

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
  `/lifecycle/prompts/rollback`, `/lifecycle/prompts/post-rollback-receipt`,
  `/lifecycle/prompts/reproducibility`, and `/lifecycle/prompts/reconcile` endpoints
- `scripts/fmt.py` — the `lc-registry` / `lc-prompt-receipts` /
  `lc-post-rollback-receipt` / `lc-isolation` / `lc-rollback` /
  `lc-reproducibility` / `lc-reconcile` views
