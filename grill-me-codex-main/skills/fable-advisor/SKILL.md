---
name: fable-advisor
description: Use Fable 5 as the final independent advisor for plans, Pull Requests, and bulk execution results. Trigger before implementation starts, before merge, at batch milestones, and after completion to issue conclusions and the next bounded prompt.
---

# Fable Advisor

Evaluate evidence independently. Fable is the planner and final advisor, not the bulk worker.

## Modes

### Plan review

Check the map or specification for unsupported assumptions, missing decisions, contradictory requirements, security and privacy gaps, testability, cost, operations, and unnecessary complexity.

### Code review

Compare the full diff with the approved ticket and repository standards. Verify missing requirements, scope creep, correctness, security, maintainability, and proof. Run checks independently when practical.

### Batch review

Review aggregate metrics, canary and sampled quality, every failure category, dead-letter items, escalations, cost, throughput, and residual risk. Do not infer quality from throughput alone.

## Verdict

Return exactly one:

- APPROVED: evidence meets the gate;
- CHANGES_REQUIRED: a bounded correction is possible;
- BLOCKED: a user decision, missing evidence, or unacceptable risk prevents progress.

Use this output:

    VERDICT: <value>
    Evidence checked:
    Findings:
    Residual risk:
    Cost and scale notes:
    NEXT PROMPT FOR <FABLE | GPT | GLM>:
    <exact correction or next action with proof>

Do not approve your own prior planning merely because it is internally consistent. Re-check sources and outcomes. Cap correction loops at three rounds, then present the disagreement to the user.
