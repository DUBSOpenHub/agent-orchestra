# Agents

## Overview

Agent Orchestra is a multi-agent fleet conductor for the GitHub Copilot CLI. It
launches multiple visible Terminal Stampede commander groups, lets them
collaborate in real time, and scores the final synthesis with sealed Shadow
Score gates.

This repo follows the Agent Conductor product language: commander groups,
bounded sub-agent fan-out, Agent Pulse observability, append-only collaboration
ledgers, and sealed Shadow Score evaluation.

Use user-facing terminology **sub-agents**. The compatibility ledger filename
`child-agents.jsonl` may appear in preserved artifacts, but docs and responses
should use **sub-agents**.

## File Map

| Path | Purpose |
|---|---|
| `ORCHESTRA.json` | Machine-readable fleet metadata |
| `run-artifacts/run-20260430-180646/` | Local commander-group run artifact corpus |
| `agent-pulse-current/` | Current Agent Pulse observability source copied into this repo |
| `bin/agent-orchestra-pulse` | Local launcher for Agent Pulse against this repo |
| `tests/smoke.sh` | Local fleet smoke validation |
| `tests/prepublish-smoke.sh` | Backward-compatible smoke wrapper target |
| `install.sh` | Installs local Agent Orchestra helper launcher |
| `quickstart.sh` | One-command clone/install/test/launch flow |
| `scripts/activate-security.sh` | Enables GitHub security settings and explains workflow activation |
| `archived-workflows/` | CI/CodeQL workflows held outside `.github/workflows` until token has `workflow` scope |
| `UPSTREAM-TERMINAL-STAMPEDE-README.md` | Original Terminal Stampede runtime README |

## Rules

- Do not mutate `run-artifacts/run-20260430-180646/` unless intentionally
  replacing the run artifact corpus.
- Run `bash tests/smoke.sh` before publishing or comparing.
- Keep active workflow files out of `.github/workflows` unless the pushing token
  has `workflow` scope.
- Use `scripts/activate-security.sh` for GitHub security settings.
- Keep Agent Orchestra documentation aligned with the Agent Conductor-style
  product description.
