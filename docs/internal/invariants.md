# System Invariants Registry

Authoritative `INV-*` rules governing the outer agentic harness and inner code repository (`INNER_DIR` in `scripts/harness.env`).
Every plan and code review (`iterative-plan-review` / `iterative-code-review`) enforces these invariants.

## Numbering Convention
- `INV-BOUNDARY-*`: Outer harness / inner code repository clean-room separation.
- `INV-STATE-*`: Persistence, atomicity, concurrency, and schema compatibility.
- `INV-SURFACE-*`: CLI / API / Web contract parity and payload bounds.
- `INV-DOMAIN-*`: Optional project-specific domain/mathematical invariants (also surfaced in `AGENTS.md` Section 5).

---

## 1. Harness / Inner Repo Boundary (`INV-BOUNDARY-*`)

* **`INV-BOUNDARY-1` (Code-Free Outer Harness)**: The outer harness contains only agentic instructions, skills, internal docs, and scripts — no project source code (`Cargo.toml`, `package.json`, `crates/`, `src/`, `web/`) outside `templates/`.
* **`INV-BOUNDARY-2` (Agent-Free Inner Repo)**: The inner repository (`INNER_DIR`, default `app/`) remains 100% free of `AGENTS.md`, `.agents/`, `harness.env`, `docs/internal/` references, and developer host paths (`/home/<user>/`). Enforced deterministically by `./scripts/check-boundary.sh`.

## 2. State, Storage & Concurrency (`INV-STATE-*`)

* Add project-specific persistence, concurrency, and atomicity invariants here.

## 3. Surface Contracts (`INV-SURFACE-*`)

* Add API, CLI, and Web UI contract invariants here.

## 4. Domain-Specific Invariants (`INV-DOMAIN-*`)

* Add domain, algorithmic, or mathematical invariants here (and reference them in `AGENTS.md` Section 5 if you enable Project-Defined Review Axis 5).
