# Module 3 — Demo: Prove Prompt Versioning and Reproducible Rollback

> **Status: planned.** Scaffolded from the course outline; not yet built.

## What This Demo Will Prove

Prompts are versioned like code: each request receipt links a prompt version,
model version, and evaluation run id. A prompt change is isolated from approved
production traffic, and a rollback returns receipts to the approved release id —
reproducibly, because prompt, fixture, model, and result metadata are preserved.

## Learning Objectives Covered

| LO | Description |
|----|-------------|
| TO4 | Apply LLMOps practices to manage the operational lifecycle of prompts and models |
| EO4a | Prompt version control enabling reproducible experiments and safe rollback |

## Planned Steps

1. Inspect the GitHub prompt repository with version ids, metadata, owners, fixtures, and release tags.
2. Link prompt version, model version, and evaluation run id to request receipts.
3. Run a prompt change and show how the new version is isolated from approved production traffic.
4. Trigger rollback to the prior prompt version and prove receipts return to the approved release id.
5. Validate rollback reproducibility because prompt, fixture, model, and result metadata are preserved.

## Next

Validate model updates against quality baselines.
