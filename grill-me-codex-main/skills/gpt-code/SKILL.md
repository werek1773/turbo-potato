---
name: gpt-code
description: Use the configured GPT 5.6 SOL profile to implement complex, ambiguous, cross-module, or high-impact GitHub coding tickets with full proof and a Fable advisory handoff. Trigger when model-router selects GPT rather than GLM.
---

# GPT Code

Implement one approved ticket. GPT is the primary coder for work that requires strong reasoning.

## Gates

1. Read AGENTS.md, the ticket, parent specification, routing rationale, and repository standards.
2. Confirm blockers are closed and the tree is clean.
3. Work on agent/issue-<number>-<short-name>.
4. Stop as BLOCKED if implementation requires a new product decision.

## Implementation

1. Inspect the relevant system before editing.
2. Make the smallest faithful change.
3. Use test-first work at stable seams when practical.
4. Run focused checks while working and the ticket's full proof at the end.
5. Inspect the complete diff for scope creep, secrets, accidental files, regressions, and speculative abstractions.
6. Never merge your own Pull Request.

## Handoff

Open or update a Pull Request with the linked issue, changed files, proof output, deviations, and risks. Request fable-advisor in code-review mode.

For CHANGES_REQUIRED, apply the bounded prompt and re-run proof. After three unsuccessful cycles, stop and escalate to the user.
