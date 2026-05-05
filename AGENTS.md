# Agents

## Overview

Agent Orchestra is a frozen Thursday-good baseline for comparing Terminal
Stampede and Agent Conductor behavior. It packages:

- a known-good Terminal Stampede run from `run-20260430-180646`
- the frozen Terminal Stampede source that produced that baseline
- current Agent Pulse source for inspecting the old run with the latest
  dashboard and metrics code

This repo is not the active production runtime. Treat it as a reproducible
baseline and comparison harness.

## File Map

| Path | Purpose |
|---|---|
| `BASELINE.json` | Machine-readable baseline metadata |
| `known-good-runs/run-20260430-180646/` | Preserved Thursday-good run artifacts |
| `agent-pulse-current/` | Current Agent Pulse source copied into this repo |
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
- Keep Agent Orchestra documentation clear that this is a baseline, not the
  current active Agent Conductor runtime.
