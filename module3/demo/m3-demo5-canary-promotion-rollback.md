# Module 3 — Demo: Prove canary promotion, hold, and rollback decisions

## Why this matters

**The problem:** A candidate that passed every offline baseline can still fail in
production, because real traffic is messier than any fixture — odder prompts, longer
tails, edge cases your evaluation never imagined. So the last question before a full
rollout is the scariest one: does this release survive contact with real users? Flip
it to a hundred percent and find out, and a bad release takes down everyone. The
answer is a canary: expose a small, bounded slice of real traffic to the new release,
watch it against hard criteria, and promote only if it earns it — otherwise roll back
before most users ever saw it. The discipline is in the word *bounded*: if you cannot
prove the blast radius stayed small, you were not running a canary, you were running a
gamble with extra steps. How do you test a release on real traffic while guaranteeing
a bad one can harm no more than a fraction of it?

**What you will see:** Four moves that turn a risky rollout into a bounded, reversible
experiment — the canary start that shifts exactly ten percent of eligible traffic and
proves the blast radius, paired with the watch that tracks five live signals against
the approved release; the promotion criteria that demand every signal pass AND the
receipt trail prove exposure stayed bounded; the promote decision that ramps a healthy
canary in stages, paired with the hold-and-rollback that pulls a degraded canary and
returns production to the approved release; and the reconciliation that proves
production landed safely with the blast radius capped the entire time.

**What you walk away with:** A canary deployment with a controlled blast radius and
defined promotion criteria (EO4c) — the release control that lets you test on real
traffic without betting production on the result.

## Learning objectives covered

| Step | LO sub-element | What proves it |
|------|----------------|----------------|
| 1 | EO4c | The canary shifts only 10% of eligible traffic — the blast radius is bounded — and is watched on quality, latency, cost, error rate, and contract compliance against the approved release |
| 2 | EO4c | Promotion needs every signal within criteria AND a receipt trail proving bounded exposure |
| 3 | EO4c | A healthy canary is promoted on a staged, watched ramp, and a breached signal holds and rolls back the canary to the approved release |
| 4 | EO4c | Production provably returns to the approved release with the blast radius capped |

## What this demo proves — and each step is unique

| Step | Command | What it teaches (nothing repeats) |
|------|---------|-----------------------------------|
| 1 | `/lifecycle/canary/start` + `/lifecycle/canary/watch` | Ten percent is a cap, and it is provable; the five signals a canary lives or dies by |
| 2 | `/lifecycle/canary/criteria` + `/lifecycle/canary/exposure` | Promotion needs both criteria AND receipt-proven bounded exposure |
| 3 | `/lifecycle/canary/promote` + `/lifecycle/canary/rollback` | Earning promotion buys a ramp, not a flip; a breach rolls back before most users notice |
| 4 | `/lifecycle/canary/reconcile` | The safe landing is provable, not assumed |

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

The canary decision is deterministic — the same traffic split, signals, and criteria
reproduce the same promote and rollback outcomes every time. Reset before you start:

```bash
./scripts/module3-demo-reset.sh
```

## Demo steps

### Step 1: Start the canary and watch its signals

**Goal:** Shift ten percent of eligible traffic to the candidate release and confirm
the blast radius is bounded to that slice, then watch the five signals — quality,
latency, cost, error rate, and contract compliance — on the canary slice, side by side
with the approved release.

```bash
curl -s -X POST http://localhost:8000/lifecycle/canary/run >/dev/null
curl -s http://localhost:8000/lifecycle/canary/start | python3 scripts/fmt.py --type canary-start \
  --title "Start the canary" \
  --why "Ten percent of eligible traffic shifts to the candidate — the blast radius is bounded to that slice"
curl -s http://localhost:8000/lifecycle/canary/watch | python3 scripts/fmt.py --type canary-watch \
  --title "Watch the canary signals" \
  --why "Quality, latency, cost, error rate, and contract compliance on the canary slice, against the approved release"
```

**Expected output:** first the start — ★ `canary: 10% of 50 eligible`, then the split —
★ `production: 45 requests` on the approved release, ★ `canary: 5 requests` on the
candidate — then the **release identity**, proving the canary is a *prompt + model
combination*: ★ `prompt: support_summary v2.0.0 → support_summary v3.0.0-rc1`, ★
`model: balanced-std@2026-06 → balanced-std@2026-07`, ★ `release: rel-2026.06 →
rel-2026.07-rc1` — and ★ `blast radius bounded: true`. Then the watch — ★ `canary:
rel-2026.07-rc1` (vs approved `rel-2026.06`), labelled **Live canary signals**, then
five signals with the canary value beside the approved value — quality `0.91` vs
`0.91`, latency `835ms` vs `740ms`, cost `$0.34` vs `$0.30`, error `0.7%` vs `0.4%`,
contract `99.4%` vs `99.6%`.

**What the learner should notice:** This candidate already cleared its offline
baseline; live traffic now tests whether that decision still holds under production
conditions. The whole safety of a canary is in one number, and
here it is `5`. Ten percent of the eligible traffic — five of fifty requests — goes to
the candidate; the other forty-five stay on the approved release. That split is the
contract: no matter how badly the candidate behaves, it is structurally incapable of
touching more than five requests. `blast radius bounded: true` is not a comment, it is
the property you must be able to assert before you expose real users to anything new.
A canary without a bounded blast radius is just an outage waiting for a trigger. With
the slice bounded, the watch is deliberately just watching — not judging. You are
seeing the candidate's live behavior next to the production baseline, and the honest
read is that live is a little messier than the fixtures were: the canary is a touch
softer than the approved release on latency, cost, error rate, and contract, and only
flat on quality — every signal still inside its threshold, but nothing is tidier than
production. That is exactly why you never eyeball a canary. Small movements
in five directions are impossible to adjudicate by feel. That is what the next step is
for: turning these observations into a single, defensible promote-or-not decision
against thresholds you set in advance.

### Step 2: Check the promotion criteria

**Goal:** Evaluate the canary's signals against the promotion criteria and confirm the
receipt trail proves the exposure stayed bounded.

```bash
curl -s http://localhost:8000/lifecycle/canary/criteria | python3 scripts/fmt.py --type canary-criteria \
  --title "Check the promotion criteria" \
  --why "Every signal within threshold AND a receipt trail proving exposure stayed inside the blast radius"
curl -s http://localhost:8000/lifecycle/canary/exposure | python3 scripts/fmt.py --type canary-exposure \
  --title "Prove bounded exposure from the receipt trail" \
  --why "Count the receipts by lane — the 10% exposure is measured from the receipt trail, not asserted"
```

**Expected output:** first the criteria — five signals all `pass` against their
objectives, then ★ `exposure: 5 ≤ 5 allowed` and ★ `eligible to promote: true`. Then
the **receipt-derived proof** of that exposure — ★ `receipt trail: 50 eligible
requests`, the two lanes ★ `approved 45 receipts (req-cn-1001 … req-cn-1045)` and ★
`canary 5 receipts (req-cn-1046 … req-cn-1050)`, ★ `canary exposure: 5 / 50 = 10%`, ★
`exposure limit: 10%`, and ★ `receipt check: PASS`.

**What the learner should notice:** Promotion is an `AND`, and that is the entire
lesson of this step. Every signal has to clear its threshold — and here all five do —
but that alone is not enough. The second condition is the one teams forget: the receipt
trail has to *prove* the exposure never exceeded the blast radius — and here you do not
take that on faith. The receipt trail is counted on screen: fifty eligible requests,
forty-five receipts on the approved lane and five on the canary lane, so the measured
exposure is `5 / 50 = 10%`, exactly at the limit, and the `receipt check` reads `PASS`.
That is the difference between claiming bounded exposure and demonstrating it — the
number comes from the receipts, not from a promise. If the signals looked great but the
receipts showed exposure had crept to thirty percent, promotion would still be off the
table, because a good result from an unbounded experiment tells you nothing about a
bounded rollout. Criteria met and exposure provably bounded — both true — is the only
state that earns a promotion.

### Step 3: Promote the healthy canary and roll back the degraded one

**Goal:** Promote the healthy canary and confirm it advances on a staged ramp rather
than an instant flip to a hundred percent, then see what happens when a canary breaches
— the decision flips to rollback and production returns to the approved release, with
the damage capped at the canary slice.

```bash
curl -s http://localhost:8000/lifecycle/canary/promote | python3 scripts/fmt.py --type canary-promote \
  --title "Promote the healthy canary" \
  --why "Criteria met and exposure bounded — promote on a staged ramp, each stage still watched"
curl -s http://localhost:8000/lifecycle/canary/rollback | python3 scripts/fmt.py --type canary-rollback \
  --title "Hold and roll back the degraded canary" \
  --why "A breached signal rolls the canary back — production returns to the approved release, blast radius capped at the canary slice"
```

**Expected output:** first the promote — ★ `decision: PROMOTE`, ★ `criteria met: true`,
★ `exposure bounded: true`, ★ `ramp plan: 10% → 25% → 50% → 100%`, and the release path
`rel-2026.06 → rel-2026.07-rc1`. Then the rollback — ★ `decision: ROLLBACK`, then the
degraded signals — quality `0.84` breach, latency `1300ms` breach, cost `$0.33` pass,
error `3.2%` breach, contract `95.0%` breach — ★ `blast radius: 5 requests (10%)`, ★
`active after rollback: rel-2026.06`, and ★ `canary exposure after: 0%`.

**What the learner should notice:** Even a canary that earns promotion does not get
flipped straight to a hundred percent, and the ramp plan is why. Promotion buys the
candidate a *staged* increase — ten to twenty-five to fifty to a hundred — and every
stage is still watched against the same criteria. This matters because ten percent
might look healthy while a problem that only shows up under higher load is still hiding.
A staged ramp keeps the blast radius bounded at each step of the way up, so if the
candidate stumbles at fifty percent, you still catch it before it reaches everyone.
Promotion is a gradient, not a switch. Now watch the other outcome — the canary doing
its job, and it is worth sitting with. A different candidate — degraded — breaches four
of five signals, and the decision is immediate: `ROLLBACK`. Look at the number that
makes this a good day instead of a bad one: `blast radius: 5 requests`. Only the ten
percent canary slice ever saw the regression; the ninety percent on the approved
release never noticed. Production returns to `rel-2026.06` and canary exposure drops to
zero. Without the canary, this degraded release goes to a hundred percent of users; with
it, it touched five requests and was gone. That contrast is the entire value
proposition of canarying.

### Step 4: Reconcile after rollback

**Goal:** Confirm production is provably back on the approved release, with zero canary
exposure and a blast radius that stayed bounded the whole time.

```bash
curl -s http://localhost:8000/lifecycle/canary/reconcile | python3 scripts/fmt.py --type canary-reconcile \
  --title "Reconcile after rollback" \
  --why "Production is back on the approved release, canary exposure is zero, and the blast radius never exceeded its cap"
```

**Expected output:** ★ `disposition: CONFIRMED`, then the **active release after
rollback** broken out by axis so the approved prompt *and* model are both explicit —
★ `prompt: support_summary v2.0.0`, ★ `model: balanced-std@2026-06`, ★ `release:
rel-2026.06` (each marked `approved`) — then ★ `canary exposure: 0%`, and ★ `blast
radius: ≤ 10% throughout`.

**What the learner should notice:** The sign-off is `CONFIRMED`, and it rests on three
facts you can prove rather than feel. The active release matches the approved release —
and here that is spelled out on both axes: the prompt is back to `support_summary
v2.0.0` and the model to `balanced-std@2026-06`, not just an opaque release tag. Canary
exposure is zero, so no candidate traffic is lingering in production. And the blast
radius stayed at or below ten percent for the entire experiment, breach included. That
last point is the one auditors care about: you did not just recover, you can
*demonstrate* that the exposure was bounded from start to finish. A canary you can
reconcile like this turns "we tried a release and pulled it" into "we ran a bounded
experiment, it failed its criteria, and here is the proof that production was never at
risk." That is release management you can defend.

Worth saying out loud in narration: "rollback" here means aborting a *live rollout* and
proving the blast radius stayed bounded — a different guarantee from reverting a stored
*version* to a reproducible result. This canary rollback returns production to the
approved release with exposure that never exceeded ten percent. Same word, two
mechanisms, two proofs.

## Preflight check

```bash
bash module3/scripts/m3-demo5-canary-promotion-rollback.preflight.sh
```

Runs every step above, captures each command and its output, maps each step to EO4c,
and writes a readable log to `preflight-logs/m3-demo5-canary-promotion-rollback.log`. Expect `PASS: 4  FAIL:
0`.

## Cleanup

```bash
./scripts/module3-demo-reset.sh
```

## Key files

- `app/lifecycle/canary.py` — the deterministic canary: traffic split, live signals,
  promotion criteria, and the promote and rollback decisions
- `app/main.py` — the `/lifecycle/canary/run`, `/lifecycle/canary/start`,
  `/lifecycle/canary/watch`, `/lifecycle/canary/criteria`, `/lifecycle/canary/exposure`,
  `/lifecycle/canary/promote`, `/lifecycle/canary/rollback`, and
  `/lifecycle/canary/reconcile` endpoints
- `scripts/fmt.py` — the `canary-start` / `canary-watch` / `canary-criteria` /
  `canary-exposure` / `canary-promote` / `canary-rollback` / `canary-reconcile` views
