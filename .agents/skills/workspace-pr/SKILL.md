---
name: workspace-pr
description: >-
  Submodule-aware Git synchronization, inner/outer boundary validation, and optional
  GitHub Pull Request automation. By default runs in safe local mode (verifies authors,
  runs check-boundary.sh, syncs inner submodule commits to INNER_LOCAL_UPSTREAM if
  configured, and optionally commits updated submodule gitlink). Only pushes to remote
  or opens PRs when --push or --pr is explicitly passed.
---

# Submodule Sync & Pull Request Automation (`workspace-pr`)

## Execution

```bash
./scripts/run-pr.sh [options]
```

### Modes
* **Safe Local Sync (Default — Never Pushes to External Remotes)**:
  ```bash
  ./scripts/run-pr.sh
  ./scripts/run-pr.sh --commit-gitlink
  ```
* **Explicit Remote Push / GitHub PR (`--push` / `--pr`)**:
  ```bash
  ./scripts/run-pr.sh --push
  ./scripts/run-pr.sh --pr --title "feat: ..."
  ```
* **Target a Worktree (`-C`) or Preview (`--dry-run`)**:
  ```bash
  ./scripts/run-pr.sh -C .worktrees/<lane-name> --dry-run
  ```
