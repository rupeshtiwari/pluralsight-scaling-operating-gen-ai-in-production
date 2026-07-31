# Module 2 · Clip 1 — Introduction (presentation, ~3 min)

**Type:** presentation clip (no demo)
**Covers:** Module 2 framing — TO2 (resilience) and TO3 (observability). Sets up
Clips 2, 3, 5, and 6.
**Non-duplication note:** This clip references, but does NOT re-teach, the receipt
and reconciliation material from Module 1 Clip 6. The per-request receipt is named
in one sentence only. The correlation teaching (one request ID across the caller
response, the structured log, and the durable receipt) lives solely in Clip 2,
Step 5, and is not previewed here in mechanical detail.

---

## Narration

In Module 1, you built something that works. A dedicated AI service layer that
takes a request, weighs cost against latency and complexity, routes it to the right
model tier, and writes a durable receipt for every decision. On a calm day, that
system is enough.

Production is not a calm day.

On a real day, traffic arrives in bursts, not a steady trickle. A provider you
depend on slows to a crawl, or starts returning errors, or quietly hands back worse
answers than it did yesterday. Your model budget is finite, and one unbounded spike
can exhaust the quota that every other caller is sharing. None of that is a routing
problem. Module 1's router will happily keep sending requests into a provider that
is on fire.

Module 2 is about keeping the system standing when the day goes wrong, and being
able to see inside it when it does. It has two terminal objectives. The first is
resilience: absorbing spikes, refusing work you cannot serve, and failing over
automatically when a provider degrades. The second is observability: tracing a
request across every layer, logging what actually happened, sampling output
quality, and defining the alerts that tell you before your users do.

You will build both, hands on.

In the first demo, you will put the service under a real concurrent spike and watch
a rate-limited queue absorb it, admit exactly what the provider quota allows, and
fail fast on the rest with a clean, honest error. In the second, you will trip a
circuit breaker against a failing provider, watch traffic route to a healthy
alternative, and see retries back off instead of stampeding. In the third, you will
open a single request's trace across the application, the service, and the provider,
read its structured log and its metrics, and catch a quality regression from a
sample of live responses. And in the last demo, you will stand in front of a live
incident, four dimensions red at once, and use exactly this evidence to find the
cause and choose the operator action.

Everything you saw in Module 1 still holds. Every request still earns a receipt.
What changes here is that the system now expects things to go wrong, and gives you
the controls and the visibility to handle it on purpose. By the end of this module,
you will be able to take a GenAI integration that merely works and make it one you
would trust in production.

Let's get started.

---

*Word count: ~460 (about three minutes at presentation pace).*
