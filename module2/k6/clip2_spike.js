// Module 2 · Clip 2 — controlled admission spike for the local GenAI service.
//
// Fires 20 requests concurrently at POST /load/submit and classifies each by the
// service's admission decision. Because the service admits atomically, the counts
// are deterministic under real concurrency: 6 accepted, 10 delayed, 4 rejected,
// with zero 500s and zero connection failures.
//
//   API_BASE=http://localhost:8000 k6 run --quiet module2/k6/clip2_spike.js
//
// handleSummary prints a compact JSON summary on stdout for scripts/fmt.py.
import http from 'k6/http';
import { Counter } from 'k6/metrics';

const accepted = new Counter('accepted');
const delayed = new Counter('delayed');
const rejected = new Counter('rejected');
const http500 = new Counter('http_500');
const failed = new Counter('failed');

const BASE = __ENV.API_BASE || 'http://localhost:8000';
const SUBMITTED = 20;

export const options = {
  scenarios: {
    spike: { executor: 'shared-iterations', vus: 10, iterations: SUBMITTED, maxDuration: '30s' },
  },
};

export default function () {
  const res = http.post(
    `${BASE}/load/submit`,
    JSON.stringify({ model: 'balanced-std' }),
    { headers: { 'Content-Type': 'application/json' } },
  );
  if (res.status === 0) { failed.add(1); return; }
  if (res.status >= 500) { http500.add(1); return; }
  if (res.status === 429) { rejected.add(1); return; }
  let disp = '';
  try { disp = res.json('disposition'); } catch (e) { disp = ''; }
  if (disp === 'accepted') accepted.add(1);
  else if (disp === 'delayed') delayed.add(1);
}

export function handleSummary(data) {
  const c = (n) => (data.metrics[n] && data.metrics[n].values.count) || 0;
  const summary = {
    submitted: SUBMITTED,
    accepted: c('accepted'),
    delayed: c('delayed'),
    rejected: c('rejected'),
    http_200: c('accepted') + c('delayed'),
    http_429: c('rejected'),
    http_500: c('http_500'),
    failed: c('failed'),
  };
  // Write a clean JSON file so the demo can render it without k6's own banner.
  return {
    stdout: JSON.stringify(summary) + '\n',
    'module2/k6/last_summary.json': JSON.stringify(summary),
  };
}
