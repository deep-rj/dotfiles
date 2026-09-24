# Global instructions

- When `mcp__ide__getDiagnostics` is available (VS Code), verify any editor/IDE warning, error, or diagnostic (e.g. a Ruff/Pylance squiggle) with it instead of inferring the rule from config or static analysis — a plausible guess (e.g. assuming `B905` from a bare `zip()`) can be wrong (it was actually `RUF007`) even when the reasoning sounds right.

## Code comments

- Default to no comment. Add one only when the WHY is non-obvious: a hidden constraint, invariant, workaround, unit, or boundary. Never describe what the code does; rename or extract instead.
- Write comments as timeless facts about the code as it is now. Never narrate the change or session ("added", "fixed", "now", "per our discussion"), and never reference the current task, ticket, PR, or caller.
- Don't record how a decision was reached (test results, best-practice appeals, alternatives considered) in code. That belongs in the commit message or PR description, or an ADR for architectural choices. The comment states only the resulting constraint.
- Keep comments to one or two lines. No multi-paragraph blocks or docstrings that restate the signature.
- Don't leave "removed X" tombstones or commented-out code, and don't edit comments on code you didn't change.
