# Provider adapter contract

The adapter contract is the single boundary between application code and any
model provider. Application code depends on **these fields only** — never on a
vendor's raw response shape. This is the reusable template referenced by
Module 1.

## Contract fields

| Field | Type | Meaning |
|-------|------|---------|
| `model` | string | Provider/model identity |
| `tier` | string | `low_cost` \| `balanced` \| `premium` |
| `latency_target_ms` | int | Latency profile target for the tier |
| `quota_mode` | string | `shared` \| `dedicated` \| `reserved` |
| `cost_per_1k_usd` | float | Cost estimate basis per 1,000 tokens |
| `quality_score` | float | 0.0–1.0 quality signal (condition-adjusted) |
| `status` | string | Live provider status derived from the active condition |
| `condition` | string | Active simulated condition |

## Model tiers (pinned)

| model | tier | latency_target_ms | quota_mode | cost_per_1k_usd | quality_score |
|-------|------|-------------------|------------|-----------------|---------------|
| econo-mini | low_cost | 400 | shared | 0.05 | 0.82 |
| balanced-std | balanced | 700 | dedicated | 0.30 | 0.90 |
| premium-max | premium | 1200 | reserved | 1.20 | 0.97 |

`balanced-std` is the baseline default.

## Simulated conditions

Every provider carries one active condition so scenarios are fully repeatable
with **zero external API calls**.

| condition | status shown | effect |
|-----------|--------------|--------|
| healthy | `healthy` | normal operation, within latency target |
| slow | `degraded_slow` | latency inflated beyond target (×3) |
| error | `error` | provider returns a hard error |
| quota | `quota_exceeded` | provider quota exhausted |
| quality | `quality_degraded` | quality score reduced below the acceptance bar |
| deprecation | `deprecated` | model version scheduled for sunset |

## Normalized receipt

Every routing decision is persisted to PostgreSQL in one provider-agnostic
shape, proving the application stays decoupled from provider response shapes:

```
receipts(
  request_id, created_at, selected_model, provider_tier, provider_status,
  route_reason, latency_target_ms, prompt_tokens, completion_tokens,
  total_tokens, cost_estimate_usd, quality_score, policy_name
)
```
