---
name: subagent-plan-execute-review
description: Structured autonomous workflow for executing a task brief or requirement set either inline on the main thread or via delegated implementation subagents. Enforces mandatory user-sourced backwards_compatible and execution_mode (main_thread | subagent) flags via ask_question, isolated NVMe worktree execution, Invariant-First plan drafting, iterative-plan-review (max 5 rounds), scoped baseline vs. delta benchmarking (workspace-bench), deterministic gate verification (workspace-test / workspace-pre-push), iterative-code-review (max 5 rounds), and a 6-part Final Handoff Receipt.
---

# Plan-Execute-Review Skill (`subagent-plan-execute-review`)

This skill defines the end-to-end execution contract for executing a scoped engineering task brief or set of requirements either **inline on the Main Thread** (`execution_mode: "main_thread"`, avoiding cold context-rebuilding overhead when the main thread already holds warm file context) or via one or more **Implementation Subagents** (`execution_mode: "subagent"`, `invoke_subagent` with `TypeName: "self"`, ideal for multi-lane parallel waves or large cold-context tasks).

Both modes execute the **exact same 6-phase verification pipeline** inside an isolated NVMe worktree—including Invariant-First planning, [`iterative-plan-review`](../iterative-plan-review/SKILL.md) (via a fresh-eyed `research` reviewer subagent), [`workspace-bench`](../workspace-bench/SKILL.md) baseline/delta verification, [`workspace-test`](../workspace-test/SKILL.md) / [`workspace-pre-push`](../workspace-pre-push/SKILL.md) deterministic gates, [`iterative-code-review`](../iterative-code-review/SKILL.md) (via a fresh-eyed `research` reviewer subagent), and a 6-part Final Handoff Receipt.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ PARENT / MAIN AGENT PRE-FLIGHT (`ask_question` if either flag is missing)    │
│   1. Obtain `backwards_compatible: true | false` from User Input (mandatory) │
│   2. Obtain `execution_mode: "main_thread" | "subagent"` from User Input     │
│   3. Provision NVMe worktree(s) `.worktrees/<lane-name>`                     │
│   4. If `subagent`: populate Brief & spawn `self` subagent(s)                │
│      If `main_thread`: execute Phases 0..6 directly on the main thread       │
└──────────────────────────────────────┬───────────────────────────────────────┘
                                       ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ PHASE 0: BRIEF VALIDATION, WORKTREE VERIFICATION & BASELINE BENCHMARKS       │
│   • Fail-fast if `backwards_compatible`, `execution_mode`, or worktree unset │
│   • Verify isolated NVMe worktree `.worktrees/<lane-name>` (`feature/<name>`)│
│   • Capture scoped baseline via `./scripts/run-bench.sh -s <suite> -f <flt>` │
└──────────────────────────────────────┬───────────────────────────────────────┘
                                       ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ PHASE 1 & 2: INVARIANT-FIRST PLAN DRAFTING & `iterative-plan-review`         │
│   • Draft plan enforcing `backwards_compatible` & boundary/resource rules    │
│   • Spawn `Fresh-Eyed Plan Reviewer` (`research` subagent, max 5 rounds)     │
│   • Remediate blocking findings (or return `ESCALATED` if unresolved @ R5)   │
└──────────────────────────────────────┬───────────────────────────────────────┘
                                       ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ PHASE 3 & 4: IMPLEMENTATION, BENCHMARK DELTA & DETERMINISTIC GATE            │
│   • Implement plan (Boy Scout anti-suppression, clean ADTs, safe state)      │
│   • Compare post-change `./scripts/run-bench.sh` against baseline (≤3% noise)│
│   • Pass `./scripts/run-pre-push.sh` (or scoped `run-test.sh` + boundary)    │
│   • Commit inner submodule + outer repo as configured GIT_AUTHOR             │
└──────────────────────────────────────┬───────────────────────────────────────┘
                                       ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ PHASE 5 & 6: `iterative-code-review` & 6-PART FINAL HANDOFF RECEIPT          │
│   • Spawn `Fresh-Eyed Code Reviewer` (`research` subagent, max 5 rounds)     │
│   • If blockers found: fix -> re-verify -> commit -> next round (up to R5)   │
│   • Emit structured 6-Part Final Handoff Receipt                             │
└──────────────────────────────────────┬───────────────────────────────────────┘
                                       ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ MULTI-LANE COMPLETION BARRIER (`execution_mode: "subagent"`)                 │
│   • Subagents finish out of order; on EVERY wakeup call `manage_subagents`   │
│   • Check status of ALL lanes before merging or declaring work done          │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 1. Mandatory Inputs: `backwards_compatible` & `execution_mode` Contracts

### 1.1 Pre-Flight Gate (`ask_question` Required When Unspecified), Worktree Lifecycle & Multi-Lane Barrier
* **Never Guess `backwards_compatible` or `execution_mode`**: Before starting Phase 0 or spawning any subagent under this skill, the agent **MUST** have explicit answers from the user for **both** mandatory flags:
  1. `backwards_compatible`: `true` (preserve existing persisted formats/schemas and additive-only public APIs) or `false` (clean-slate replacement permitted).
  2. `execution_mode`: `"main_thread"` (execute Phases 0–6 directly on the main thread while still spawning `research` subagents for `iterative-plan-review` and `iterative-code-review`) or `"subagent"` (delegate Phases 0–6 to background `self` implementation subagent(s)).
  * **Mandatory `ask_question` Prompt**: If the user has not explicitly stated either `backwards_compatible` or `execution_mode` in their prompt, call `ask_question` before creating worktrees or drafting plans. Place `(Recommended)` on `"main_thread"` for single-lane tasks with warm file context, or on `"subagent"` for multi-lane parallel waves or large cold-context tasks.
* **Parent-Owned NVMe Worktree Lifecycle**:
  * Source `scripts/harness.env` to read `INNER_DIR`, `GIT_AUTHOR_NAME`, and `GIT_AUTHOR_EMAIL`.
  * Provision each lane's NVMe worktree `<repo-root>/.worktrees/<lane-name>` on branch `feature/<lane-name>` **before** starting Phase 0 or calling `invoke_subagent`:
    ```bash
    git worktree add -b "feature/<lane-name>" ".worktrees/<lane-name>" main
    git -C ".worktrees/<lane-name>" -c protocol.file.allow=always submodule update --init --recursive
    if [[ -e ".worktrees/<lane-name>/${INNER_DIR}/.git" ]]; then
      git -C ".worktrees/<lane-name>/${INNER_DIR}" checkout -B "feature/<lane-name>" HEAD
      git -C ".worktrees/<lane-name>/${INNER_DIR}" config user.name "${GIT_AUTHOR_NAME}"
      git -C ".worktrees/<lane-name>/${INNER_DIR}" config user.email "${GIT_AUTHOR_EMAIL}"
    fi
    git -C ".worktrees/<lane-name>" config user.name "${GIT_AUTHOR_NAME}"
    git -C ".worktrees/<lane-name>" config user.email "${GIT_AUTHOR_EMAIL}"
    ```
  * When `execution_mode: "subagent"`, use [`references/subagent-brief-template.md`](references/subagent-brief-template.md) to pass the pre-provisioned `worktree_path`, `backwards_compatible`, and `execution_mode` to each subagent.
* **Mandatory Multi-Lane Completion Barrier (Out-of-Order Wakeups in `subagent` Mode)**:
  * On every subagent wakeup, call `manage_subagents(Action: "list")` and check the status of **all** spawned lanes before merging branches, removing worktrees, or declaring the overall task complete.

### 1.2 Fail-Fast Gate
* On startup of Phase 0, verify `backwards_compatible` (`true` or `false`), `execution_mode` (`"main_thread"` or `"subagent"`), and an existing `worktree_path` are explicitly set.
* **Missing or Ambiguous Flag**: Halt immediately before drafting a plan or editing files.

### 1.3 Semantics of `backwards_compatible`

| Setting | Persisted Data / Schema Compatibility | Surface API Contract (CLI / Server / Web) | Handoff Requirement |
| :--- | :--- | :--- | :--- |
| **`backwards_compatible: true`** | **Strict Preservation**: Existing persisted formats/schemas/configs remain readable and valid without forced migration. | **Additive Only**: Existing CLI flags, API endpoints/schemas, and frontend contracts remain backwards-compatible (new fields optional/defaulted). | Confirm zero breaking API/schema diffs and note any optional additive migrations. |
| **`backwards_compatible: false`** | **Clean Replacement Permitted**: May replace schemas, bump format versions, or remove legacy shims directly. | **Synchronized Breaking Replacement Permitted**: May rename, replace, or tighten schemas across CLI, Server, and Web simultaneously, keeping all surfaces coherent. | Explicitly list exact breaking format/endpoint changes in Part 2 of the Final Handoff Receipt. |

---

## 2. Workspace Isolation, CPU Lock & Git Hygiene

1. **Parent-Provisioned NVMe Worktree Verification**:
   * Execute all file reads/edits, test commands (`./scripts/run-test.sh -C <worktree_path>`), and benchmark commands (`./scripts/run-bench.sh -C <worktree_path>`) strictly inside `worktree_path`.
   * **NEVER use `/tmp` (`tmpfs`)** for worktrees or `CARGO_TARGET_DIR`.
2. **Mandatory Multi-Agent CPU & Benchmark Lock**:
   * All compilation, test runs, and benchmarks serialize through `./scripts/with-cpu-lock.sh` (acquired automatically by `run-test.sh`, `run-bench.sh`, and `run-pre-push.sh`).
3. **Git Author Identity & Submodule Protocol**:
   * Commit in both `INNER_DIR` and outer repo using `GIT_AUTHOR_NAME <GIT_AUTHOR_EMAIL>` from `scripts/harness.env`.
   * When `INNER_DIR` files are modified:
     1. Commit inside `INNER_DIR` first.
     2. Push to `INNER_LOCAL_UPSTREAM` (if configured in `scripts/harness.env`).
     3. Stage `INNER_DIR` in the outer worktree and commit alongside outer changes.
   * **Never push to external remotes** and **do not merge into `main`** inside the lane—leave `feature/<lane-name>` clean for review and merge.

---

## 3. Six-Phase Execution Pipeline

### Phase 0: Brief Validation, Worktree Verification & Scoped Baseline Benchmarks
1. Validate required brief fields (`backwards_compatible`, `execution_mode`, `lane_name`, `worktree_path`, `requirements`).
2. Verify `worktree_path` exists on branch `feature/<lane-name>` with `INNER_DIR` initialized (if applicable) and git author configured.
3. Read target files and tests. If touching a benchmarked hot path (and not provided pre-captured metrics), capture a scoped baseline using `./scripts/run-bench.sh -C <worktree_path> -s <suite> -f "<filter>"`. (For cold/unbenchmarked paths, record `N/A — cold path`.)

### Phase 1: Draft Invariant-First Implementation Plan
Run an exhaustive search (`rg`) for every retired, signature-changed, or migrated symbol or ambient pattern up front. Write the plan to `<appDataDir>/brain/<conversation-id>/plan-<lane-name>.md` (or `<worktree_path>/.plan.md`, removing `.plan.md` before committing).

Per [`iterative-plan-review`](../iterative-plan-review/SKILL.md), the plan **MUST NOT** contain code snippets or pseudo-code, and **MUST** contain:
1. **Data & State Model (ADTs & Schemas)**
2. **System & Resource Invariants**
3. **Backwards-Compatibility & Surface Parity Contract** (`backwards_compatible: true | false`)
4. **Failure Modes, Bounds & Edge Cases**
5. **Verification & Benchmark Gate Plan**
6. **Scoped File Delta Map & Migration Totality** (distinguishing **Compiler-Enforced Retirements** from **Coexisting APIs / Ambient Patterns**)

### Phase 2: Execute `iterative-plan-review` (Max 5 Rounds)
Run [`iterative-plan-review`](../iterative-plan-review/SKILL.md) with an ephemeral `research` subagent (`Role: "Fresh-Eyed Plan Reviewer"`). Remediate blocking findings across up to 5 rounds; return `ESCALATED` if unresolved at Round 5 or if a conflict with the brief occurs.

### Phase 3: Implementation & Inner Verification Loop
1. Uphold `unsafe_code = "deny"`, `clippy::all`, `clippy::pedantic`, `clippy::perf`, zero production `unwrap_used`/`expect_used`, and the Boy Scout Anti-Suppression Rule.
2. Add deterministic unit/integration/regression tests for every invariant and edge case in the plan.
3. Run scoped tests via `./scripts/run-test.sh -C <worktree_path> -c` (or `-p <crate>`).

### Phase 4: Post-Change Benchmark Delta, Deterministic Gate & Git Commit
1. Re-run Phase 0 benchmark commands (if applicable) and verify no unexpected regression beyond noise (`> 3%` wall-clock or `> 1%` Callgrind `Ir`/`Est Cycles`).
2. Run `./scripts/run-pre-push.sh -C <worktree_path>` (or scoped `./scripts/run-test.sh` + `./scripts/check-boundary.sh`).
3. Remove any temporary `.plan.md` from the worktree, commit `INNER_DIR` and outer worktree cleanly (`git status --porcelain` empty), and sync `INNER_DIR` to `INNER_LOCAL_UPSTREAM` if configured.

### Phase 5: Execute `iterative-code-review` (Max 5 Rounds)
Run [`iterative-code-review`](../iterative-code-review/SKILL.md) with an ephemeral `research` subagent (`Role: "Fresh-Eyed Code Reviewer"`), passing the worktree path, commit range, approved plan path, `backwards_compatible`, optional `roadmap_items`, and the Deterministic Gate Receipt. Fix any blockers, re-run the deterministic gate, commit fixes, and spawn a fresh reviewer for the next round (up to Round 5).

### Phase 6: Structured 6-Part Final Handoff Receipt

```markdown
## Subagent Final Handoff Receipt (`<lane-name>`)

### 1. Status, Worktree & Commit SHAs
* **Final Status**: `COMPLETED` | `ESCALATED`
* **Worktree Path**: `<repo-root>/.worktrees/<lane-name>`
* **Branch**: `feature/<lane-name>`
* **Inner Submodule Commit Range**: `<base_sha>..<head_sha>` | `N/A`
* **Outer Repo Commit Range**: `<base_sha>..<head_sha>`
* **Working Tree Clean (`git status --porcelain`)**: `CLEAN`

### 2. Backwards-Compatibility & Schema Impact
* **`backwards_compatible` Brief Setting**: `true` | `false`
* **Persisted Data / Schema Impact**: `NONE` | `<exact description>`
* **Surface API Impact (CLI / Server / Web)**: `NONE` | `ADDITIVE` | `BREAKING (<surfaces>)`

### 3. Plan Review Receipt (`iterative-plan-review`)
* **Plan Artifact**: `<path-to-plan.md>`
* **Rounds Used**: `1`..`5`
* **Reviewer Conversation ID(s)**: `<uuid>`
* **Final Plan Verdict**: `APPROVED`

### 4. Benchmark Baseline vs. Delta Table (`workspace-bench`)
| Suite & Filter | Baseline | Post-Change | Delta | Status / Notes |
| :--- | :--- | :--- | :--- | :--- |
| `<suite> / <filter>` | `<val>` | `<val>` | `<+/-X.X%>` | `PASS` / `N/A — cold path` |

### 5. Deterministic Gate Receipt (`workspace-test` / `workspace-pre-push`)
* **Gate Command Executed**: `./scripts/run-pre-push.sh -C <worktree>`
* **Rust `fmt` & `clippy -D warnings`**: `PASS`
* **Tests (`cargo test` / `vitest`)**: `PASS`
* **Inner/Outer Clean-Room Boundary (`check-boundary.sh`)**: `PASS`
* **Git Author Verification**: `PASS`

### 6. Code Review Verdict (`iterative-code-review`)
* **Rounds Used**: `1`..`5`
* **Reviewer Conversation ID(s)**: `<uuid>`
* **Final Code Review Verdict**: `APPROVED` (or remaining blocker details if `ESCALATED`)
```
