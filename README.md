# rust-ts-harness

Code-free Linux + Rust + TypeScript agentic harness that wraps an inner project repository (`app/` by default) while keeping all agentic instructions, skills, and internal engineering docs in the outer wrapper.

## Outer Harness Structure

- `AGENTS.md`: Workspace rules, lint/anti-suppression policy, worktree & CPU-lock rules, and optional Project-Defined Review Axis.
- `.agents/`: Portable workflow skills (`subagent-plan-execute-review`, `iterative-plan-review`, `iterative-code-review`, `ideate-plan-execute-review`, `workspace-*`) and subagent specs.
- `docs/internal/`: Templates for `invariants.md`, `roadmap/`, `plans/`, and `evidence/`.
- `scripts/`: `init.sh`, `harness.env`, `with-cpu-lock.sh`, `check-boundary.sh`, `run-test.sh`, `run-pre-push.sh`, `run-bench.sh`, `run-e2e.sh`, `run-pr.sh`.
- `templates/inner-project/`: Starter Rust workspace (`crates/core`, `crates/server`) + TypeScript web shell (`web/`), materialized into `app/` by `init.sh` (and removed unless `--keep-templates` is passed).

## Quick Start

1. Clone this harness into a new project directory:
   ```bash
   git clone https://github.com/gheffern/rust-ts-harness.git ~/Projects/my-app
   cd ~/Projects/my-app
   ```
2. Bootstrap with a fresh Rust + TS inner repository (`app/`):
   ```bash
   ./scripts/init.sh --name my-app
   ```
   Or attach an existing repository (keeping it completely free of agentic files):
   ```bash
   ./scripts/init.sh --name my-app --inner-repo git@github.com:org/existing-repo.git --inner-dir app
   ```
3. Verify the full deterministic gate:
   ```bash
   ./scripts/run-pre-push.sh --all
   ```
