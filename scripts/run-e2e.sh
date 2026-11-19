#!/usr/bin/env bash
# ==============================================================================
# End-to-End Health & Playwright Verification Runner (scripts/run-e2e.sh)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_WORKTREE="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET_DIR="${TARGET_DIR:-${DEFAULT_WORKTREE}}"

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
BASE_URL="${APP_BASE_URL:-${E2E_BASE_URL:-http://127.0.0.1:8080}}"
HEALTH_PATH="${E2E_HEALTH_PATH:-/api/v1/health}"
PLAYWRIGHT_IMAGE="${PLAYWRIGHT_IMAGE:-mcr.microsoft.com/playwright:v1.60.0-jammy}"

RUN_HEALTH=true
RUN_PLAYWRIGHT=true
USE_CONTAINER=false
PW_EXTRA_ARGS=()
ORIG_ARGS=("$@")

usage() {
  cat <<EOF
Usage: $0 [options] [-- <playwright-args...>]

Options:
  -u, --url <url>          Target base URL (default: ${BASE_URL})
  -C, --dir <path>         Target repository or worktree directory (default: ${DEFAULT_WORKTREE})
      --health-only        Run only live HTTP health probe
      --playwright-only    Run only Playwright E2E suite
      --spec <file>        Run a specific Playwright spec file (e.g. e2e/smoke.spec.ts)
  -g, --grep <pattern>     Run only Playwright tests matching regex pattern
      --container          Run Playwright inside ${PLAYWRIGHT_IMAGE} via podman
      --host               Run Playwright on host (default)
  -h, --help               Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--url) BASE_URL="$2"; shift 2 ;;
    -C|--dir) TARGET_DIR="$2"; shift 2 ;;
    --health-only) RUN_HEALTH=true; RUN_PLAYWRIGHT=false; shift ;;
    --playwright-only) RUN_HEALTH=false; RUN_PLAYWRIGHT=true; shift ;;
    --spec) PW_EXTRA_ARGS+=("$2"); shift 2 ;;
    -g|--grep) PW_EXTRA_ARGS+=("--grep" "$2"); shift 2 ;;
    --container) USE_CONTAINER=true; shift ;;
    --host) USE_CONTAINER=false; shift ;;
    --) shift; PW_EXTRA_ARGS+=("$@"); break ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

TARGET_DIR="$(cd "${TARGET_DIR}" && pwd)"
if [[ "${TARGET_DIR}" == /tmp/* ]]; then
  echo "[run-e2e] ERROR: Worktree '${TARGET_DIR}' is on /tmp (RAM-backed tmpfs)." >&2
  exit 2
fi

ACTIVE_INNER_REL=""
if [[ -d "${TARGET_DIR}/${INNER_DIR}" ]]; then
  ACTIVE_INNER_REL="${INNER_DIR}"
elif [[ -d "${TARGET_DIR}/${TEMPLATE_INNER_DIR}" ]]; then
  ACTIVE_INNER_REL="${TEMPLATE_INNER_DIR}"
fi

INNER_ROOT="${TARGET_DIR}/${ACTIVE_INNER_REL}"
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
  exec "${SCRIPT_DIR}/with-cpu-lock.sh" e2e "$0" "${ORIG_ARGS[@]}"
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_ROOT="/tmp/${PROJECT_SLUG}-e2e-logs"
LOG_DIR="${LOG_ROOT}/${TIMESTAMP}"
mkdir -p "${LOG_DIR}"
ln -sfn "${TIMESTAMP}" "${LOG_ROOT}/latest"
find "${LOG_ROOT}" -mindepth 1 -maxdepth 1 -type d -name '20[0-9][0-9]*' | sort -r | tail -n +11 | xargs -r rm -rf

echo "=== ${PROJECT_NAME} E2E Audit (${BASE_URL}) ==="

if [[ "${RUN_HEALTH}" == "true" ]]; then
  printf "[Stage 1] Probing %s%s... " "${BASE_URL}" "${HEALTH_PATH}"
  curl -fsS --max-time 10 "${BASE_URL}${HEALTH_PATH}" > "${LOG_DIR}/health.json"
  printf "\033[0;32mPASS\033[0m\n"
fi

if [[ "${RUN_PLAYWRIGHT}" == "true" ]]; then
  if [[ -z "${WEB_REL}" ]]; then
    echo "[run-e2e] ERROR: Could not find web/package.json inside '${ACTIVE_INNER_REL}'." >&2
    exit 1
  fi
  echo "[Stage 2] Running Playwright suite in ${WEB_REL}..."
  if [[ "${USE_CONTAINER}" == "true" ]]; then
    podman run --rm --network host \
      --security-opt label=disable \
      -v "${TARGET_DIR}:/work:z" \
      -v "${LOG_DIR}:/out:z" \
      -e "APP_BASE_URL=${BASE_URL}" \
      -e "E2E_OUT_DIR=/out" \
      -w "/work/${WEB_REL}" \
      "${PLAYWRIGHT_IMAGE}" \
      npx playwright test -c e2e/playwright.config.ts "${PW_EXTRA_ARGS[@]}"
  else
    (
      cd "${TARGET_DIR}/${WEB_REL}"
      export APP_BASE_URL="${BASE_URL}"
      export E2E_OUT_DIR="${LOG_DIR}"
      npx playwright test -c e2e/playwright.config.ts "${PW_EXTRA_ARGS[@]}"
    )
  fi
fi

echo "=== E2E Audit PASSED (Logs: ${LOG_ROOT}/latest) ==="
