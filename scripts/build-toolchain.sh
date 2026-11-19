#!/usr/bin/env bash
# ==============================================================================
# Build Harness Toolchain Container Image (scripts/build-toolchain.sh)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${REPO_ROOT}/scripts/harness.env" ]]; then
  # shellcheck source=harness.env
  source "${REPO_ROOT}/scripts/harness.env"
fi

CONTAINER_IMAGE="${CONTAINER_IMAGE:-localhost/rust-ts-harness-toolchain:latest}"
CONTAINERFILE="${REPO_ROOT}/docker/toolchain.Containerfile"
IF_MISSING=false
FRESH=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --if-missing) IF_MISSING=true; shift ;;
    --fresh) FRESH=true; shift ;;
    -h|--help)
      echo "Usage: $0 [--if-missing] [--fresh]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if command -v podman >/dev/null 2>&1; then
  RUNTIME="podman"
elif command -v docker >/dev/null 2>&1; then
  RUNTIME="docker"
else
  echo "[build-toolchain] ERROR: Neither 'podman' nor 'docker' is installed." >&2
  exit 1
fi

if [[ "${IF_MISSING}" == "true" ]] && "${RUNTIME}" image exists "${CONTAINER_IMAGE}" >/dev/null 2>&1; then
  exit 0
fi

if [[ ! -f "${CONTAINERFILE}" ]]; then
  echo "[build-toolchain] ERROR: Missing ${CONTAINERFILE}." >&2
  exit 1
fi

BUILD_ARGS=(-t "${CONTAINER_IMAGE}" -f "${CONTAINERFILE}")
if [[ "${FRESH}" == "true" ]]; then
  BUILD_ARGS+=(--pull --no-cache)
fi

echo "[build-toolchain] Building ${CONTAINER_IMAGE} from ${CONTAINERFILE}..."
"${RUNTIME}" build "${BUILD_ARGS[@]}" "${REPO_ROOT}/docker"
