# Agent Orchestra

Agent Orchestra is the frozen Thursday-good baseline and replay companion for Agent Conductor, the multi-agent fleet conductor with real-time TUI observability.

## Contents

- Terminal Stampede source frozen at commit `dc14bdefa5d084002fcbcad2a3cc6aa6fa2328c5`.
- Known-good commander-group artifacts copied into `known-good-runs/run-20260430-180646/`.
- Current Agent Pulse source copied into `agent-pulse-current/` so the old run can be inspected with the latest observability and sub-agent telemetry code.
- Machine-readable fleet baseline metadata in `BASELINE.json`.

## Known-good run

`known-good-runs/run-20260430-180646/` preserved 5 commander bundles and 9 result files. This is the known-good side for comparing the current Agent Conductor fleet runtime, live collaboration ledgers, Agent Pulse observability, and sealed Shadow Score evaluation gates against the old happy-path behavior.

## Use Agent Pulse against this baseline

```bash
cd agent-pulse-current
AGENT_PULSE_SCAN_ROOTS=/Users/greggcochran/dev/agent-orchestra python3 agent_pulse.py --no-splash
```
