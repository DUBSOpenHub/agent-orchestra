#!/usr/bin/env bash
set -euo pipefail
cd /Users/greggcochran/dev/terminal-stampede
if command -v copilot >/dev/null 2>&1; then
  copilot \
    --agent stampede-commander \
    --model claude-opus-4.7 \
    --allow-all-tools \
    --no-ask-user \
    -p 'Reply exactly STAMPEDE_PREFLIGHT_OK and nothing else.'
else
  gh copilot -- \
    --agent stampede-commander \
    --model claude-opus-4.7 \
    --allow-all-tools \
    --no-ask-user \
    -p 'Reply exactly STAMPEDE_PREFLIGHT_OK and nothing else.'
fi
