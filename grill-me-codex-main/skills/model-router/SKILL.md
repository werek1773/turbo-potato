---
name: model-router
description: Route planned work among Fable 5, GPT 5.6 SOL, and GLM 5.2 using risk, complexity, verification cost, and volume. Trigger when assigning GitHub tickets, designing bulk execution, controlling inference cost, or escalating a failed cheap-model task.
---

# Model Router

Choose the cheapest profile that can safely satisfy the ticket. Treat Fable 5, GPT 5.6 SOL, and GLM 5.2 as user-configured profile names; never invent provider model IDs or credentials.

## Routing table

### Fable 5

Use for planning, trade-offs, dependency maps, specification synthesis, ambiguous product decisions, and final advisory evaluation. Fable does not perform bulk implementation.

### GPT 5.6 SOL

Use for difficult coding: multi-file behavior, debugging without a clear cause, architecture-sensitive changes, security, auth, payments, concurrency, migrations, public APIs, non-trivial tests, or any task whose failure has meaningful impact.

### GLM 5.2

Use for high-volume, low-risk, mechanically checkable work: formatting, extraction, tagging, simple conversions, repetitive edits, fixture generation, deterministic classification, or isolated code changes with exact proof.

A GLM task must have all of these properties:

- no unresolved design decision;
- narrow and reversible scope;
- deterministic or strongly objective validation;
- no secrets, permissions, security boundary, migration, payment, or destructive operation;
- failure can be detected before output reaches production.

If any property is false, route to GPT.

## Bulk execution

For large batches, require:

1. stable task IDs and idempotent writes;
2. dry-run on a representative sample;
3. explicit concurrency and cost limits;
4. checkpointed batches instead of one unbounded run;
5. at most two automatic retries;
6. a dead-letter queue for failures;
7. schema validation on every result;
8. sampled quality review plus review of every failure;
9. metrics for attempted, passed, retried, escalated, and rejected items;
10. a pause switch and resumable state.

Start with a small canary. Increase volume only when the acceptance rate meets the specification.

## Escalation

Promote GLM work to GPT when validation fails twice, confidence is below the ticket threshold, output changes scope, the task crosses files or systems unexpectedly, or sampled error rate exceeds the limit. Send the original input, validation evidence, attempts, and exact failure reason; do not merely ask GPT to try again.

Fable reviews aggregate outcomes, anomalies, cost, and residual risk at milestones and at the end. It should not manually inspect every item in a million-task batch.
