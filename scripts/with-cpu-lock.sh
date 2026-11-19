#!/usr/bin/env bash
# ==============================================================================
# Multi-Agent CPU, Build & Benchmark Lock Wrapper (scripts/with-cpu-lock.sh)
# ==============================================================================
# Coordinates concurrent agent worktrees via Linux kernel flock(2) on a single
# lockfile so parallel agents never overlap heavy Cargo compilations, test runs,
# E2E suites, or Criterion/CLI benchmarks.
#
# Usage:
#   ./scripts/with-cpu-lock.sh build <command> [args...]
#   ./scripts/with-cpu-lock.sh test  <command> [args...]
#   ./scripts/with-cpu-lock.sh bench <command> [args...]
#   ./scripts/with-cpu-lock.sh e2e   <command> [args...]
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/harness.env" ]]; then
  # shellcheck source=harness.env
  source "${SCRIPT_DIR}/harness.env"
fi

PROJECT_SLUG="${PROJECT_SLUG:-harness}"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <build|test|bench|e2e> <command> [args...]" >&2
  exit 2
fi

MODE="$1"
shift

LOCKFILE="${HARNESS_CPU_LOCKFILE:-/tmp/${PROJECT_SLUG}-cpu.lock}"

case "${MODE}" in
  build|test|bench|e2e)
    TIMEOUT_SECS="${HARNESS_LOCK_TIMEOUT_SECS:-5400}"
    ;;
  *)
    echo "Error: Unknown lock mode '${MODE}'. Expected one of: build, test, bench, e2e" >&2
    exit 2
    ;;
esac

# Re-entrant guard: if this process tree already holds the lock, execute directly
if [[ "${HARNESS_CPU_LOCK_HELD:-0}" == "1" ]]; then
  exec "$@"
fi

exec 9>"${LOCKFILE}"

if ! flock -x -n 9; then
  echo "[with-cpu-lock] Waiting for active '${MODE}' lock on ${LOCKFILE} (timeout=${TIMEOUT_SECS}s, pid=$$)..." >&2
  if ! flock -x -w "${TIMEOUT_SECS}" 9; then
    echo "[with-cpu-lock] ERROR: Timed out after ${TIMEOUT_SECS}s waiting for ${LOCKFILE}" >&2
    exit 1
  fi
  echo "[with-cpu-lock] Lock acquired on ${LOCKFILE} (mode=${MODE}, pid=$$)." >&2
fi

export HARNESS_CPU_LOCK_HELD=1
"$@"
