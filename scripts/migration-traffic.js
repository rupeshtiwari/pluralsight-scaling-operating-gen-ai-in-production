// Module 3, Clip 6, Step 1 — send exactly 12 requests through the migrated path.
//
// Each POST /v1/completions targets the deprecated model; the replacement adapter
// routes it to the replacement and records a migration request. Run this AFTER
// POST /admin/deprecate, then read GET /receipts/migration for the aggregated
// compatibility receipt.
//
//   k6 run --quiet scripts/migration-traffic.js
//
// Host k6 (brew install k6) or the compose fallback:
//   docker compose run --rm k6 run --quiet scripts/migration-traffic.js
import http from 'k6/http';
import { check } from 'k6';

export const options = {
  scenarios: {
    migration: { executor: 'shared-iterations', vus: 1, iterations: 12, maxDuration: '30s' },
  },
};

const API = __ENV.API_BASE || 'http://localhost:8000';

export default function () {
  const res = http.post(
    `${API}/v1/completions`,
    JSON.stringify({ model: 'balanced-std@2026-04', prompt: 'summarize this support ticket' }),
    { headers: { 'Content-Type': 'application/json' } },
  );
  check(res, { 'routed to the replacement adapter': (r) => r.json('migrated') === true });
}
