---
name: codex-research
description: Investigate a GitHub research ticket using current primary sources and record traceable findings for a Wayfinder map or specification. Use for Deep Research, changing technical facts, provider documentation, API behavior, standards, prices, limits, or decisions that need evidence before planning.
---

# Codex Research

Resolve one research question without modifying product code.

## Process

1. Read the research issue, its parent map, acceptance criteria, and blockers.
2. State the exact question and what evidence would answer it.
3. Search current primary sources: official documentation, specifications, source code, first-party APIs, or vendor announcements. Use secondary sources only to locate primary evidence.
4. Separate:
   - confirmed facts;
   - reasoned inferences;
   - unresolved uncertainty;
   - decisions that belong to the user.
5. Save durable findings under docs/research/<issue-number>-<short-name>.md when working in a repository. Include the access date and a link beside every material claim.
6. Post a concise GitHub resolution comment linking the research file. Close the issue only when its acceptance criteria are met.
7. Update the parent map through fable-wayfinder.

## Quality bar

- Prefer two independent primary sources for high-impact claims when possible.
- Verify any fact with a meaningful chance of having changed.
- Never invent a source, quote, benchmark, or product capability.
- Do not turn vendor marketing into a technical conclusion without evidence.
- Do not implement code, change architecture, or choose for the user.

End with: answer, confidence, remaining unknowns, and the next responsible role.
