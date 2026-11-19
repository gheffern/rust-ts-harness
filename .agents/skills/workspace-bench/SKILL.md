---
name: workspace-bench
description: >-
  Execute Criterion microbenchmarks and Valgrind Callgrind profiles inside the
  inner Rust workspace (`INNER_DIR`), serialized under scripts/with-cpu-lock.sh bench. Use whenever
  measuring baseline vs. delta latency, throughput, or instruction/cache metrics.
---

# Criterion & Callgrind Benchmark Runner (`workspace-bench`)

Executes Criterion benchmarks (or Valgrind Callgrind microarchitectural profiles) serialized via `scripts/with-cpu-lock.sh bench` so concurrent agent worktrees never skew measurements.

> **Mandatory Filter Guardrail**: `-f <filter>` is required by default (pass `--full-suite` only when an exhaustive baseline is explicitly needed).

## Execution

```bash
./scripts/run-bench.sh -s <suite> -f "<filter>" [options]
```

### Common Examples
* **Targeted Criterion Benchmark**:
  ```bash
  ./scripts/run-bench.sh -s <suite> -f "<filter>"
  ./scripts/run-bench.sh -C .worktrees/<name> -s <suite> -f "<filter>"
  ```
* **Deterministic Callgrind Profile (`Ir`, `D1 Miss`, `Br Mispred`, `Est Cycles`)**:
  ```bash
  ./scripts/run-bench.sh --callgrind -s <suite> -f "<filter>"
  ```

## Logs
* Benchmark logs are saved to `/tmp/<PROJECT_SLUG>-bench-logs/latest/`.
