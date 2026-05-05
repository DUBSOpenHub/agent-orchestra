#!/usr/bin/env python3
import json, os, pathlib

ATOMS = pathlib.Path("/Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/commanders/commander-004/atoms")

def atomic_write(path, data):
    tmp = path.with_name(f".tmp-{path.name}")
    with tmp.open("w") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, path)

# wkr-037-001: pid-tracking
atomic_write(ATOMS / "atm-037-001.json", {
    "worker_id": "wkr-037-001",
    "theme": "stop-teardown-behavior",
    "focus": "pid-tracking",
    "findings": [
        "find_leaf_pid() (L73-90): only inspects first-child chain via head -n1; can return wrong PID if agent is on a sibling branch.",
        "Fixed 5s delay before PID capture (L1277-1279); no readiness loop — slow auth can cause shell PID recorded instead of agent PID.",
        "Teardown (L327-338) sends plain SIGTERM; no SIGKILL fallback, no wait/retry loop.",
        "Commander PID files named commander-XXX.pid (L1293-1299) — correctly distinct from worker PIDs.",
        "No launcher-level tracking for commander-spawned sub-agents; only telemetry via child-agents.jsonl (L1049). Teardown cannot reach nested sub-agents."
    ],
    "source_refs": [
        "bin/stampede.sh:73-90",
        "bin/stampede.sh:1277-1299",
        "bin/stampede.sh:327-345",
        "bin/stampede.sh:1049"
    ],
    "confidence": 0.96,
    "status": "success"
})

# wkr-037-002: monitor-stop-flows
atomic_write(ATOMS / "atm-037-002.json", {
    "worker_id": "wkr-037-002",
    "theme": "stop-teardown-behavior",
    "focus": "monitor-stop-flows",
    "findings": [
        "Dead detection uses tmux pane_dead and pane_current_command (L127, L232) — reliable vs PID files.",
        "Orphan recovery threshold 180s (L25); fires only when live_agents==0 and claimed>0 (L237); requeues via mv (L275).",
        "No trap for SIGTERM/SIGINT — monitor cannot be cleanly stopped by signal.",
        "Hang-forever risk: TOTAL_TASKS forced to 1 (L77) but if done_count stays 0, partial completion never triggers (L300-301 requires done_count>0); loop spins indefinitely.",
        "all_done_or_dead requires total_agents>0 (L282); if tmux returns no panes, flag never sets.",
        "Commander heartbeat check exists only in orphan recovery (L247-274); no dedicated metaswarm shutdown path — completion logic purely generic queue/result counts."
    ],
    "source_refs": [
        "bin/stampede-monitor.sh:25",
        "bin/stampede-monitor.sh:74-77",
        "bin/stampede-monitor.sh:127",
        "bin/stampede-monitor.sh:237",
        "bin/stampede-monitor.sh:275",
        "bin/stampede-monitor.sh:281-305"
    ],
    "confidence": 0.96,
    "status": "success"
})

# wkr-037-003: smoke-stop-coverage
atomic_write(ATOMS / "atm-037-003.json", {
    "worker_id": "wkr-037-003",
    "theme": "stop-teardown-behavior",
    "focus": "smoke-stop-coverage",
    "findings": [
        "--teardown flag is NEVER exercised in smoke-test.sh (zero occurrences).",
        "PID file creation and cleanup never asserted.",
        "No test for dead-agent orphan requeue (stub agent always succeeds, L24-59).",
        "cleanup() (L14-20) stops both regular and metaswarm tmux sessions but not commander-spawned sub-agent processes.",
        "Line 149 explicit tmux stop is benign redundancy with trap-based cleanup — not a gap.",
        "state.json never checked for terminal phase after any operation.",
        "Overall stop/teardown coverage: ~15% — only happy-path completion exercised."
    ],
    "source_refs": [
        "tests/smoke-test.sh:14-20",
        "tests/smoke-test.sh:21",
        "tests/smoke-test.sh:149",
        "tests/smoke-test.sh:152-159"
    ],
    "confidence": 0.95,
    "status": "success"
})

# wkr-037-004: detach-vs-session-lifetime
atomic_write(ATOMS / "atm-037-004.json", {
    "worker_id": "wkr-037-004",
    "theme": "stop-teardown-behavior",
    "focus": "detach-vs-session-lifetime",
    "findings": [
        "remain-on-exit is session-wide (L1167) — covers monitor, worker, and commander panes.",
        "sleep 86400 (L1154-1156) keeps every successful agent pane live for 24h; processes linger if session not torn down.",
        "--teardown terminates recorded PIDs then runs tmux session stop (L306-345) — explicit session removal.",
        "Metaswarm sub-agents spawned by commanders are not in pids/; teardown cannot reach them — potential process leak.",
        "5s PID capture sleep (L1277-1279) insufficient on slow auth startup; wrong PID risk.",
        "README description of --teardown is incomplete: does not mention sub-agent descendants or collab/commanders directories are NOT cleaned."
    ],
    "source_refs": [
        "bin/stampede.sh:1154-1156",
        "bin/stampede.sh:1164-1168",
        "bin/stampede.sh:306-345",
        "bin/stampede.sh:1275-1279",
        "README.md"
    ],
    "confidence": 0.93,
    "status": "success"
})

# wkr-037-005: cleanup-gaps
atomic_write(ATOMS / "atm-037-005.json", {
    "worker_id": "wkr-037-005",
    "theme": "stop-teardown-behavior",
    "focus": "cleanup-gaps",
    "findings": [
        "do_teardown() cleans: PID signals, PID file removal, tmux session stop, state.json->torn_down. Does NOT clean: queue/, claimed/, results/, logs/, scripts/, collab/, commanders/ (L306-364).",
        "commanders/ subdirectories (swarm-state.json, child-agents.jsonl, bundle.json) never removed (L712, L850-956).",
        "collab/ JSONL ledgers (proposals, reviews, improvements, consensus, broadcasts) never cleaned (L770-819).",
        "CI (ci.yml) does NOT run smoke-test.sh; 'Install smoke test' step runs modified install.sh only (ci.yml:38-43).",
        "mark_run_blocked() (L141-196) updates state but does not terminate running processes — potential leak on auth failure.",
        "Claimed tasks are abandoned on teardown — not requeued, not removed (L327-364).",
        "stampede.sh main body has no SIGINT/SIGTERM trap; only a cursor-visibility trap inside a heredoc (L1380)."
    ],
    "source_refs": [
        "bin/stampede.sh:306-364",
        "bin/stampede.sh:770-819",
        "bin/stampede.sh:1380",
        ".github/workflows/ci.yml:38-48",
        "bin/stampede.sh:141-196"
    ],
    "confidence": 0.97,
    "status": "success"
})

print("all 5 atoms written successfully")
