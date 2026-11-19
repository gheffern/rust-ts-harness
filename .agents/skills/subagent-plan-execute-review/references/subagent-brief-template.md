# Task Brief Template (`subagent-plan-execute-review`)

Parent / Main agents MUST use this template when executing a task under [`subagent-plan-execute-review`](../SKILL.md) (either inline on the main thread when `execution_mode: "main_thread"` or via `invoke_subagent` with `TypeName: "self"`, `Model: "inherit"` when `execution_mode: "subagent"`).

> **Parent / Main Agent Pre-Flight, Worktree Lifecycle & Multi-Lane Barrier Rules**:
> 1. **Never guess or default `backwards_compatible` or `execution_mode`**: Obtain both settings (`backwards_compatible: true | false` and `execution_mode: "main_thread" | "subagent"`) from the user via `ask_question` before provisioning worktrees or starting Phase 0.
> 2. **Parent / Main Agent owns worktree creation and cleanup**: Sequentially provision each lane's NVMe worktree `<repo-root>/.worktrees/<lane_name>` on branch `feature/<lane_name>` (initializing submodules and setting git author from `scripts/harness.env`).
> 3. **Always check all lanes before declaring work done (`subagent` mode)**: On every subagent wakeup, call `manage_subagents(Action: "list")` and verify the status of all spawned lanes before merging or declaring completion.

---

## Copy-Paste Invocation Prompt Template

```markdown
Read and strictly follow `.agents/skills/subagent-plan-execute-review/SKILL.md`.

### 1. Mandatory Execution Configuration
* **`lane_name`**: `<kebab-case-lane-name>`
* **`backwards_compatible`**: `<true | false>`
* **`execution_mode`**: `<"main_thread" | "subagent">`
* **`worktree_path`**: `<repo-root>/.worktrees/<lane_name>`
* **`base_branch`**: `main`
* **`roadmap_items` (Optional)**: `<["RM-..."] | "N/A" | "deferred to parent merge">`

### 2. Scoped Crate & File Boundaries
* **Allowed Crates / Directories**:
  * `<crate-or-path-1>`
  * `<crate-or-path-2>`
* **Out-of-Scope (Do Not Touch)**:
  * Any files outside the allowed crates/directories above.

### 3. Benchmark Scope (`workspace-bench`, Optional)
* **Required Benchmark Commands** (or `"N/A — cold path"`):
  * `./scripts/run-bench.sh -C <repo-root>/.worktrees/<lane_name> -s <suite> -f "<filter>"`
* **Pre-Captured Baseline Metrics (Optional)**:
  * `<suite> / <filter>: <metric>`

### 4. Task Requirements & Acceptance Criteria
1. **Requirement 1 (`<Component>`)**:
   * **Objective / Problem**: `<exact description>`
   * **Acceptance Criteria & Invariants**: `<exact functional or architectural requirement>`

### 5. Deliverables
Execute all 6 phases of `subagent-plan-execute-review` and return the completed 6-Part Final Handoff Receipt.
```
