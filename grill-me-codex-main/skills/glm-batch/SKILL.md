---
name: glm-batch
description: Use GLM 5.2 for cheap, repetitive, low-risk, mechanically verifiable tickets or large batches. Trigger only after model-router marks work GLM-safe and defines validation, retry, checkpoint, and escalation rules.
---

# GLM Batch

Run this skill with GLM 5.2 inside VS Code. Execute the cheapest safe path. Never use GLM batch work to make product, architecture, security, or irreversible decisions.

## Single-ticket mode

1. Read the approved ticket, parent specification, routing rationale, and proof.
2. Confirm every GLM-safe condition in model-router remains true.
3. Make only the requested mechanical change.
4. Run deterministic validation.
5. Report output, proof, and any deviation. Escalate instead of improvising.

## Batch mode

1. Assign a stable ID to every item.
2. Validate inputs before dispatch.
3. Run a small canary and compare its error rate with the ticket threshold.
4. Process bounded checkpoint batches with the configured concurrency cap.
5. Make writes idempotent and resumable.
6. Validate every output against schema and business rules.
7. Retry a failed item at most twice.
8. Send persistent failures to the dead-letter queue with input, attempts, and reason.
9. Promote unexpected or ambiguous items to GPT through model-router.
10. Record counts, latency, estimated cost, validation failures, retries, escalations, and sampled review results.

Stop the batch automatically when error rate, cost, or latency crosses the specification limit. Never silently drop an item.

## Handoff

GPT may inspect difficult escalations. Fable receives milestone and final summaries and returns advisory conclusions.
