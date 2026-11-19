#!/usr/bin/env bash
# ==============================================================================
# Pre-Push & CI Parity Verification Gate (scripts/run-pre-push.sh)
# ==============================================================================
# Executes the pre-push quality gate and emits a structured Deterministic Gate
# Receipt at /tmp/${PROJECT_SLUG}-pre-push-logs/latest/receipt.txt consumed by
# iterative-code-review and ideate-plan-execute-review.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_WORKTREE="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET_DIR="${TARGET_DIR:-${DEFAULT_WORKTREE}}"

MODE="auto" # auto | all | rust | web
USE_CONTAINER=false
ORIG_ARGS=("$@")

usage() {
  cat <<EOF
Usage: $0 [options] [target_dir]

Options:
  (default)            Auto-detect changed files and run affected quality gates
  -A, --all, --full    Run all stages unconditionally (full CI parity)
  -r, --rust-only      Run Boundary + Rust (+ optional WASM) gates
  -f, --web-only       Run Boundary + Web (TypeScript, Biome, Vitest, Vite build)
  -C, --dir <path>     Target repository or worktree directory (default: ${DEFAULT_WORKTREE})
      --container      Run inside podman container (CONTAINER_IMAGE from harness.env)
      --host           Run directly on host (default)
  -h, --help           Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -A|--all|--full|--full-ci) MODE="all"; shift ;;
    -r|--rust-only|-b|--backend-only) MODE="rust"; shift ;;
    -f|--web-only|--frontend-only) MODE="web"; shift ;;
    -C|--dir) TARGET_DIR="$2"; shift 2 ;;
    --container) USE_CONTAINER=true; shift ;;
    --host) USE_CONTAINER=false; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ -d "$1" ]]; then
        TARGET_DIR="$1"
      else
        echo "Unknown option: $1" >&2
        usage
        exit 1
      fi
      shift
      ;;
  esac
done

TARGET_DIR="$(cd "${TARGET_DIR}" && pwd)"
if [[ "${TARGET_DIR}" == /tmp/* ]]; then
  echo "[run-pre-push] ERROR: Worktree '${TARGET_DIR}' is on /tmp (RAM-backed tmpfs)." >&2
  exit 2
fi

if [[ -f "${TARGET_DIR}/scripts/harness.env" ]]; then
  # shellcheck source=harness.env
  source "${TARGET_DIR}/scripts/harness.env"
elif [[ -f "${SCRIPT_DIR}/harness.env" ]]; then
  # shellcheck source=harness.env
  source "${SCRIPT_DIR}/harness.env"
fi

PROJECT_NAME="${PROJECT_NAME:-rust-ts-harness}"
PROJECT_SLUG="${PROJECT_SLUG:-harness}"
INNER_DIR="${INNER_DIR:-app}"
TEMPLATE_INNER_DIR="${TEMPLATE_INNER_DIR:-templates/inner-project}"
WEB_SUBDIR="${WEB_SUBDIR:-}"
CONTAINER_IMAGE="${CONTAINER_IMAGE:-localhost/rust-ts-harness-toolchain:latest}"

ACTIVE_INNER_REL=""
if [[ -d "${TARGET_DIR}/${INNER_DIR}" ]]; then
  ACTIVE_INNER_REL="${INNER_DIR}"
elif [[ -d "${TARGET_DIR}/${TEMPLATE_INNER_DIR}" ]]; then
  ACTIVE_INNER_REL="${TEMPLATE_INNER_DIR}"
fi

INNER_ROOT="${TARGET_DIR}/${ACTIVE_INNER_REL}"
RUST_MANIFEST=""
[[ -n "${ACTIVE_INNER_REL}" && -f "${INNER_ROOT}/Cargo.toml" ]] && RUST_MANIFEST="${ACTIVE_INNER_REL}/Cargo.toml"

WEB_REL=""
if [[ -n "${ACTIVE_INNER_REL}" ]]; then
  if [[ -n "${WEB_SUBDIR}" && -f "${INNER_ROOT}/${WEB_SUBDIR}/package.json" ]]; then
    WEB_REL="${ACTIVE_INNER_REL}/${WEB_SUBDIR}"
  else
    for candidate in web frontend .; do
      if [[ -f "${INNER_ROOT}/${candidate}/package.json" ]]; then
        if [[ "${candidate}" == "." ]]; then
          WEB_REL="${ACTIVE_INNER_REL}"
        else
          WEB_REL="${ACTIVE_INNER_REL}/${candidate}"
        fi
        break
      fi
    done
  fi
fi

if [[ "${HARNESS_CPU_LOCK_HELD:-0}" != "1" ]] && [[ -x "${SCRIPT_DIR}/with-cpu-lock.sh" ]]; then
  exec "${SCRIPT_DIR}/with-cpu-lock.sh" build "$0" "${ORIG_ARGS[@]}"
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_ROOT="/tmp/${PROJECT_SLUG}-pre-push-logs"
LOG_DIR="${LOG_ROOT}/${TIMESTAMP}"
mkdir -p "${LOG_DIR}"
ln -sfn "${TIMESTAMP}" "${LOG_ROOT}/latest"
find "${LOG_ROOT}" -mindepth 1 -maxdepth 1 -type d -name '20[0-9][0-9]*' | sort -r | tail -n +11 | xargs -r rm -rf

RECEIPT_FILE="${LOG_DIR}/receipt.txt"
CURRENT_STAGE="Initialization"
CURRENT_LOG=""

on_error() {
  local exit_code=$?
  printf "\n\033[0;31m[PRE-PUSH GATE FAILED] %s (Exit Code: %d)\033[0m\n" "${CURRENT_STAGE}" "${exit_code}" >&2
  if [[ -n "${CURRENT_LOG}" && -f "${CURRENT_LOG}" ]]; then
    printf "=== Last 40 lines of %s ===\n" "${CURRENT_LOG}" >&2
    tail -n 40 "${CURRENT_LOG}" >&2
    printf "=== End of error snippet (Full log: %s) ===\n\n" "${CURRENT_LOG}" >&2
  fi
  exit "${exit_code}"
}
trap 'on_error' ERR

if [[ "${USE_CONTAINER}" == "true" ]]; then
  if [[ -f "/.dockerenv" ]] || [[ -f "/run/.containerenv" ]]; then
    USE_CONTAINER=false
  elif ! command -v podman >/dev/null 2>&1; then
    echo "[run-pre-push] ERROR: --container requested but 'podman' is not installed." >&2
    exit 1
  else
    "${SCRIPT_DIR}/build-toolchain.sh" --if-missing
  fi
fi

run_in_env() {
  local work_subdir="$1"
  shift
  if [[ "${USE_CONTAINER}" == "true" ]]; then
    mkdir -p "${HOME}/.cargo" "${HOME}/.cache/sccache" "${HOME}/.npm"
    podman run --rm \
      --security-opt label=disable \
      -v "${TARGET_DIR}:/build:z" \
      -v "${HOME}/.cargo:/cargo-cache:z" \
      -v "${HOME}/.cache/sccache:/sccache:z" \
      -v "${HOME}/.npm:/root/.npm:z" \
      -e CARGO_HOME=/cargo-cache \
      -e SCCACHE_DIR=/sccache \
      -e RUSTC_WRAPPER=/usr/local/bin/sccache \
      -e CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_RUSTFLAGS="-C target-cpu=x86-64-v3 -C link-arg=-fuse-ld=mold" \
      -w "/build/${work_subdir}" \
      "${CONTAINER_IMAGE}" \
      "$@"
  else
    (
      cd "${TARGET_DIR}/${work_subdir}"
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

RUN_RUST=false
RUN_WEB=false
WEB_EXPLICIT=false

if [[ "${MODE}" == "all" ]]; then
  [[ -n "${RUST_MANIFEST}" ]] && RUN_RUST=true
  [[ -n "${WEB_REL}" ]] && RUN_WEB=true
elif [[ "${MODE}" == "rust" ]]; then
  RUN_RUST=true
elif [[ "${MODE}" == "web" ]]; then
  RUN_WEB=true
  WEB_EXPLICIT=true
else
  INNER_CHANGED=""
  if [[ -n "${ACTIVE_INNER_REL}" && -e "${INNER_ROOT}/.git" ]]; then
    INNER_CHANGED="$(git -C "${INNER_ROOT}" diff --name-only HEAD 2>/dev/null || true)"
    [[ -z "${INNER_CHANGED}" ]] && INNER_CHANGED="$(git -C "${INNER_ROOT}" status --porcelain 2>/dev/null | awk '{print $2}' || true)"
  elif [[ -n "${ACTIVE_INNER_REL}" ]]; then
    INNER_CHANGED="$(git -C "${TARGET_DIR}" diff --name-only HEAD -- "${ACTIVE_INNER_REL}" 2>/dev/null || true)"
  fi
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if [[ "$f" =~ (^|/)(web|frontend)/ || "$f" =~ \.(ts|tsx|js|jsx|css|html)$ ]]; then
      RUN_WEB=true
    else
      RUN_RUST=true
    fi
  done <<< "${INNER_CHANGED}"
  if [[ "${RUN_RUST}" == "false" && "${RUN_WEB}" == "false" ]]; then
    [[ -n "${RUST_MANIFEST}" ]] && RUN_RUST=true
    [[ -n "${WEB_REL}" ]] && RUN_WEB=true
  fi
fi

START_TIME="$(date +%s)"
printf "\n=========================================================\n"
printf "  %s Pre-Push & CI Parity Gate\n" "${PROJECT_NAME}"
printf "  Inner Repo : %s\n" "${ACTIVE_INNER_REL:-none}"
printf "  Mode       : %s | Env: %s\n" "${MODE}" "$([[ "${USE_CONTAINER}" == "true" ]] && echo "container" || echo "host")"
printf "=========================================================\n\n"

# Stage 1 & 2: Boundary & Git Author Identity
CURRENT_STAGE="Stages 1-2: Git Author & Inner/Outer Boundary Check"
CURRENT_LOG="${LOG_DIR}/01-boundary.log"
printf "[Stages 1-2] Boundary & Git author verification... "
"${SCRIPT_DIR}/check-boundary.sh" "${TARGET_DIR}" > "${CURRENT_LOG}" 2>&1
printf "\033[0;32mPASS\033[0m\n"

RUST_STATUS="SKIPPED"
WASM_STATUS="SKIPPED"
WEB_STATUS="SKIPPED"

# Stage 3: Rust Quality Gate (inside INNER_DIR)
if [[ "${RUN_RUST}" == "true" && -n "${RUST_MANIFEST}" ]]; then
  CURRENT_STAGE="Stage 3a: Inner Rust fmt, clippy (-D warnings), cargo test"
  CURRENT_LOG="${LOG_DIR}/02-rust.log"
  printf "[Stage 3a] Rust (${RUST_MANIFEST}) fmt + clippy + test... "
  : > "${CURRENT_LOG}"
  WORKSPACE_FLAG=()
  if grep -q '^\[workspace\]' "${TARGET_DIR}/${RUST_MANIFEST}"; then
    WORKSPACE_FLAG=("--workspace")
  fi
  run_in_env "${ACTIVE_INNER_REL}" cargo fmt --all -- --check >> "${CURRENT_LOG}" 2>&1
  run_in_env "${ACTIVE_INNER_REL}" cargo clippy "${WORKSPACE_FLAG[@]}" --all-targets -- -D warnings >> "${CURRENT_LOG}" 2>&1
  run_in_env "${ACTIVE_INNER_REL}" cargo test "${WORKSPACE_FLAG[@]}" >> "${CURRENT_LOG}" 2>&1
  RUST_PASSED="$(grep -E "test result: ok\." "${CURRENT_LOG}" | awk '{sum += $4} END {print sum+0}')"
  RUST_STATUS="PASS (${RUST_PASSED} tests)"
  printf "\033[0;32mPASS\033[0m (%s tests)\n" "${RUST_PASSED}"

  # Optional WASM check
  WASM_CRATES=()
  while IFS= read -r cargo_file; do
    pkg_name="$(sed -nE 's/^[[:space:]]*name[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "${cargo_file}" | head -n 1 || true)"
    [[ -n "${pkg_name}" ]] && WASM_CRATES+=("${pkg_name}")
  done < <(find "${INNER_ROOT}" -maxdepth 4 -path '*wasm*/Cargo.toml' 2>/dev/null || true)

  if [[ ${#WASM_CRATES[@]} -gt 0 ]]; then
    CURRENT_STAGE="Stage 3b: Browser WASM SIMD128 Check"
    CURRENT_LOG="${LOG_DIR}/02b-wasm.log"
    : > "${CURRENT_LOG}"
    for wc in "${WASM_CRATES[@]}"; do
      printf "[Stage 3b] Checking wasm32-unknown-unknown (%s)... " "${wc}"
      run_in_env "${ACTIVE_INNER_REL}" cargo clippy --target wasm32-unknown-unknown -p "${wc}" -- -D warnings >> "${CURRENT_LOG}" 2>&1
    done
    WASM_STATUS="PASS (${WASM_CRATES[*]})"
    printf "\033[0;32mPASS\033[0m\n"
  fi
fi

# Stage 4: Web Frontend Gate
if [[ "${RUN_WEB}" == "true" && -n "${WEB_REL}" ]]; then
  CURRENT_STAGE="Stage 4: Web TypeScript, Biome, Vitest & Vite Bundle (${WEB_REL})"
  CURRENT_LOG="${LOG_DIR}/03-web.log"

  if [[ "${USE_CONTAINER}" == "false" ]] && { ! command -v npm >/dev/null 2>&1 || [[ ! -d "${TARGET_DIR}/${WEB_REL}/node_modules" ]]; }; then
    if [[ "${WEB_EXPLICIT}" == "true" ]]; then
      echo "[Stage 4] ERROR: --web-only requested, but host lacks 'npm' or '${WEB_REL}/node_modules'." >&2
      exit 1
    else
      WEB_STATUS="SKIPPED (no host npm or ${WEB_REL}/node_modules)"
      printf "[Stage 4] Web UI... \033[0;33mSKIP\033[0m (no host npm or %s/node_modules)\n" "${WEB_REL}"
    fi
  else
    printf "[Stage 4] Web UI (%s) typecheck + lint + vitest + build... " "${WEB_REL}"
    WEB_CMD="if [ ! -d node_modules ]; then npm install --no-audit --no-fund; fi"
    if grep -q '"typecheck"' "${TARGET_DIR}/${WEB_REL}/package.json"; then
      WEB_CMD="${WEB_CMD} && npm run typecheck"
    else
      WEB_CMD="${WEB_CMD} && npx tsc --noEmit"
    fi
    if [[ -x "${TARGET_DIR}/${WEB_REL}/node_modules/.bin/biome" ]] || [[ "${USE_CONTAINER}" == "true" ]]; then
      WEB_CMD="${WEB_CMD} && npx --no-install biome check src tests e2e"
    fi
    WEB_CMD="${WEB_CMD} && npm test && npm run build"
    run_in_env "${WEB_REL}" sh -c "${WEB_CMD}" > "${CURRENT_LOG}" 2>&1
    WEB_STATUS="PASS"
    printf "\033[0;32mPASS\033[0m\n"
  fi
fi

ELAPSED=$(( $(date +%s) - START_TIME ))
OUTER_SHA="$(git -C "${TARGET_DIR}" rev-parse --short HEAD 2>/dev/null || echo "UNCOMMITTED")"
INNER_SHA="N/A"
if [[ -n "${ACTIVE_INNER_REL}" && -e "${INNER_ROOT}/.git" ]]; then
  INNER_SHA="$(git -C "${INNER_ROOT}" rev-parse --short HEAD 2>/dev/null || echo "UNCOMMITTED")"
fi

cat > "${RECEIPT_FILE}" <<EOF
================================================================================
DETERMINISTIC GATE RECEIPT (${PROJECT_NAME})
================================================================================
Timestamp     : $(date -Iseconds)
Worktree      : ${TARGET_DIR}
Outer Commit  : ${OUTER_SHA}
Inner Commit  : ${INNER_SHA} (${ACTIVE_INNER_REL:-none})
Execution Env : $([[ "${USE_CONTAINER}" == "true" ]] && echo "container (${CONTAINER_IMAGE})" || echo "host")
Mode          : ${MODE}
Duration      : ${ELAPSED}s
Exit Code     : 0

Stage Summary:
  - Boundary & Git Author : PASS
  - Rust (${RUST_MANIFEST:-none}) : ${RUST_STATUS}
  - WASM SIMD128          : ${WASM_STATUS}
  - Web (${WEB_REL:-none}) : ${WEB_STATUS}

Logs Directory: ${LOG_DIR}
================================================================================
EOF

printf "\n=========================================================\n"
printf "  \033[0;32mPRE-PUSH GATE PASSED\033[0m (%ds)\n" "${ELAPSED}"
printf "  Receipt: %s/latest/receipt.txt\n" "${LOG_ROOT}"
printf "=========================================================\n"
