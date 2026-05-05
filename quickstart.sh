#!/usr/bin/env bash
set -euo pipefail

REPO="DUBSOpenHub/agent-orchestra"
TARGET_DIR="${AGENT_ORCHESTRA_DIR:-${HOME}/dev/agent-orchestra}"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

need git
need python3

if [[ -f "BASELINE.json" && -d "known-good-runs" && -d "agent-pulse-current" ]]; then
  ROOT="$(pwd)"
elif [[ -d "${TARGET_DIR}/.git" ]]; then
  ROOT="${TARGET_DIR}"
  git -C "${ROOT}" pull --ff-only
else
  mkdir -p "$(dirname "${TARGET_DIR}")"
  if command -v gh >/dev/null 2>&1; then
    gh repo clone "${REPO}" "${TARGET_DIR}"
  else
    git clone "https://github.com/${REPO}.git" "${TARGET_DIR}"
  fi
  ROOT="${TARGET_DIR}"
fi

cd "${ROOT}"
chmod +x install.sh tests/prepublish-smoke.sh
./install.sh

echo
echo "Quickstart complete."
echo "Repo: ${ROOT}"
echo
echo "To launch the dashboard later:"
echo "  agent-orchestra-pulse"
