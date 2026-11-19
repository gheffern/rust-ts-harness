# Agentic Assistant Directives & Workspace Rules

This outer repository is a code-free agentic harness (`AGENTS.md`, `.agents/`, `docs/internal/`, `scripts/`) configured via [`scripts/harness.env`](scripts/harness.env). All project code lives inside the inner submodule (`INNER_DIR` in `scripts/harness.env`, default `app/`).

## 1. Environment, Tooling & Multi-Agent CPU Lock
* **Mandatory CPU & Benchmark Lock (`scripts/with-cpu-lock.sh`)**: Always serialize heavy compilations, test suites, E2E audits, and Criterion benchmarks through `./scripts/with-cpu-lock.sh <build|test|bench|e2e> <command...>` (backed by Linux kernel `flock(2)`). Canonical scripts (`./scripts/run-test.sh`, `./scripts/run-pre-push.sh`, `./scripts/run-bench.sh`, `./scripts/run-e2e.sh`) acquire this lock automatically.
* **Host-First Execution (Optional Container)**: Scripts run natively on the host by default (automatically enabling `sccache` and `mold` when installed). Pass `--container` to execute inside `CONTAINER_IMAGE` (configured in `scripts/harness.env`, default `localhost/rust-ts-harness-toolchain:latest`, auto-built from [`docker/toolchain.Containerfile`](docker/toolchain.Containerfile) via `./scripts/build-toolchain.sh`).
* **Outer Harness vs. Inner Code Repository**:
  1. **Outer Harness (this repo)**: Contains `AGENTS.md`, `.agents/`, `docs/internal/`, and `scripts/` — **no project source code** (`INV-BOUNDARY-1`).
  2. **Inner Code Submodule (`INNER_DIR`, default `app/`)**: Contains the Rust + TypeScript project code (`Cargo.toml`, `crates/*`, `web/`) — **kept 100% free of agentic files and developer host paths** (`INV-BOUNDARY-2`).

## 2. Git, Submodule & Clean-Room Boundary
* **Commit Author Identity**: Read `GIT_AUTHOR_NAME` and `GIT_AUTHOR_EMAIL` from `scripts/harness.env` (defaulting to local `git config user.name` / `user.email`) and author commits consistently across both inner and outer repos.
* **No Unsanctioned External Remote Push**: NEVER execute `git push` to external remotes unless explicitly instructed by the user (or explicitly invoked via `./scripts/run-pr.sh --push` / `--pr`). Local bare upstreams configured in `INNER_LOCAL_UPSTREAM` are local infrastructure.
* **Submodule Synchronization Protocol**: When modifying code inside `INNER_DIR`:
  1. Commit changes inside `INNER_DIR` first.
  2. Push inner commits to `INNER_LOCAL_UPSTREAM` (if configured) so the gitlink SHA is reachable across worktrees.
  3. Stage and commit the updated submodule pointer in the outer harness repository (`./scripts/run-pr.sh --commit-gitlink` automates steps 2–3).
* **Clean-Room Boundary (`INV-BOUNDARY-1` & `INV-BOUNDARY-2`)**:
  - `INV-BOUNDARY-1`: Outer harness contains no project code outside `templates/` (removed after `init.sh`).
  - `INV-BOUNDARY-2`: `INNER_DIR` remains 100% free of `AGENTS.md`, `.agents/`, `harness.env`, `docs/internal/` references, or developer host paths (`/home/<user>/`). Verified deterministically via `./scripts/check-boundary.sh`.
* **Branch Isolation & NVMe Worktrees**: Create distinct feature branches (`feature/<name>`) for separate initiatives. **NEVER create git worktrees or set `CARGO_TARGET_DIR` under `/tmp` (`tmpfs` RAM disk)**. Always place worktrees under `.worktrees/<name>` on NVMe disk.

## 3. Architectural Hygiene & Strict Rust Lints
* **Single Responsibility & Cohesion**: Isolate domain logic, state mutations, and I/O behind clear interfaces. Avoid single-use indirection that obscures straightforward execution paths.
* **Opportunistic Refactoring (Boy Scout Principle)**: When touching a file or function, refactor adjacent smells scoped tightly to the touched area without altering unrelated public APIs.
* **Strict Rust Lints & Anti-Suppression Rule**:
  - Uphold workspace lints: `unsafe_code = "deny"`, `clippy::all`, `clippy::pedantic`, `clippy::perf`, `unwrap_used`, and `expect_used` warnings (`-D warnings` in pre-push).
  - **No Unjustified Clippy Relaxations**: On any newly added or modified production function/type, eliminate structural, complexity, and inlining Clippy lints (`clippy::too_many_lines`, `clippy::too_many_arguments`, `clippy::cognitive_complexity`, `clippy::type_complexity`, `clippy::large_enum_variant`, `clippy::struct_excessive_bools`, `clippy::fn_params_excessive_bools`, `clippy::inline_always`) by refactoring into cohesive domain parameter `struct`s, expressive `enum`s/ADTs, or focused helper functions. Suppressing via `#[expect(clippy::..., reason = "...")]` is permitted **only** on verified hot paths where `reason` documents a proven hardware/runtime performance gain; cold-path suppressions are forbidden. Numeric/pointer `cast_*` suppressions must document exact domain bounds proofs, and `unwrap_used` / `expect_used` are banned in production code (permitted in `#[cfg(test)]`, `tests/`, and `benches/`).
* **Verification Safety**: Always verify touched layers using `./scripts/run-test.sh` (`workspace-test`) during iteration and `./scripts/run-pre-push.sh` (`workspace-pre-push`) before finalizing work.

## 4. Internal Knowledge Base (`docs/internal/`)
* [`docs/internal/invariants.md`](docs/internal/invariants.md): Authoritative `INV-*` registry.
* [`docs/internal/roadmap/roadmap.md`](docs/internal/roadmap/roadmap.md) & [`completed-milestones.md`](docs/internal/roadmap/completed-milestones.md): Active milestones and completed archive.
* [`docs/internal/plans/`](docs/internal/plans/README.md): Invariant-First architecture plans.
* [`docs/internal/evidence/`](docs/internal/evidence/README.md): Empirical benchmark and telemetry receipts.

## 5. Project-Defined Review Axis (Optional Axis 4 / Axis 5)
> Projects with specialized invariants (e.g., scientific/mathematical fidelity, financial precision, zero-copy mmap/SIMD layouts, or strict protocol wire budgets) may declare them below. `iterative-plan-review` (Axis 4) and `iterative-code-review` (Axis 5) enforce these rules whenever non-empty; otherwise they evaluate only the universal axes.

* *(None configured yet — add `INV-DOMAIN-*` rules here or in `docs/internal/invariants.md` as your project matures.)*
