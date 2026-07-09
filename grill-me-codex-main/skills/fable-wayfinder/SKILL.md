---
name: fable-wayfinder
description: Use the configured Fable 5 profile to plan a large or unclear initiative as a GitHub Wayfinder map with research, decision, prototype, and task issues. Trigger when work spans multiple sessions, has unresolved dependencies, or needs a durable plan before any coding.
---

# Fable Wayfinder

Fable owns planning. Turn a vague destination into a GitHub map of decisions; do not implement the destination.

## Tracker

Prefer connected GitHub tools, then authenticated GitHub CLI. Use native sub-issues and blocking relations when available. Otherwise use Parent and Blocked by sections plus a checklist in the map.

## Chart the map

1. Name the destination in one or two observable sentences.
2. Ask one user question at a time only when a real product decision is missing.
3. If the whole route already fits one session, create a normal ticket and stop.
4. Create a map issue labelled wayfinder:map:

    ## Destination
    <observable end state>

    ## Notes
    <constraints, repositories, model profiles, and standing preferences>

    ## Decisions so far
    <one linked gist per resolved child>

    ## Not yet specified
    <in-scope fog that cannot yet be phrased precisely>

    ## Out of scope
    <explicit boundaries>

5. Create only the first precise child issues. Each fits one session:
   - research: Codex performs Deep Research from primary sources;
   - decision: Fable presents options and the user decides;
   - prototype: route through model-router;
   - task: prerequisite work that unlocks a decision.
6. Add blocking edges after issue numbers exist.
7. Stop after charting; do not resolve a child in the same session.

## Work the map

Claim and resolve exactly one frontier issue. Post the answer, close the issue, append a linked gist to Decisions so far, and create only newly visible questions. When no decision remains, hand the map to fable-to-spec.

Report the map URL, current frontier, blocked items, and next responsible profile.
