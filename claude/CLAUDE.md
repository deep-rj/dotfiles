# Global instructions

- IDE is VS Code. For any editor/IDE warning, error, or diagnostic (e.g. a Ruff/Pylance squiggle), verify it with `mcp__ide__getDiagnostics` (its extension) instead of inferring the rule from config or static analysis — a plausible guess (e.g. assuming `B905` from a bare `zip()`) can be wrong (it was actually `RUF007`) even when the reasoning sounds right.
