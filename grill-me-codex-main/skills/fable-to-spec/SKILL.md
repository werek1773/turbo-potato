---
name: fable-to-spec
description: Use Fable 5 to synthesize a resolved Wayfinder map, research, and user decisions into an execution-ready GitHub specification. Trigger after planning questions are closed and before model routing or implementation tickets.
---

# Fable To Spec

Convert resolved decisions into one durable specification. Do not write product code.

## Process

1. Read the map, every linked resolution, Codex research, repository standards, and relevant ADRs.
2. If a material decision remains open, create or reopen a Wayfinder child and stop.
3. Create a GitHub specification containing:
   - source map and research;
   - problem and user-visible outcome;
   - numbered user stories;
   - functional and non-functional requirements;
   - implementation constraints and allowed seams;
   - test strategy and proof commands;
   - security, privacy, cost, and operational limits;
   - out of scope;
   - acceptance criteria.
4. State which facts are sourced, which are inferences, and which are user decisions.
5. Avoid brittle file paths and code snippets unless a prototype encodes a decision better than prose.
6. Run fable-advisor in plan-review mode. Do not create execution tickets until it returns APPROVED.

After three failed review rounds, mark BLOCKED and present the disagreement to the user.
