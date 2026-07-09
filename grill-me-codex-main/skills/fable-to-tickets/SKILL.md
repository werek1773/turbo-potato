---
name: fable-to-tickets
description: Use Fable 5 to split an approved specification into small GitHub execution tickets and route each ticket to GPT 5.6 SOL or GLM 5.2 through the model-router skill. Trigger after the specification passes plan review.
---

# Fable To Tickets

Create one-session vertical slices and assign the cheapest model that can safely complete each one.

## Gates

- The specification exists and fable-advisor returned APPROVED.
- Product decisions are closed.
- Every ticket has observable acceptance criteria and proof.

## Process

1. Read the full specification, review, standards, and current code structure.
2. Draft narrow, independently verifiable vertical slices.
3. Put wide mechanical refactors into expand, migrate, and contract phases.
4. Define blocking edges and the frontier.
5. Run model-router for every ticket. Record:
   - selected profile;
   - complexity and impact;
   - why the cheaper profile is or is not safe;
   - escalation conditions.
6. Create issues in dependency order with Parent spec, What to build, Acceptance criteria, Proof, Blocked by, Assigned profile, and Escalate when.
7. Add issues to the parent specification checklist.
8. Stop after publishing; do not implement.

Use GLM for repetitive low-risk work only. Use GPT for complex coding, ambiguity, cross-module reasoning, or high-impact changes.
