# Agents

## Overview

Agent Orchestra is the baseline and replay companion to Agent Conductor, the
multi-agent fleet conductor with real-time TUI observability. It packages:

- a known-good Terminal Stampede commander-group run from
  `run-20260430-180646`
- the frozen Terminal Stampede source that produced that fleet baseline
- current Agent Pulse source for inspecting commander groups and sub-agent
  telemetry with the latest dashboard and metrics code

This repo is not the active Agent Conductor runtime. Treat it as a reproducible
baseline for comparing commander groups, live collaboration ledgers, Agent Pulse
observability, and sealed Shadow Score evaluation behavior.

Use user-facing terminology **sub-agents**. The compatibility ledger filename
`child-agents.jsonl` may appear in preserved artifacts, but docs and responses
should use **sub-agents**.

## File Map

| Path | Purpose |
|---|---|
| `BASELINE.json` | Machine-readable fleet baseline metadata |
| `known-good-runs/run-20260430-180646/` | Preserved Thursday-good commander-group artifacts |
| `agent-pulse-current/` | Current Agent Pulse observability source copied into this repo |
| `bin/agent-orchestra-pulse` | Local launcher for Agent Pulse against this repo |
| `tests/prepublish-smoke.sh` | Pre-publish baseline validation |
| `install.sh` | Installs local Agent Orchestra helper launcher |
| `quickstart.sh` | One-command clone/install/test/launch flow |
| `scripts/activate-security.sh` | Enables GitHub security settings and explains workflow activation |
| `archived-workflows/` | CI/CodeQL workflows held outside `.github/workflows` until token has `workflow` scope |
| `UPSTREAM-TERMINAL-STAMPEDE-README.md` | Original Terminal Stampede README from the frozen source |

## Rules

- Do not mutate `known-good-runs/run-20260430-180646/` unless intentionally
  replacing the baseline.
- Run `./tests/prepublish-smoke.sh` before publishing or comparing.
- Keep active workflow files out of `.github/workflows` unless the pushing token
  has `workflow` scope.
- Use `scripts/activate-security.sh` for GitHub security settings.
- Keep Agent Orchestra documentation clear that this is the Agent Conductor
  baseline/replay companion, not the active fleet runtime.
