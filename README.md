# Agent Orchestra

Agent Orchestra is a frozen Thursday-good baseline for comparing multi-agent
Terminal Stampede behavior against the current hardened Agent Conductor stack.

It preserves the old run that felt best in practice, while bundling the current
Agent Pulse dashboard code so the historical artifacts can be inspected with
today's telemetry view.

## What is included

| Path | Purpose |
|---|---|
| `known-good-runs/run-20260430-180646/` | Preserved Thursday-good run artifacts |
| `agent-pulse-current/` | Current Agent Pulse source copied into this repo |
| `BASELINE.json` | Machine-readable baseline metadata |
| `AGENTS.md` | Repo-specific agent instructions and guardrails |
| `install.sh` | Local setup and helper launcher installer |
| `quickstart.sh` | One-command clone/install/test flow |
| `bin/agent-orchestra-pulse` | Agent Pulse launcher for this baseline |
| `scripts/activate-security.sh` | GitHub security activation helper |
| `tests/prepublish-smoke.sh` | Baseline validation gate |
| `README-THURSDAY-BASELINE.md` | Short baseline notes and Agent Pulse command |
| `UPSTREAM-TERMINAL-STAMPEDE-README.md` | Original Terminal Stampede README from the frozen source |

## Baseline

The frozen Terminal Stampede source is based on:

```text
dc14bdefa5d084002fcbcad2a3cc6aa6fa2328c5
```

The preserved run is:

```text
run-20260430-180646
```

That run contains:

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
- The preserved Thursday run still has 5 commander bundles and 9 result files.
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

Use this repo as the "known-good" side of an A/B comparison:

```text
Agent Orchestra                    current Agent Conductor + Terminal Stampede
known-good Thursday run            latest hardened runtime
```

Start with `BASELINE.json`, then inspect the commander bundles under:

```text
known-good-runs/run-20260430-180646/commanders/
```

## Repository status

This is now a standalone local repository, not a linked worktree of
`terminal-stampede`.
