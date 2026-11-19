---
name: ideate-plan-execute-review
description: >-
  Continuous autonomous improvement loop (Ideate -> Plan -> Execute -> Review) with
  nested issue remediation and idea iteration loops. Leverages specialized subagents:
  read-only Ideator for codebase exploration and hypothesis backlog authoring, primary
  lead agent for planning and execution with workspace-bench / workspace-test baseline
  and delta verification, and independent Reviewer for diff auditing and test receipt
  validation under a strict Zero-Duplicate-Work policy.
---

# Ideate-Plan-Execute-Review Workflow

An autonomous, multi-agent continuous improvement lifecycle designed for performance optimization, refactoring, and iterative feature development.

Maintains a persistent, historical **Experiment Log** (`<appDataDir>/brain/<conversation-id>/ideas.md`) tracking both **Kept** (accepted and committed) and **Discarded** (reverted with failure reasons and lessons learned) hypotheses across iterations.

```mermaid
flowchart TD
    Goal["User Request / Goal"] --> IdeateSub["Stage 1: Ideate (Subagent: ideator)"]
    IdeateSub --> IdeasBacklog["Idea Backlog & Experiment Log (brain/ideas.md)"]
    IdeasBacklog --> SelectIdea["Select Top Candidate Idea"]

    subgraph OuterLoop ["Outer Loop: Idea Iteration Budget (Default 3)"]
        SelectIdea --> Baseline["Record Baseline Metric via ./scripts/run-bench.sh"]
        Baseline --> PlanLead["Stage 2: Plan (Primary Lead Agent)"]
        PlanLead --> PlanArtifact["Implementation Plan (brain/plan.md)"]
        PlanArtifact --> ExecLead["Stage 3: Execute (Primary Lead Agent)"]
        ExecLead --> DeltaVerify["Run ./scripts/run-test.sh & ./scripts/run-bench.sh (Serialized via with-cpu-lock.sh)"]
        DeltaVerify --> ReviewSub["Stage 4: Review (Subagent: reviewer - Zero Duplicate Retesting)"]

        subgraph InnerLoop ["Inner Loop: Issue Remediation (Max 3 Retries)"]
            ReviewSub --> Verdict{"Review Verdict?"}
            Verdict -- "CHANGES_REQUESTED" --> FixLead["Lead Agent Resolves Issues & Reruns Tests"]
            FixLead --> ReviewSub
            Verdict -- "Fail > 3 Retries / Regression" --> Discard["Rollback Working Tree & Log as DISCARDED"]
        end

        Verdict -- "APPROVED" --> Commit["Git Commit Approved Idea & Log as KEPT"]
        Commit --> NextIdea{"Budget Remaining & More Ideas?"}
        Discard --> NextIdea
        NextIdea -- "Yes" --> SelectIdea
        NextIdea -- "No / Target Met" --> FinalHandoff["Final Summary & Experiment Log Report"]
    end
```

---

## 1. Subagent Specifications

Prompt definitions and configuration schemas are maintained under:
- [`ideator.md`](../../subagents/ideator.md)
- [`reviewer.md`](../../subagents/reviewer.md)

| Agent | Role | Tool Capabilities | Primary Function |
| :--- | :--- | :--- | :--- |
| **`ideator`** | Ideator & Solution Architect | Read-only (`EnableWriteTools: false`) | Deep exploration of `INNER_DIR`, bottleneck discovery, hypothesis generation, and maintaining `ideas.md`. |
| **Lead Agent** | Coordinator, Planner & Implementer | Full write & commands | Baseline measurement (`./scripts/run-bench.sh`), plan authoring (`plan.md`), code execution, test runs (`./scripts/run-test.sh` + `./scripts/check-boundary.sh`), delta benchmarking, git commits, and issuing authoritative Test Execution Receipts. |
| **`reviewer`** | Code Reviewer & Quality Auditor | Read + diff inspection (code editing forbidden) | Independent git diff audit across outer and inner repos, `AGENTS.md` compliance, test receipt verification, and baseline-to-delta validation under the **Zero-Duplicate-Work Policy**. |

---

## 2. Workflow Lifecycle

### Stage 1: Ideation (Subagent: `ideator`)
1. Inspect any existing `<appDataDir>/brain/<conversation-id>/ideas.md` so previously **Discarded Ideas** are never repeated.
2. Explore `INNER_DIR` (`crates/*`, `web/`), formulating concrete hypotheses with exact `./scripts/run-bench.sh` baseline/delta commands and `./scripts/run-test.sh` regression commands.

### Stage 2: Planning & Baseline Measurement (Primary Lead Agent)
1. Select the top `Backlog` candidate from `ideas.md` and mark it `In-Progress`.
2. Capture the quantitative baseline before touching code using `./scripts/run-bench.sh -s <suite> -f <filter>`.
3. Author the plan in `<appDataDir>/brain/<conversation-id>/plan.md`.

### Stage 3: Execution & Post-Change Delta Verification (Primary Lead Agent)
1. Apply tightly scoped changes adhering to `AGENTS.md`.
2. Run `./scripts/check-boundary.sh` and `./scripts/run-test.sh -c` (or `-p <crate>`).
3. Run `./scripts/run-bench.sh -s <suite> -f <filter>` to capture the post-change delta.
4. Assemble the authoritative **Test Execution Receipt** (commands, exit code `0`, test counts, baseline vs. delta table).

### Stage 4: Independent Review & Outer-Loop Commit / Rollback
1. Invoke `reviewer` with the diff, plan path, and Test Execution Receipt (reviewer trusts the receipt and does NOT re-run tests or benchmarks).
2. If `APPROVED`:
   - Commit inner submodule changes (if any) and sync via `./scripts/run-pr.sh --commit-gitlink`, then commit outer changes using `GIT_AUTHOR_NAME <GIT_AUTHOR_EMAIL>` from `scripts/harness.env`.
   - Record the commit SHA and baseline-vs-delta gain under **Kept Ideas** in `ideas.md`.
3. If `CHANGES_REQUESTED` (> 3 retries) or negative performance delta:
   - Roll back uncommitted changes in both inner submodule and outer workspace.
   - Record the failure rationale and lessons learned under **Discarded Ideas** in `ideas.md`.
