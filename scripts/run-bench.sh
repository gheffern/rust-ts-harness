#!/usr/bin/env bash
# ==============================================================================
# Criterion & Callgrind Benchmark Runner (scripts/run-bench.sh)
# ==============================================================================
# Executes Criterion benchmarks (or Valgrind Callgrind microarchitectural
# profiles) inside the inner repository (INNER_DIR), serialized via
# scripts/with-cpu-lock.sh bench.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_WORKTREE="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET_DIR="${TARGET_DIR:-${DEFAULT_WORKTREE}}"

SUITE=""
FILTER=""
FULL_SUITE=false
USE_CONTAINER=false
CALLGRIND_MODE=false
CALLGRIND_TIME=""
CALLGRIND_COLLECT="*Bencher*iter*"
EXTRA_ARGS=()
ORIG_ARGS=("$@")

usage() {
  cat <<EOF
Usage: $0 -s <suite> -f <filter> [options] [-- <extra criterion args...>]

Options:
  -s, --suite <name>            Criterion bench target name (e.g., core_bench)
  -f, --filter <regex>          REQUIRED (unless --full-suite): Benchmark ID substring/regex
      --full-suite              Allow running full suite without -f <filter>
  -C, --dir <path>              Target repository or worktree directory (default: ${DEFAULT_WORKTREE})
      --callgrind               Profile matching benchmarks under Valgrind Callgrind
      --callgrind-time <sec>    Run Criterion --profile-time <sec> under Callgrind
      --callgrind-collect <pat> Callgrind --toggle-collect pattern (default: *Bencher*iter*)
      --container               Run inside podman container (CONTAINER_IMAGE from harness.env)
      --host                    Run directly on host (default)
  -h, --help                    Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--suite) SUITE="$2"; shift 2 ;;
    -f|--filter) FILTER="$2"; shift 2 ;;
    --full-suite) FULL_SUITE=true; shift ;;
    -C|--dir) TARGET_DIR="$2"; shift 2 ;;
    --callgrind) CALLGRIND_MODE=true; shift ;;
    --callgrind-time) CALLGRIND_MODE=true; CALLGRIND_TIME="$2"; shift 2 ;;
    --callgrind-collect) CALLGRIND_COLLECT="$2"; shift 2 ;;
    --container) USE_CONTAINER=true; shift ;;
    --host) USE_CONTAINER=false; shift ;;
    --) shift; EXTRA_ARGS+=("$@"); break ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

TARGET_DIR="$(cd "${TARGET_DIR}" && pwd)"
if [[ "${TARGET_DIR}" == /tmp/* ]]; then
  echo "[run-bench] ERROR: Worktree '${TARGET_DIR}' is on /tmp (RAM-backed tmpfs)." >&2
  exit 2
fi

if [[ -z "${SUITE}" ]]; then
  echo "[run-bench] ERROR: -s <suite> is required." >&2
  usage
  exit 2
fi

if [[ "${FULL_SUITE}" != "true" && -z "${FILTER}" ]]; then
  echo "[run-bench] ERROR: -f <filter> is required by default (pass --full-suite to override)." >&2
  exit 2
fi

if [[ -f "${TARGET_DIR}/scripts/harness.env" ]]; then
  # shellcheck source=harness.env
  source "${TARGET_DIR}/scripts/harness.env"
elif [[ -f "${SCRIPT_DIR}/harness.env" ]]; then
  # shellcheck source=harness.env
  source "${SCRIPT_DIR}/harness.env"
fi

PROJECT_SLUG="${PROJECT_SLUG:-harness}"
INNER_DIR="${INNER_DIR:-app}"
TEMPLATE_INNER_DIR="${TEMPLATE_INNER_DIR:-templates/inner-project}"
CONTAINER_IMAGE="${CONTAINER_IMAGE:-localhost/rust-toolchain:latest}"

ACTIVE_INNER_REL=""
if [[ -f "${TARGET_DIR}/${INNER_DIR}/Cargo.toml" ]]; then
  ACTIVE_INNER_REL="${INNER_DIR}"
elif [[ -f "${TARGET_DIR}/${TEMPLATE_INNER_DIR}/Cargo.toml" ]]; then
  ACTIVE_INNER_REL="${TEMPLATE_INNER_DIR}"
else
  echo "[run-bench] ERROR: No Cargo.toml found in '${INNER_DIR}/' or '${TEMPLATE_INNER_DIR}/'." >&2
  exit 1
fi

if [[ "${HARNESS_CPU_LOCK_HELD:-0}" != "1" ]] && [[ -x "${SCRIPT_DIR}/with-cpu-lock.sh" ]]; then
  exec "${SCRIPT_DIR}/with-cpu-lock.sh" bench "$0" "${ORIG_ARGS[@]}"
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_ROOT="/tmp/${PROJECT_SLUG}-bench-logs"
LOG_DIR="${LOG_ROOT}/${TIMESTAMP}"
mkdir -p "${LOG_DIR}"
ln -sfn "${TIMESTAMP}" "${LOG_ROOT}/latest"
find "${LOG_ROOT}" -mindepth 1 -maxdepth 1 -type d -name '20[0-9][0-9]*' | sort -r | tail -n +11 | xargs -r rm -rf

run_in_env() {
  if [[ "${USE_CONTAINER}" == "true" ]]; then
    mkdir -p "${HOME}/.cargo" "${HOME}/.cache/sccache"
    podman run --rm \
      --security-opt label=disable \
      -v "${TARGET_DIR}:/build:z" \
      -v "${HOME}/.cargo:/cargo-cache:z" \
      -v "${HOME}/.cache/sccache:/sccache:z" \
      -e CARGO_HOME=/cargo-cache \
      -e SCCACHE_DIR=/sccache \
      -e RUSTC_WRAPPER=/usr/local/bin/sccache \
      -e CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_RUSTFLAGS="-C target-cpu=x86-64-v3 -C link-arg=-fuse-ld=mold" \
      -w "/build/${ACTIVE_INNER_REL}" \
      "${CONTAINER_IMAGE}" \
      "$@"
  else
    (
      cd "${TARGET_DIR}/${ACTIVE_INNER_REL}"
      if command -v sccache >/dev/null 2>&1; then
        export RUSTC_WRAPPER="sccache"
      fi
      if [[ "$(uname -m)" == "x86_64" ]] && command -v mold >/dev/null 2>&1; then
        export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_RUSTFLAGS="-C target-cpu=x86-64-v3 -C link-arg=-fuse-ld=mold"
      fi
      "$@"
    )
  fi
}

LOG_FILE="${LOG_DIR}/${SUITE}.log"

if [[ "${CALLGRIND_MODE}" == "true" ]]; then
  LOG_FILE="${LOG_DIR}/${SUITE}-callgrind.log"
  echo "[run-bench] Building release bench binary (${SUITE}, inner=${ACTIVE_INNER_REL})..."
  BIN_JSON="$(run_in_env cargo bench --bench "${SUITE}" --no-run --message-format=json)"
  BIN_PATH="$(printf '%s\n' "${BIN_JSON}" | python3 -c 'import json,sys
for line in sys.stdin:
  try: obj=json.loads(line)
  except Exception: continue
  if obj.get("reason")=="compiler-artifact" and obj.get("executable") and obj.get("target",{}).get("kind")==["bench"]:
    print(obj["executable"]); break')"
  if [[ -z "${BIN_PATH}" ]]; then
    echo "[run-bench] ERROR: Could not resolve compiled benchmark binary for '${SUITE}'." >&2
    exit 1
  fi
  CG_OUT="${LOG_DIR}/${SUITE}.callgrind.out"
  BENCH_ARGS=("${BIN_PATH}")
  [[ -n "${FILTER}" ]] && BENCH_ARGS+=("${FILTER}")
  if [[ -n "${CALLGRIND_TIME}" ]]; then
    BENCH_ARGS+=("--profile-time" "${CALLGRIND_TIME}")
  else
    BENCH_ARGS+=("--test")
  fi
  run_in_env valgrind --tool=callgrind --cache-sim=yes --branch-sim=yes \
    --toggle-collect="${CALLGRIND_COLLECT}" \
    --callgrind-out-file="${CG_OUT}" \
    "${BENCH_ARGS[@]}" 2>&1 | tee "${LOG_FILE}"
  if command -v callgrind_annotate >/dev/null 2>&1; then
    callgrind_annotate --auto=yes "${CG_OUT}" >> "${LOG_FILE}"
  fi
  echo "[run-bench] Callgrind receipt saved to ${LOG_FILE}"
  exit 0
fi

CARGO_CMD=("cargo" "bench" "--bench" "${SUITE}" "--")
[[ -n "${FILTER}" ]] && CARGO_CMD+=("${FILTER}")
[[ ${#EXTRA_ARGS[@]} -gt 0 ]] && CARGO_CMD+=("${EXTRA_ARGS[@]}")

echo "[run-bench] Running '${SUITE}' (inner=${ACTIVE_INNER_REL}, filter=${FILTER:-<all>})..."
run_in_env "${CARGO_CMD[@]}" 2>&1 | tee "${LOG_FILE}"
echo "[run-bench] Benchmark log saved to ${LOG_FILE}"
