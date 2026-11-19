# Empirical Evidence & Benchmark Receipts (`docs/internal/evidence/`)

Record baseline vs. delta Criterion, Callgrind, or E2E timing receipts here as `YYYY-MM-DD-<slug>.md`.

## Receipt Template

```markdown
# Benchmark Receipt: <Title>

* **Date**: `YYYY-MM-DD`
* **Commit**: `<git rev-parse --short HEAD>`
* **Command**: `./scripts/run-bench.sh -s <suite> -f "<filter>"`

| Benchmark / Metric | Baseline | After | Delta | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `<bench_id>` | `<val>` | `<val>` | `<% or x>` | `<notes>` |
```
