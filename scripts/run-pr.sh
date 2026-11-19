#!/usr/bin/env bash
# ==============================================================================
# Submodule Sync & Pull Request Automation (scripts/run-pr.sh)
# ==============================================================================
# Dual-mode Git, Submodule & Pull Request automation:
#   1. Default Local Sync Mode (no external remote push):
#      - Verifies clean working trees in both INNER_DIR and outer repo
#      - Runs scripts/check-boundary.sh
#      - If INNER_LOCAL_UPSTREAM is set, pushes inner commits to that local path
#      - Optionally commits updated submodule pointer in outer repo (--commit-gitlink)
#   2. Remote Push / PR Mode (--push / --pr):
#      - Only runs when explicitly requested by the user
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_WORKTREE="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET_DIR="${TARGET_DIR:-${DEFAULT_WORKTREE}}"

PUSH_REMOTE=false
OPEN_PR=false
DRY_RUN=false
COMMIT_GITLINK=false
BASE_BRANCH="main"
TITLE=""
BODY=""
BODY_FILE=""
DRAFT=false

usage() {
  cat <<EOF
Usage: $0 [options]

Modes:
  (default)                Local Submodule & Boundary Sync only (never pushes to external remotes)
  --commit-gitlink         Automatically commit updated inner submodule pointer in outer repo
  --push                   Push current branch to origin after passing boundary checks
  --pr                     Push current branch and create/update a Pull Request via gh

Options:
  -C, --dir <path>         Target repository or worktree directory (default: ${DEFAULT_WORKTREE})
  -b, --base <branch>      Target base branch for PR (default: main)
  -t, --title <text>       Pull Request title (defaults to latest commit subject)
  -d, --body <text>        Pull Request body markdown
  -f, --body-file <path>   Read Pull Request body markdown from file
      --draft              Create Pull Request as Draft
      --dry-run            Preview actions without mutating remotes
  -h, --help               Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --commit-gitlink) COMMIT_GITLINK=true; shift ;;
    --push) PUSH_REMOTE=true; shift ;;
    --pr) PUSH_REMOTE=true; OPEN_PR=true; shift ;;
    -C|--dir) TARGET_DIR="$2"; shift 2 ;;
    -b|--base) BASE_BRANCH="$2"; shift 2 ;;
    -t|--title) TITLE="$2"; shift 2 ;;
    -d|--body) BODY="$2"; shift 2 ;;
    -f|--body-file) BODY_FILE="$2"; shift 2 ;;
    --draft) DRAFT=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

TARGET_DIR="$(cd "${TARGET_DIR}" && pwd)"
cd "${TARGET_DIR}"

if [[ -f "${TARGET_DIR}/scripts/harness.env" ]]; then
  # shellcheck source=harness.env
  source "${TARGET_DIR}/scripts/harness.env"
elif [[ -f "${SCRIPT_DIR}/harness.env" ]]; then
  # shellcheck source=harness.env
  source "${SCRIPT_DIR}/harness.env"
fi

PROJECT_NAME="${PROJECT_NAME:-rust-ts-harness}"
INNER_DIR="${INNER_DIR:-app}"
INNER_LOCAL_UPSTREAM="${INNER_LOCAL_UPSTREAM:-}"
GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-$(git config user.name 2>/dev/null || echo '')}"
GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-$(git config user.email 2>/dev/null || echo '')}"

printf "\n=========================================================\n"
printf "  %s Submodule & PR Workflow\n" "${PROJECT_NAME}"
printf "  Worktree : %s\n" "${TARGET_DIR}"
printf "  Mode     : %s\n" "$([[ "${OPEN_PR}" == "true" ]] && echo "Push + PR (--pr)" || ([[ "${PUSH_REMOTE}" == "true" ]] && echo "Push (--push)" || echo "Local Submodule & Boundary Sync (Safe Default)"))"
printf "=========================================================\n\n"

# 1. Verify clean working trees
if [[ -e "${TARGET_DIR}/${INNER_DIR}/.git" ]]; then
  INNER_DIRTY="$(git -C "${TARGET_DIR}/${INNER_DIR}" status --porcelain)"
  if [[ -n "${INNER_DIRTY}" ]]; then
    echo "ERROR: Inner submodule '${INNER_DIR}/' has uncommitted changes." >&2
    git -C "${TARGET_DIR}/${INNER_DIR}" status --short >&2
    exit 1
  fi
fi

OUTER_DIRTY_NON_SUBMODULE="$(git -C "${TARGET_DIR}" status --porcelain | grep -vE "^[ M?]{2} ${INNER_DIR}$" || true)"
if [[ -n "${OUTER_DIRTY_NON_SUBMODULE}" ]]; then
  echo "ERROR: Outer repository has uncommitted changes outside '${INNER_DIR}/'." >&2
  echo "${OUTER_DIRTY_NON_SUBMODULE}" >&2
  exit 1
fi

# 2. Boundary & author hygiene
"${SCRIPT_DIR}/check-boundary.sh" "${TARGET_DIR}"

# 3. Sync inner commits to local upstream if configured
if [[ -n "${INNER_LOCAL_UPSTREAM}" && -e "${TARGET_DIR}/${INNER_DIR}/.git" && -d "${INNER_LOCAL_UPSTREAM}" ]]; then
  INNER_BRANCH="$(git -C "${TARGET_DIR}/${INNER_DIR}" rev-parse --abbrev-ref HEAD)"
  echo "[Submodule Sync] Pushing ${INNER_DIR}/ (${INNER_BRANCH}) -> ${INNER_LOCAL_UPSTREAM}"
  if [[ "${DRY_RUN}" == "false" ]]; then
    git -C "${TARGET_DIR}/${INNER_DIR}" push "${INNER_LOCAL_UPSTREAM}" "HEAD:${INNER_BRANCH}"
  fi
fi

# 4. Handle updated inner gitlink in outer repo
SUBMODULE_DIFF="$(git -C "${TARGET_DIR}" diff --name-only -- "${INNER_DIR}" || true)"
if [[ -n "${SUBMODULE_DIFF}" ]]; then
  if [[ "${COMMIT_GITLINK}" == "true" && "${DRY_RUN}" == "false" ]]; then
    INNER_SHA="$(git -C "${TARGET_DIR}/${INNER_DIR}" rev-parse --short HEAD)"
    git -C "${TARGET_DIR}" add "${INNER_DIR}"
    if [[ -n "${GIT_AUTHOR_NAME}" && -n "${GIT_AUTHOR_EMAIL}" ]]; then
      git -C "${TARGET_DIR}" commit \
        --author="${GIT_AUTHOR_NAME} <${GIT_AUTHOR_EMAIL}>" \
        -m "chore(${INNER_DIR}): update submodule pointer to ${INNER_SHA}"
    else
      git -C "${TARGET_DIR}" commit -m "chore(${INNER_DIR}): update submodule pointer to ${INNER_SHA}"
    fi
    echo "[Submodule Sync] Committed updated ${INNER_DIR} gitlink (${INNER_SHA})."
  else
    echo "[Submodule Sync] NOTE: ${INNER_DIR} pointer changed in outer repo (pass --commit-gitlink to commit)."
  fi
fi

if [[ "${PUSH_REMOTE}" == "false" ]]; then
  echo "[Local Sync] Complete. No external remote was modified."
  exit 0
fi

# 5. Remote push (--push / --pr)
OUTER_BRANCH="$(git -C "${TARGET_DIR}" rev-parse --abbrev-ref HEAD)"
if [[ "${OUTER_BRANCH}" == "${BASE_BRANCH}" ]]; then
  echo "ERROR: Refusing to push/open PR directly from '${BASE_BRANCH}'. Use a feature branch." >&2
  exit 1
fi

if [[ "${DRY_RUN}" == "false" ]]; then
  git -C "${TARGET_DIR}" push -u origin "${OUTER_BRANCH}"
else
  echo "[Dry Run] Would push origin ${OUTER_BRANCH}"
fi

if [[ "${OPEN_PR}" == "true" ]]; then
  PR_TITLE="${TITLE:-$(git -C "${TARGET_DIR}" log -1 --format=%s)}"
  GH_ARGS=(pr create --base "${BASE_BRANCH}" --head "${OUTER_BRANCH}" --title "${PR_TITLE}")
  [[ "${DRAFT}" == "true" ]] && GH_ARGS+=(--draft)
  if [[ -n "${BODY_FILE}" ]]; then
    GH_ARGS+=(--body-file "${BODY_FILE}")
  elif [[ -n "${BODY}" ]]; then
    GH_ARGS+=(--body "${BODY}")
  else
    GH_ARGS+=(--fill)
  fi
  if [[ "${DRY_RUN}" == "false" ]]; then
    gh "${GH_ARGS[@]}"
  else
    echo "[Dry Run] Would run: gh ${GH_ARGS[*]}"
  fi
fi
