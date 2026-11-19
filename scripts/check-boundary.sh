#!/usr/bin/env bash
# ==============================================================================
# Clean-Room Inner/Outer Boundary & Git Hygiene Verifier (check-boundary.sh)
# ==============================================================================
# Enforces:
#   1. INV-BOUNDARY-1: Outer harness repo contains no project code outside
#      templates/ (project code lives strictly inside INNER_DIR).
#   2. INV-BOUNDARY-2: Inner repository (INNER_DIR) remains 100% free of
#      agentic files (AGENTS.md, .agents/), harness config (harness.env),
#      internal docs links (docs/internal/), or host paths (/home/<user>/).
#   3. Optional INNER_LICENSE invariant (harness.env).
#   4. Git commit author identity across outer and inner repositories.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
cd "${TARGET_DIR}"

if [[ -f "${TARGET_DIR}/scripts/harness.env" ]]; then
  # shellcheck source=harness.env
  source "${TARGET_DIR}/scripts/harness.env"
elif [[ -f "${SCRIPT_DIR}/harness.env" ]]; then
  # shellcheck source=harness.env
  source "${SCRIPT_DIR}/harness.env"
fi

INNER_DIR="${INNER_DIR:-app}"
TEMPLATE_INNER_DIR="${TEMPLATE_INNER_DIR:-templates/inner-project}"
GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-$(git config user.name 2>/dev/null || echo '')}"
GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-$(git config user.email 2>/dev/null || echo '')}"
INNER_LICENSE="${INNER_LICENSE:-}"

FAILURES=0

pass() {
  printf "  \033[0;32m[PASS]\033[0m %s\n" "$1"
}

info() {
  printf "  \033[0;34m[INFO]\033[0m %s\n" "$1"
}

fail() {
  printf "  \033[0;31m[FAIL]\033[0m %s\n" "$1" >&2
  FAILURES=$((FAILURES + 1))
}

echo "=== Checking Harness / Inner Repo Boundary (${TARGET_DIR}) ==="

# 1. INV-BOUNDARY-1: Outer harness stays code-free (outside INNER_DIR and templates/)
OUTER_CODE_LEAKS=()
for p in Cargo.toml package.json crates src web; do
  if [[ -e "${TARGET_DIR}/${p}" ]]; then
    OUTER_CODE_LEAKS+=("${p}")
  fi
done
if [[ ${#OUTER_CODE_LEAKS[@]} -gt 0 ]]; then
  fail "INV-BOUNDARY-1 violation: project code artifact(s) found in outer harness repo: ${OUTER_CODE_LEAKS[*]}"
else
  pass "INV-BOUNDARY-1: Outer harness repo contains no project code."
fi

# 2. Resolve active inner directory (materialized INNER_DIR or uninitialized template)
ACTIVE_INNER=""
TEMPLATE_MODE=false
if [[ -d "${TARGET_DIR}/${INNER_DIR}" ]]; then
  ACTIVE_INNER="${TARGET_DIR}/${INNER_DIR}"
  if [[ -e "${ACTIVE_INNER}/.git" ]]; then
    pass "Inner repository '${INNER_DIR}/' is present and git-tracked."
  else
    info "Inner directory '${INNER_DIR}/' exists without .git (not yet a submodule)."
  fi
elif [[ -d "${TARGET_DIR}/${TEMPLATE_INNER_DIR}" ]]; then
  ACTIVE_INNER="${TARGET_DIR}/${TEMPLATE_INNER_DIR}"
  TEMPLATE_MODE=true
  info "Template mode: '${INNER_DIR}/' not yet initialized; checking '${TEMPLATE_INNER_DIR}/'."
else
  fail "Neither '${INNER_DIR}/' nor '${TEMPLATE_INNER_DIR}/' exists in ${TARGET_DIR}."
fi

# 3. INV-BOUNDARY-2: Zero agentic files or developer host paths in inner repo
if [[ -n "${ACTIVE_INNER}" ]]; then
  if [[ -e "${ACTIVE_INNER}/AGENTS.md" || -d "${ACTIVE_INNER}/.agents" ]]; then
    fail "INV-BOUNDARY-2 violation: AGENTS.md or .agents/ found inside inner repo."
  fi
  LEAK_MATCHES="$(grep -rnE "AGENTS\.md|\.agents/|harness\.env|docs/internal/|/home/[a-zA-Z0-9._-]+/" \
    "${ACTIVE_INNER}" \
    --exclude-dir=target --exclude-dir=node_modules --exclude-dir=.git --exclude=.git 2>/dev/null || true)"
  if [[ -n "${LEAK_MATCHES}" ]]; then
    fail "INV-BOUNDARY-2 violation: agentic or host-path reference leaked into inner repo:"
    echo "${LEAK_MATCHES}" >&2
  else
    pass "INV-BOUNDARY-2: Zero agentic or host-path leaks inside inner repo."
  fi
fi

# 4. Optional inner license check
if [[ -n "${INNER_LICENSE}" && -n "${ACTIVE_INNER}" && -f "${ACTIVE_INNER}/Cargo.toml" ]]; then
  if grep -q "license = \"${INNER_LICENSE}\"" "${ACTIVE_INNER}/Cargo.toml"; then
    pass "Inner Cargo.toml declares license = \"${INNER_LICENSE}\"."
  else
    fail "Inner Cargo.toml missing expected license = \"${INNER_LICENSE}\"."
  fi
fi

# 5. Git commit author identity checks
if [[ -n "${GIT_AUTHOR_NAME}" && -n "${GIT_AUTHOR_EMAIL}" ]]; then
  EXPECTED_AUTHOR="${GIT_AUTHOR_NAME} <${GIT_AUTHOR_EMAIL}>"
  if git -C "${TARGET_DIR}" rev-parse --verify HEAD >/dev/null 2>&1; then
    OUTER_BAD_AUTHORS="$(git -C "${TARGET_DIR}" log -n 20 --format="%an <%ae>" 2>/dev/null | grep -v "^${EXPECTED_AUTHOR}$" || true)"
    if [[ -n "${OUTER_BAD_AUTHORS}" ]]; then
      fail "Outer repository contains commit(s) not authored by '${EXPECTED_AUTHOR}': ${OUTER_BAD_AUTHORS}"
    else
      pass "Outer repository commit authors verified (${EXPECTED_AUTHOR})."
    fi
  else
    info "Outer repository has no commits yet; skipping outer author history check."
  fi

  if [[ "${TEMPLATE_MODE}" == "false" && -n "${ACTIVE_INNER}" && -e "${ACTIVE_INNER}/.git" ]]; then
    if git -C "${ACTIVE_INNER}" rev-parse --verify HEAD >/dev/null 2>&1; then
      INNER_BAD_AUTHORS="$(git -C "${ACTIVE_INNER}" log -n 20 --format="%an <%ae>" 2>/dev/null | grep -v "^${EXPECTED_AUTHOR}$" || true)"
      if [[ -n "${INNER_BAD_AUTHORS}" ]]; then
        fail "Inner repository contains commit(s) not authored by '${EXPECTED_AUTHOR}': ${INNER_BAD_AUTHORS}"
      else
        pass "Inner repository commit authors verified (${EXPECTED_AUTHOR})."
      fi
    fi
  fi
fi

if [[ "${FAILURES}" -gt 0 ]]; then
  echo "Boundary verification FAILED with ${FAILURES} error(s)." >&2
  exit 1
fi

echo "=== Boundary Verification PASSED ==="
