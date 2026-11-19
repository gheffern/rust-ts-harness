#!/usr/bin/env bash
# ==============================================================================
# Harness Bootstrapper (scripts/init.sh)
# ==============================================================================
# Configures a fresh clone/copy of rust-ts-harness into a concrete project:
#   - Updates scripts/harness.env
#   - Initializes or attaches the inner code repository at INNER_DIR (default: app/):
#       * Default: materializes templates/inner-project/ into a local git repo +
#         optional bare upstream (../<slug>-<inner-dir>.git) and adds as submodule
#       * With --inner-repo <url-or-path>: attaches an existing repo as submodule
#   - Leaves zero project code in the outer harness repository
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROJECT_NAME=""
INNER_DIR="app"
INNER_REPO=""
LOCAL_UPSTREAM=""
NO_LOCAL_UPSTREAM=false
AUTHOR_NAME="$(git -C "${REPO_ROOT}" config user.name 2>/dev/null || echo 'Graham Heffern')"
AUTHOR_EMAIL="$(git -C "${REPO_ROOT}" config user.email 2>/dev/null || echo 'gheffern@gmail.com')"
KEEP_TEMPLATES=false
DRY_RUN=false

usage() {
  cat <<EOF
Usage: $0 --name <project-slug> [options]

Options:
  --name <slug>              Project name / slug (e.g., my-app) [REQUIRED]
  --inner-dir <dir>          Inner submodule path relative to root (default: app)
  --inner-repo <url|path>    Attach an existing git repository as the inner submodule
  --local-upstream <path>    Path for local bare upstream when creating default inner repo
                             (default: ../<slug>-<inner-dir>.git)
  --no-local-upstream        Initialize inner repo without a local bare upstream repo
  --author-name <name>       Git author name (default: ${AUTHOR_NAME})
  --author-email <email>     Git author email (default: ${AUTHOR_EMAIL})
  --keep-templates           Keep templates/ directory after initializing inner repo
  --dry-run                  Print planned actions without modifying files
  -h, --help                 Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) PROJECT_NAME="$2"; shift 2 ;;
    --inner-dir) INNER_DIR="$2"; shift 2 ;;
    --inner-repo) INNER_REPO="$2"; shift 2 ;;
    --local-upstream) LOCAL_UPSTREAM="$2"; shift 2 ;;
    --no-local-upstream) NO_LOCAL_UPSTREAM=true; shift ;;
    --author-name) AUTHOR_NAME="$2"; shift 2 ;;
    --author-email) AUTHOR_EMAIL="$2"; shift 2 ;;
    --keep-templates) KEEP_TEMPLATES=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "${PROJECT_NAME}" ]]; then
  echo "ERROR: --name <project-slug> is required." >&2
  usage
  exit 2
fi

if [[ ! "${PROJECT_NAME}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
  echo "ERROR: --name must match ^[a-zA-Z0-9][a-zA-Z0-9_-]*$" >&2
  exit 2
fi

if [[ "${REPO_ROOT}" == /tmp/* ]]; then
  echo "ERROR: Refusing to initialize inside /tmp." >&2
  exit 2
fi

PROJECT_SLUG="$(printf '%s' "${PROJECT_NAME}" | tr '[:upper:]_' '[:lower:]-')"
RUST_CRATE_PREFIX="$(printf '%s' "${PROJECT_SLUG}" | tr '-' '_')"
RUST_PKG_PREFIX="${PROJECT_SLUG}"

if [[ -z "${LOCAL_UPSTREAM}" && "${NO_LOCAL_UPSTREAM}" == "false" && -z "${INNER_REPO}" ]]; then
  LOCAL_UPSTREAM="$(cd "${REPO_ROOT}/.." && pwd)/${PROJECT_SLUG}-${INNER_DIR}.git"
fi

echo "=== Bootstrapping ${PROJECT_NAME} (${REPO_ROOT}) ==="
echo "  Project Slug   : ${PROJECT_SLUG}"
echo "  Inner Dir      : ${INNER_DIR}"
echo "  Inner Source   : ${INNER_REPO:-templates/inner-project (new Rust + TS repo)}"
echo "  Local Upstream : ${LOCAL_UPSTREAM:-none}"
echo "  Git Author     : ${AUTHOR_NAME} <${AUTHOR_EMAIL}>"

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "[Dry Run] No changes made."
  exit 0
fi

cd "${REPO_ROOT}"

if [[ -e "${REPO_ROOT}/${INNER_DIR}" ]]; then
  echo "ERROR: '${INNER_DIR}' already exists in ${REPO_ROOT}." >&2
  exit 1
fi

# 1. Configure git author locally
git config user.name "${AUTHOR_NAME}"
git config user.email "${AUTHOR_EMAIL}"

# 2. Materialize or attach inner submodule
if [[ -n "${INNER_REPO}" ]]; then
  git -c protocol.file.allow=always submodule add "${INNER_REPO}" "${INNER_DIR}"
  git -C "${REPO_ROOT}/${INNER_DIR}" config user.name "${AUTHOR_NAME}"
  git -C "${REPO_ROOT}/${INNER_DIR}" config user.email "${AUTHOR_EMAIL}"
else
  TMP_STAGE="${REPO_ROOT}/.init-inner-stage"
  rm -rf "${TMP_STAGE}"
  cp -a "${REPO_ROOT}/templates/inner-project" "${TMP_STAGE}"

  # Rename placeholder package/crate names in template inner project
  sed -i "s/app-core/${RUST_PKG_PREFIX}-core/g; s/app_core/${RUST_CRATE_PREFIX}_core/g" \
    "${TMP_STAGE}/Cargo.toml" \
    "${TMP_STAGE}/crates/core/Cargo.toml" \
    "${TMP_STAGE}/crates/server/Cargo.toml" \
    "${TMP_STAGE}/crates/server/src/main.rs"
  sed -i "s/app-server/${RUST_PKG_PREFIX}-server/g" \
    "${TMP_STAGE}/crates/server/Cargo.toml"
  sed -i "s/rust-ts-harness/${PROJECT_NAME}/g" \
    "${TMP_STAGE}/crates/server/src/main.rs" \
    "${TMP_STAGE}/web/package.json"

  if command -v cargo >/dev/null 2>&1; then
    cargo generate-lockfile --manifest-path "${TMP_STAGE}/Cargo.toml" --offline >/dev/null 2>&1 || true
  fi

  git -C "${TMP_STAGE}" init -b main >/dev/null
  git -C "${TMP_STAGE}" config user.name "${AUTHOR_NAME}"
  git -C "${TMP_STAGE}" config user.email "${AUTHOR_EMAIL}"
  git -C "${TMP_STAGE}" add .
  git -C "${TMP_STAGE}" commit --author="${AUTHOR_NAME} <${AUTHOR_EMAIL}>" -m "feat: initial ${PROJECT_SLUG} Rust + TS workspace" >/dev/null

  if [[ "${NO_LOCAL_UPSTREAM}" == "false" ]]; then
    if [[ -e "${LOCAL_UPSTREAM}" ]]; then
      echo "ERROR: Local upstream path '${LOCAL_UPSTREAM}' already exists." >&2
      rm -rf "${TMP_STAGE}"
      exit 1
    fi
    git clone --bare "${TMP_STAGE}" "${LOCAL_UPSTREAM}" >/dev/null
    rm -rf "${TMP_STAGE}"
    git -c protocol.file.allow=always submodule add "${LOCAL_UPSTREAM}" "${INNER_DIR}"
    git -C "${REPO_ROOT}/${INNER_DIR}" config user.name "${AUTHOR_NAME}"
    git -C "${REPO_ROOT}/${INNER_DIR}" config user.email "${AUTHOR_EMAIL}"
  else
    mv "${TMP_STAGE}" "${REPO_ROOT}/${INNER_DIR}"
  fi
fi

# 3. Write scripts/harness.env
cat > "${REPO_ROOT}/scripts/harness.env" <<EOF
# ==============================================================================
# Central Harness Configuration (sourced by scripts/*.sh)
# ==============================================================================
PROJECT_NAME="${PROJECT_NAME}"
PROJECT_SLUG="${PROJECT_SLUG}"

INNER_DIR="${INNER_DIR}"
TEMPLATE_INNER_DIR="templates/inner-project"
WEB_SUBDIR=""

GIT_AUTHOR_NAME="${AUTHOR_NAME}"
GIT_AUTHOR_EMAIL="${AUTHOR_EMAIL}"

INNER_LOCAL_UPSTREAM="${LOCAL_UPSTREAM}"

INNER_LICENSE=""

CONTAINER_IMAGE="localhost/rust-toolchain:latest"
PLAYWRIGHT_IMAGE="mcr.microsoft.com/playwright:v1.60.0-jammy"

E2E_BASE_URL="http://127.0.0.1:8080"
E2E_HEALTH_PATH="/api/v1/health"
EOF

# 4. Clean up templates/ unless --keep-templates
if [[ "${KEEP_TEMPLATES}" == "false" && -d "${REPO_ROOT}/templates" ]]; then
  rm -rf "${REPO_ROOT}/templates"
fi

echo "=== Bootstrap Complete ==="
echo "Next steps:"
echo "  1. Review scripts/harness.env and docs/internal/invariants.md"
echo "  2. Run ./scripts/run-pre-push.sh --all"
echo "  3. Commit your initialized project as ${AUTHOR_NAME} <${AUTHOR_EMAIL}>"
