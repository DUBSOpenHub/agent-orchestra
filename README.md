# 🎼 Agent Orchestra

**Multi-agent fleet conductor for the GitHub Copilot CLI. Launch multiple
visible Terminal Stampede commander groups, let them collaborate in real time,
and score the final synthesis with sealed
[Shadow Score](https://github.com/DUBSOpenHub/shadow-score-spec/blob/main/SPEC.md)
gates.**

[![GitHub Copilot CLI](https://img.shields.io/badge/platform-Copilot%20CLI-232F3E.svg)](https://docs.github.com/copilot/concepts/agents/about-copilot-cli)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Security Policy](https://img.shields.io/badge/Security-Policy-brightgreen?logo=github)](SECURITY.md)

Agent Orchestra packages the Agent Conductor-style fleet experience under this
repo name: Terminal Stampede commander groups, Agent Pulse observability,
append-only collaboration ledgers, bounded sub-agent telemetry, and sealed
Shadow Score quality gates.

## What is included

| Path | Purpose |
|---|---|
| `known-good-runs/run-20260430-180646/` | Preserved commander-group reference artifacts |
| `agent-pulse-current/` | Current Agent Pulse observability source copied into this repo |
| `BASELINE.json` | Machine-readable fleet reference metadata |
| `AGENTS.md` | Repo-specific agent instructions and guardrails |
| `install.sh` | Local setup and helper launcher installer |
| `quickstart.sh` | One-command clone/install/test flow |
| `bin/agent-orchestra-pulse` | Agent Pulse launcher for this repo |
| `scripts/activate-security.sh` | GitHub security activation helper |
| `tests/prepublish-smoke.sh` | Reference validation gate |
| `REFERENCE-NOTES.md` | Short reference notes and Agent Pulse command |
| `UPSTREAM-TERMINAL-STAMPEDE-README.md` | Original Terminal Stampede README from the frozen source |

## Reference artifacts

The frozen Terminal Stampede source is based on:

```text
dc14bdefa5d084002fcbcad2a3cc6aa6fa2328c5
```

The preserved run is:

```text
run-20260430-180646
```

Agent Orchestra's fleet run shape follows the Agent Conductor contract: exactly
five commander groups. The preserved reference artifacts contain:

```text
5 commander bundles
9 total result files
```

## Quickstart

From a checked-out repo:

```bash
./quickstart.sh
```

Or clone/install with the GitHub CLI:

```bash
gh repo clone DUBSOpenHub/agent-orchestra ~/dev/agent-orchestra
cd ~/dev/agent-orchestra
./quickstart.sh
```

The quickstart runs the pre-publish smoke test and installs:

```text
~/bin/agent-orchestra-pulse
```

## View with Agent Pulse

```bash
agent-orchestra-pulse
```

## Pre-publish test

Before making the repo public or cutting a release, run:

```bash
cd /Users/greggcochran/dev/agent-orchestra
./tests/prepublish-smoke.sh
```

This checks that:

- `BASELINE.json` is valid and names Agent Orchestra.
- The preserved reference run still has 5 commander bundles and 9 result files.
- Every commander bundle has matching `commander_id` and `task_id`.
- Current Agent Pulse imports and polls against this repo.
- Workflow files remain archived outside `.github/workflows` until the token has
  `workflow` scope.

## Security activation

Security policy and Dependabot config are included. To enable repository-level
security features:

```bash
./scripts/activate-security.sh
```

CI and CodeQL workflow templates are staged under:

```text
archived-workflows/root/workflows/
```

They intentionally remain outside `.github/workflows` until the authenticated
token has GitHub `workflow` scope.

## Compare against current stack

Use this repo as the reference side of an Agent Conductor-style fleet
comparison:

```text
Agent Orchestra                 current Agent Conductor
fleet reference artifacts       multi-agent fleet conductor
frozen commander artifacts      live Terminal Stampede commander groups
Agent Pulse replay view         Agent Pulse + live collaboration ledgers
baseline comparison             sealed Shadow Score evaluation
```

Start with `BASELINE.json`, then inspect the commander bundles under:

```text
known-good-runs/run-20260430-180646/commanders/
```

## Repository status

This is now a standalone local repository, not a linked worktree of
`terminal-stampede`.
