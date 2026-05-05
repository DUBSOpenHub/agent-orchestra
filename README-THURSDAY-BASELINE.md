# Agent Orchestra

Agent Orchestra is a frozen comparison baseline for the Terminal Stampede run that worked well on Thursday evening, paired with the current Agent Pulse dashboard code.

## Contents

- Terminal Stampede source frozen at commit `dc14bdefa5d084002fcbcad2a3cc6aa6fa2328c5`.
- Known-good run artifacts copied into `known-good-runs/run-20260430-180646/`.
- Current Agent Pulse source copied into `agent-pulse-current/` so the old run can be inspected with the latest dashboard/metrics code.
- Machine-readable metadata in `BASELINE.json`.

## Known-good run

`known-good-runs/run-20260430-180646/` preserved 5 commander bundles and 9 result files. This is a baseline for comparing the current hardened runtime against the old happy-path behavior.

## Use Agent Pulse against this baseline

```bash
cd agent-pulse-current
AGENT_PULSE_SCAN_ROOTS=/Users/greggcochran/dev/agent-orchestra python3 agent_pulse.py --no-splash
```
