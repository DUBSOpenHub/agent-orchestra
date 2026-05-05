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

## View with Agent Pulse

```bash
cd /Users/greggcochran/dev/agent-orchestra/agent-pulse-current
AGENT_PULSE_SCAN_ROOTS=/Users/greggcochran/dev/agent-orchestra python3 agent_pulse.py --no-splash
```

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
