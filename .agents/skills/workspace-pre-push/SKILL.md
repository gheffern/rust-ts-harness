---
name: workspace-pre-push
description: >-
  Pre-push, pre-PR, and CI-parity verification gate. Verifies Git author identity,
  harness/inner clean-room boundary (check-boundary.sh), inner Rust fmt/clippy/test
  (+ optional wasm32), and Web TypeScript/Biome/Vitest/Vite build, emitting an
  authoritative Deterministic Gate Receipt before iterative-code-review.
---

# Pre-Push & CI Parity Gate (`workspace-pre-push`)

Executes the authoritative pre-push quality gate and emits a structured **Deterministic Gate Receipt** at `/tmp/<PROJECT_SLUG>-pre-push-logs/latest/receipt.txt` consumed by `iterative-code-review` and `ideate-plan-execute-review`.

## Execution

```bash
./scripts/run-pre-push.sh [options] [target_dir]
```

### Common Options
* `./scripts/run-pre-push.sh`: Auto-detect changed files and run affected stages
* `./scripts/run-pre-push.sh --all`: Run all stages unconditionally (full CI parity)
* `./scripts/run-pre-push.sh --rust-only`: Run Boundary + Rust (+ optional WASM)
* `./scripts/run-pre-push.sh --web-only`: Run Boundary + Web TypeScript/Biome/Vitest/Vite build
* `./scripts/run-pre-push.sh -C .worktrees/<name>`: Target a specific NVMe worktree
* `./scripts/run-pre-push.sh --container`: Run inside `CONTAINER_IMAGE` from `scripts/harness.env`
