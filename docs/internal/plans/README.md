# Implementation Plans (`docs/internal/plans/`)

Store approved Invariant-First architecture plans here as `YYYY-MM-DD-<slug>.md`.

## Invariant-First Plan Template

Plans must specify **invariants, boundaries, failure domains, and component responsibilities** — **no code snippets or pseudo-code**.

```markdown
# Plan: <Title>

* **Roadmap Item(s)**: `<RM-... | N/A>`
* **Backwards Compatible**: `<true | false>`
* **Execution Mode**: `<main_thread | subagent>`

## 1. Non-Goals
- Explicit exclusions so reviewers never expand scope.

## 2. System & Resource Invariants
- State & ADT invariants (expressive enums/structs, zero primitive obsession).
- CPU / Memory / Disk / Network bounds.

## 3. Failure Domains & Recovery
- Behavior on invalid input, partial writes, cancellations, and error propagation.

## 4. Inner/Outer Boundary & Surface Parity
- Impact on inner submodule vs. outer workspace (`INV-BOUNDARY-*`) and API/CLI/Web surfaces.

## 5. Domain-Specific Invariants (If Applicable)
- Any project-defined `INV-DOMAIN-*` rules from `AGENTS.md` / `docs/internal/invariants.md`.

## 6. Component Responsibilities & Scoped Files
- Quantified invariants and module/file ownership scope.
```
