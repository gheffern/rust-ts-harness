#!/usr/bin/env bash
# ==============================================================================
# Scoped & Changed-Only Test Runner (scripts/run-test.sh)
# ==============================================================================
# Runs scoped or full-suite tests inside the inner repository (INNER_DIR or
# template fallback):
#   1. Rust workspace/crate (Cargo.toml inside INNER_DIR)
#   2. Optional wasm32-unknown-unknown crates (*wasm*/Cargo.toml)
#   3. Web Frontend (auto-detected web/, frontend/, or root package.json)
#
# Defaults to native host execution (--container opts into podman).
# Serializes via scripts/with-cpu-lock.sh.
# ==============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_WORKTREE="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET_DIR="${TARGET_DIR:-${DEFAULT_WORKTREE}}"

MODE="auto" # auto | rust | wasm | web | all
PACKAGES=()
TEST_FILTER=""
CHANGED_MODE=false
USE_CONTAINER=false
RUN_LINT=true
PROPTEST_CASES_VAL="${PROPTEST_CASES:-}"
EXTRA_ARGS=()
POSITIONAL=()

usage() {
  cat <<EOF
Usage: $0 [options] [target/path] [-- <extra args...>]

Options:
  -c, --changed            Detect changed files in inner repo and run affected suites
  -p, --package <crate>    Run Rust tests for a specific crate in the inner repo
  -r, --rust               Run Rust workspace tests in the inner repo
  -w, --wasm               Verify wasm32-unknown-unknown clippy for *wasm* crates (if present)
  -f, --web, --frontend    Run Web typecheck, Biome lint, and Vitest suite
  -a, --all                Run all suites (Rust + optional WASM + Web)
      --lint               Run cargo fmt --check & cargo clippy --all-targets -- -D warnings (default: on)
      --no-lint            Skip cargo fmt --check & cargo clippy pre-checks
      --proptest-cases <N> Set PROPTEST_CASES=<N>
      --deep               Shorthand for --proptest-cases 10000
  -t, --test <filter>      Filter tests by function/test name substring
  -C, --dir <path>         Target repository or worktree directory (default: ${DEFAULT_WORKTREE})
      --container          Run inside podman container (CONTAINER_IMAGE from harness.env)
      --host               Run directly on host (default)
  -- <args...>             Forward raw trailing arguments to cargo test / vitest
  -h, --help               Show this help message
EOF
}

ORIG_ARGS=("$@")

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--changed|--related) CHANGED_MODE=true; shift ;;
    -p|--package)
      IFS=',' read -r -a split_pkgs <<< "$2"
      for pkg in "${split_pkgs[@]}"; do
        [[ -n "${pkg}" ]] && PACKAGES+=("${pkg}")
      done
      shift 2
      ;;
    -r|--rust) MODE="rust"; shift ;;
    -w|--wasm) MODE="wasm"; shift ;;
    -f|--web|--frontend) MODE="web"; shift ;;
    -a|--all) MODE="all"; shift ;;
    --lint) RUN_LINT=true; shift ;;
    --no-lint) RUN_LINT=false; shift ;;
    --proptest-cases) PROPTEST_CASES_VAL="$2"; shift 2 ;;
    --deep) PROPTEST_CASES_VAL="10000"; shift ;;
    -t|--test) TEST_FILTER="$2"; shift 2 ;;
    -C|--dir) TARGET_DIR="$2"; shift 2 ;;
    --container) USE_CONTAINER=true; shift ;;
    --host) USE_CONTAINER=false; shift ;;
    --) shift; EXTRA_ARGS+=("$@"); break ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ -d "$1" ]]; then
        TARGET_DIR="$1"
      else
        POSITIONAL+=("$1")
      fi
      shift
      ;;
  esac
done

TARGET_DIR="$(cd "${TARGET_DIR}" && pwd)"
if [[ "${TARGET_DIR}" == /tmp/* ]]; then
  echo "[run-test] ERROR: Worktree '${TARGET_DIR}' is on /tmp (RAM-backed tmpfs)." >&2
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

# Resolve active inner directory
ACTIVE_INNER_REL=""
if [[ -d "${TARGET_DIR}/${INNER_DIR}" ]]; then
  ACTIVE_INNER_REL="${INNER_DIR}"
elif [[ -d "${TARGET_DIR}/${TEMPLATE_INNER_DIR}" ]]; then
  ACTIVE_INNER_REL="${TEMPLATE_INNER_DIR}"
else
  echo "[run-test] ERROR: Neither '${INNER_DIR}/' nor '${TEMPLATE_INNER_DIR}/' exists in ${TARGET_DIR}." >&2
  exit 1
fi

INNER_ROOT="${TARGET_DIR}/${ACTIVE_INNER_REL}"
RUST_MANIFEST=""
[[ -f "${INNER_ROOT}/Cargo.toml" ]] && RUST_MANIFEST="${ACTIVE_INNER_REL}/Cargo.toml"

WEB_REL=""
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

if [[ "${HARNESS_CPU_LOCK_HELD:-0}" != "1" ]] && [[ -x "${SCRIPT_DIR}/with-cpu-lock.sh" ]]; then
  exec "${SCRIPT_DIR}/with-cpu-lock.sh" test "$0" "${ORIG_ARGS[@]}"
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_ROOT="/tmp/${PROJECT_SLUG}-test-logs"
LOG_DIR="${LOG_ROOT}/${TIMESTAMP}"
mkdir -p "${LOG_DIR}"
ln -sfn "${TIMESTAMP}" "${LOG_ROOT}/latest"
find "${LOG_ROOT}" -mindepth 1 -maxdepth 1 -type d -name '20[0-9][0-9]*' | sort -r | tail -n +11 | xargs -r rm -rf

CURRENT_STAGE="Initialization"
CURRENT_LOG=""

on_error() {
  local exit_code="${1:-$?}"
  [[ "${exit_code}" -eq 0 ]] && exit_code=1
  printf "\n\033[0;31m[TEST FAILED] %s (Exit Code: %d)\033[0m\n" "${CURRENT_STAGE}" "${exit_code}" >&2
  if [[ -n "${CURRENT_LOG}" && -f "${CURRENT_LOG}" ]]; then
    printf "=== Last 40 lines of %s ===\n" "${CURRENT_LOG}" >&2
    tail -n 40 "${CURRENT_LOG}" >&2
    printf "=== End of error snippet (Full log: %s) ===\n\n" "${CURRENT_LOG}" >&2
  fi
  exit "${exit_code}"
}
trap 'on_error' ERR

if [[ ${#POSITIONAL[@]} -gt 0 && "${MODE}" == "auto" && ${#PACKAGES[@]} -eq 0 ]]; then
  first_pos="${POSITIONAL[0]}"
  if [[ "${first_pos}" == *web/* || "${first_pos}" == *frontend/* || "${first_pos}" == *.ts || "${first_pos}" == *.tsx ]]; then
    MODE="web"
  else
    PACKAGES+=("${first_pos}")
  fi
fi

WASM_CRATES=()
while IFS= read -r cargo_file; do
  pkg_name="$(sed -nE 's/^[[:space:]]*name[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "${cargo_file}" | head -n 1 || true)"
  [[ -n "${pkg_name}" ]] && WASM_CRATES+=("${pkg_name}")
done < <(find "${INNER_ROOT}" -maxdepth 4 -path '*wasm*/Cargo.toml' 2>/dev/null || true)

is_wasm_crate() {
  local target="$1"
  for c in "${WASM_CRATES[@]:-}"; do
    [[ "${c}" == "${target}" ]] && return 0
  done
  return 1
}

RUN_RUST=false
RUN_WASM=false
RUN_WEB=false
WEB_EXPLICIT=false
TARGET_CRATES=()

if [[ ${#PACKAGES[@]} -gt 0 ]]; then
  RUN_RUST=true
  for pkg in "${PACKAGES[@]}"; do
    TARGET_CRATES+=("${pkg}")
    if is_wasm_crate "${pkg}"; then
      RUN_WASM=true
    fi
  done
elif [[ "${CHANGED_MODE}" == "true" ]]; then
  INNER_CHANGED=""
  if [[ -e "${INNER_ROOT}/.git" ]]; then
    INNER_CHANGED="$(git -C "${INNER_ROOT}" diff --name-only HEAD 2>/dev/null || true)"
    [[ -z "${INNER_CHANGED}" ]] && INNER_CHANGED="$(git -C "${INNER_ROOT}" status --porcelain 2>/dev/null | awk '{print $2}' || true)"
  else
    INNER_CHANGED="$(git -C "${TARGET_DIR}" diff --name-only HEAD -- "${ACTIVE_INNER_REL}" 2>/dev/null || true)"
  fi

  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if [[ "$f" =~ (^|/)(web|frontend)/ || "$f" =~ \.(ts|tsx|js|jsx|css|html)$ ]]; then
      RUN_WEB=true
    elif [[ "$f" =~ wasm ]]; then
      RUN_RUST=true
      RUN_WASM=true
    else
      RUN_RUST=true
    fi
  done <<< "${INNER_CHANGED}"

  if [[ "${RUN_RUST}" == "false" && "${RUN_WASM}" == "false" && "${RUN_WEB}" == "false" ]]; then
    RUN_RUST=true
    RUN_WEB=true
  fi
else
  case "${MODE}" in
    rust) RUN_RUST=true ;;
    wasm) RUN_WASM=true ;;
    web) RUN_WEB=true; WEB_EXPLICIT=true ;;
    all|auto)
      [[ -n "${RUST_MANIFEST}" ]] && RUN_RUST=true
      [[ ${#WASM_CRATES[@]} -gt 0 ]] && RUN_WASM=true
      [[ -n "${WEB_REL}" ]] && RUN_WEB=true
      ;;
  esac
fi

if [[ "${USE_CONTAINER}" == "true" ]]; then
  if [[ -f "/.dockerenv" ]] || [[ -f "/run/.containerenv" ]]; then
    USE_CONTAINER=false
  elif ! command -v podman >/dev/null 2>&1; then
    echo "[run-test] ERROR: --container requested but 'podman' is not installed." >&2
    exit 1
  else
    "${SCRIPT_DIR}/build-toolchain.sh" --if-missing
  fi
fi

run_in_env() {
  local work_subdir="$1"
  shift
  local extra_env_args=()
  [[ -n "${PROPTEST_CASES_VAL}" ]] && extra_env_args+=(-e "PROPTEST_CASES=${PROPTEST_CASES_VAL}")

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
      "${extra_env_args[@]}" \
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
      if [[ -n "${PROPTEST_CASES_VAL}" ]]; then
        export PROPTEST_CASES="${PROPTEST_CASES_VAL}"
      fi
      "$@"
    )
  fi
}

printf "\n=========================================================\n"
printf "  %s Scoped Test Runner\n" "${PROJECT_NAME}"
printf "  Inner Repo    : %s\n" "${ACTIVE_INNER_REL}"
printf "  Execution Env : %s\n" "$([[ "${USE_CONTAINER}" == "true" ]] && echo "container (${CONTAINER_IMAGE})" || echo "host")"
printf "  Log Directory : %s (latest -> %s/latest)\n" "${LOG_DIR}" "${LOG_ROOT}"
printf "=========================================================\n\n"

START_TIME="$(date +%s)"

# 1. Rust Tests
if [[ "${RUN_RUST}" == "true" ]]; then
  if [[ -z "${RUST_MANIFEST}" ]]; then
    printf "[Rust] \033[0;33mSKIP\033[0m (no %s/Cargo.toml found)\n" "${ACTIVE_INNER_REL}"
  else
    CURRENT_STAGE="Tier 1: Rust Tests (${RUST_MANIFEST})"
    CURRENT_LOG="${LOG_DIR}/01-rust.log"
    PKG_FLAGS=()
    if [[ ${#TARGET_CRATES[@]} -gt 0 ]]; then
      for c in "${TARGET_CRATES[@]}"; do
        PKG_FLAGS+=("-p" "${c}")
      done
      printf "[Rust] Testing crate(s): %s... " "${TARGET_CRATES[*]}"
    else
      if grep -q '^\[workspace\]' "${TARGET_DIR}/${RUST_MANIFEST}"; then
        PKG_FLAGS+=("--workspace")
      fi
      printf "[Rust] Testing %s... " "${RUST_MANIFEST}"
    fi

    : > "${CURRENT_LOG}"
    if [[ "${RUN_LINT}" == "true" && -z "${TEST_FILTER}" ]]; then
      run_in_env "${ACTIVE_INNER_REL}" cargo fmt --all -- --check >> "${CURRENT_LOG}" 2>&1 || on_error $?
      run_in_env "${ACTIVE_INNER_REL}" cargo clippy "${PKG_FLAGS[@]}" --all-targets -- -D warnings >> "${CURRENT_LOG}" 2>&1 || on_error $?
    fi

    CARGO_ARGS=("cargo" "test" "${PKG_FLAGS[@]}")
    [[ -n "${TEST_FILTER}" ]] && CARGO_ARGS+=("${TEST_FILTER}")
    [[ ${#EXTRA_ARGS[@]} -gt 0 ]] && CARGO_ARGS+=("--" "${EXTRA_ARGS[@]}")

    run_in_env "${ACTIVE_INNER_REL}" "${CARGO_ARGS[@]}" >> "${CURRENT_LOG}" 2>&1 || on_error $?
    RUST_PASSED="$(grep -E "test result: ok\." "${CURRENT_LOG}" | awk '{sum += $4} END {print sum+0}')"
    printf "\033[0;32mPASS\033[0m (%s tests passed)\n" "${RUST_PASSED}"
  fi
fi

# 2. Optional WASM Target Check
if [[ "${RUN_WASM}" == "true" ]]; then
  if [[ ${#WASM_CRATES[@]} -eq 0 ]]; then
    printf "[WASM SIMD128] \033[0;33mSKIP\033[0m (no *wasm* crate found in %s)\n" "${ACTIVE_INNER_REL}"
  else
    CURRENT_STAGE="Tier 2: Browser WASM Check (wasm32-unknown-unknown)"
    CURRENT_LOG="${LOG_DIR}/02-wasm-check.log"
    : > "${CURRENT_LOG}"
    for wc in "${WASM_CRATES[@]}"; do
      printf "[WASM SIMD128] Checking wasm32-unknown-unknown (%s)... " "${wc}"
      run_in_env "${ACTIVE_INNER_REL}" cargo clippy --target wasm32-unknown-unknown -p "${wc}" -- -D warnings >> "${CURRENT_LOG}" 2>&1 || on_error $?
      printf "\033[0;32mPASS\033[0m\n"
    done
  fi
fi

# 3. Web Frontend Tests
if [[ "${RUN_WEB}" == "true" ]]; then
  if [[ -z "${WEB_REL}" ]]; then
    printf "[Web UI] \033[0;33mSKIP\033[0m (no package.json found in %s)\n" "${ACTIVE_INNER_REL}"
  else
    CURRENT_STAGE="Tier 3: Web Typecheck, Biome & Vitest (${WEB_REL})"
    CURRENT_LOG="${LOG_DIR}/03-web-vitest.log"

    if [[ "${USE_CONTAINER}" == "false" ]] && { ! command -v npm >/dev/null 2>&1 || [[ ! -d "${TARGET_DIR}/${WEB_REL}/node_modules" ]]; }; then
      if [[ "${WEB_EXPLICIT}" == "true" ]]; then
        echo "[Web UI] ERROR: web tests requested, but host lacks 'npm' or '${WEB_REL}/node_modules'." >&2
        echo "  Run 'cd ${WEB_REL} && npm install' on a Node/npm host or pass '--container'." >&2
        exit 1
      else
        printf "[Web UI] \033[0;33mSKIP\033[0m (host lacks npm or %s/node_modules; run 'cd %s && npm install' or pass '--container')\n" "${WEB_REL}" "${WEB_REL}"
      fi
    else
      printf "[Web UI] Running typecheck & vitest in %s... " "${WEB_REL}"
      VITEST_CMD="if [ ! -d node_modules ]; then npm install --no-audit --no-fund; fi"
      if grep -q '"typecheck"' "${TARGET_DIR}/${WEB_REL}/package.json"; then
        VITEST_CMD="${VITEST_CMD} && npm run typecheck"
      else
        VITEST_CMD="${VITEST_CMD} && npx tsc --noEmit"
      fi
      if [[ -x "${TARGET_DIR}/${WEB_REL}/node_modules/.bin/biome" ]] || [[ "${USE_CONTAINER}" == "true" ]]; then
        VITEST_CMD="${VITEST_CMD} && npx --no-install biome check src tests e2e"
      fi
      VITEST_CMD="${VITEST_CMD} && npm test"
      if [[ -n "${TEST_FILTER}" ]]; then
        VITEST_CMD="${VITEST_CMD} -- -t '${TEST_FILTER}'"
      fi
      run_in_env "${WEB_REL}" sh -c "${VITEST_CMD}" > "${CURRENT_LOG}" 2>&1 || on_error $?
      printf "\033[0;32mPASS\033[0m\n"
    fi
  fi
fi

ELAPSED=$(( $(date +%s) - START_TIME ))
printf "\n=========================================================\n"
printf "  \033[0;32mALL SELECTED TEST SUITES PASSED\033[0m (%ds)\n" "${ELAPSED}"
printf "  Logs: %s/latest/\n" "${LOG_ROOT}"
printf "=========================================================\n"
