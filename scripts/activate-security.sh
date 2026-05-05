#!/usr/bin/env bash
set -euo pipefail

OWNER="${AGENT_ORCHESTRA_OWNER:-DUBSOpenHub}"
REPO="${AGENT_ORCHESTRA_REPO:-agent-orchestra}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required to activate repository security settings." >&2
  exit 1
fi

if ! gh auth status >/dev/null; then
  echo "GitHub auth is not valid. Run: gh auth login -h github.com" >&2
  exit 1
fi

enable_endpoint() {
  local path="$1"
  local label="$2"

  if gh api --method PUT "${path}" >/dev/null 2>&1; then
    echo "enabled: ${label}"
  else
    echo "skipped: ${label} (requires repo admin permissions or is unavailable)" >&2
  fi
}

enable_endpoint "/repos/${OWNER}/${REPO}/vulnerability-alerts" "Dependabot alerts"
enable_endpoint "/repos/${OWNER}/${REPO}/automated-security-fixes" "Dependabot security updates"
enable_endpoint "/repos/${OWNER}/${REPO}/private-vulnerability-reporting" "private vulnerability reporting"

echo
echo "Security files:"
echo "  ${ROOT}/SECURITY.md"
echo "  ${ROOT}/.github/dependabot.yml"
echo
echo "Workflow templates are archived because pushing active workflows requires"
echo "a token with workflow scope:"
echo "  ${ROOT}/archived-workflows/root/workflows/ci.yml"
echo "  ${ROOT}/archived-workflows/root/workflows/codeql.yml"
echo
echo "To activate workflows after refreshing auth with workflow scope:"
echo "  mkdir -p .github/workflows"
echo "  cp archived-workflows/root/workflows/*.yml .github/workflows/"
echo "  git add .github/workflows"
