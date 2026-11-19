---
name: workspace-test
description: >-
  Execute scoped or changed-only tests inside the inner repository (`INNER_DIR`),
  covering Rust crates, optional wasm32-unknown-unknown crates, and TypeScript/Vite/Vitest web
  frontend. Serializes via scripts/with-cpu-lock.sh and defaults to host execution
  (--container optional). Use whenever developing, refactoring, or debugging code.
---

# Scoped Workspace Test Runner (`workspace-test`)

Executes targeted, changed-only, or full-suite tests serialized through `scripts/with-cpu-lock.sh` (running natively on host by default, or inside `CONTAINER_IMAGE` with `--container`).

> **Worktree Guardrail**: Always place git worktrees under `.worktrees/<name>` on NVMe disk. `scripts/run-test.sh` rejects `/tmp/*` worktrees to prevent `tmpfs` RAM/swap exhaustion.

## Execution

```bash
./scripts/run-test.sh [options] [target/path] [-- <extra args...>]
```

### Common Usage Examples

* **Run Only Suites Impacted by Current Git Diff (`-c` / `--changed`)**:
  ```bash
  ./scripts/run-test.sh -c
  ```
* **Target a Specific Rust Crate (`-p <crate>`)**:
  ```bash
  ./scripts/run-test.sh -p <crate-name>
  ```
* **Filter by Test Name / Substring (`-t <filter>`)**:
  ```bash
  ./scripts/run-test.sh -p <crate-name> -t "my_test"
  ./scripts/run-test.sh -f -t "smoke"
  ```
* **Run Web TypeScript, Biome & Vitest Suite (`-f` / `--web`)**:
  ```bash
  ./scripts/run-test.sh -f
  ```
* **Run Full Suite (`-a` / `--all`) or Inside Container (`--container`)**:
  ```bash
  ./scripts/run-test.sh --all
  ./scripts/run-test.sh --all --container
  ```

## Logs
* Detailed execution logs are preserved at `/tmp/<PROJECT_SLUG>-test-logs/latest/`.
* On failure, the last 40 lines of the failing stage log are tailed to stderr.
