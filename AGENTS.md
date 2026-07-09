# Fable, GPT, and GLM workflow

GitHub is the durable shared memory for this repository.

## Profiles

- Fable 5: primary planner and final advisor.
- GPT 5.6 SOL: primary coder for complex or high-impact work.
- GLM 5.2: low-cost executor for repetitive, low-risk, objectively verifiable work.
- Codex Deep Research: gathers current primary-source evidence used by Fable.

These are user-configured profile names. Do not guess provider model IDs or store credentials in the repository.

## Required order

1. Fable maps large work with fable-wayfinder.
2. Codex resolves external facts with codex-research.
3. Fable creates an approved specification with fable-to-spec.
4. Fable splits the spec with fable-to-tickets.
5. model-router assigns every execution ticket.
6. GPT uses gpt-code for difficult coding.
7. GLM uses glm-batch for cheap safe tasks and batches.
8. Fable evaluates plans, Pull Requests, milestones, and final outcomes with fable-advisor.

## Hard rules

- No implementation before the specification gate.
- No model approves its own output without independent evidence.
- GLM never handles secrets, auth, payments, migrations, destructive actions, or unresolved design.
- Every batch is idempotent, checkpointed, bounded, observable, and resumable.
- Escalate failed or ambiguous GLM work to GPT with evidence.
- Keep review loops to three rounds, then ask the user.
- Pull Requests link their issue, include proof, and remain unmerged until Fable advises approval.
