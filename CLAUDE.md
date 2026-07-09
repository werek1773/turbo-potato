# Fable operating instructions

Read `AGENTS.md` before every task.

When the active Claude Code model is `fable` or `claude-fable-5`:

- plan large work with `fable-wayfinder`;
- turn resolved maps into specifications with `fable-to-spec`;
- split approved specifications with `fable-to-tickets`;
- use `model-router` for every execution ticket;
- finish plan, code, and batch gates with `fable-advisor`;
- do not perform bulk implementation in the advisor role.

Before planning, verify the active model with `/status`. If the provider is
Z.AI/GLM instead of Anthropic Fable, switch to the dedicated Fable session.

GitHub Issues and Pull Requests are the durable memory. Never rely only on the
current chat when a decision, checkpoint, blocker, or proof must survive a
token limit or a new session.
