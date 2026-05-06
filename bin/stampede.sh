#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

# stampede.sh — Launcher for Terminal Stampede agent fleet
# Creates a tmux session with one pane per agent + a monitor pane.
# Usage:
#   stampede.sh --run-id <id> --count <n> --repo <path> [--model <model>]
#   stampede.sh --teardown --run-id <id>

# ─── Defaults ────────────────────────────────────────────────────────────────
RUN_ID=""
WORKER_COUNT=3
REPO_PATH=""
MODEL="claude-haiku-4.5"
MODELS=""  # comma-separated list for multi-model rotation
MODEL_SET=false
MODELS_SET=false
PREMIUM_METASWARM_MODELS="claude-opus-4.7,gpt-5.5,claude-opus-4.6,gpt-5.4,claude-opus-4.5,gpt-5.2,claude-sonnet-4.6,gpt-5.3-codex,claude-sonnet-4.5,gpt-5.2-codex"
BANNED_METASWARM_MODELS="claude-haiku-4.5 gpt-5.4-mini gpt-5-mini gpt-4.1"
TEARDOWN=false
NO_ATTACH=false
DRY_RUN=false
PREFLIGHT=false
METASWARM=false
AGENT_CMD=""  # Custom CLI agent command (default: GitHub Copilot CLI)
COPILOT_PREFLIGHT_TIMEOUT="${STAMPEDE_COPILOT_PREFLIGHT_TIMEOUT:-60}"
MAX_AUTOPILOT_CONTINUES="${STAMPEDE_MAX_AUTOPILOT_CONTINUES:-30}"
# Run directory lives INSIDE the repo (.stampede/) so agents can access it.
# Content exclusion policies block ~/.copilot/ but repos are always accessible.
STAMPEDE_BASE=""  # set after REPO_PATH is known

# ─── Argument Parsing ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --run-id)    RUN_ID="$2";       shift 2 ;;
        --count)     WORKER_COUNT="$2"; shift 2 ;;
        --repo)      REPO_PATH="$2";    shift 2 ;;
        --model)     MODEL="$2"; MODEL_SET=true; shift 2 ;;
        --models)    MODELS="$2"; MODELS_SET=true; shift 2 ;;
        --teardown)  TEARDOWN=true;     shift   ;;
        --no-attach) NO_ATTACH=true;    shift   ;;
        --dry-run)   DRY_RUN=true;      shift   ;;
        --preflight) PREFLIGHT=true;    shift   ;;
        --metaswarm) METASWARM=true;    shift   ;;
        --agent-cmd) AGENT_CMD="$2";    shift 2 ;;
        -h|--help)
            echo "Usage: $0 --run-id <id> --count <n> --repo <path> [--model <model>] [--models m1,m2,m3] [--metaswarm]"
            echo ""
            echo "Options:"
            echo "  --run-id <id>      Run identifier (format: run-YYYYMMDD-HHMMSS)"
            echo "  --count <n>        Number of workers (default: 3)"
            echo "  --repo <path>      Repository path (must be a git repo)"
            echo "  --model <model>    AI model to use (default: claude-haiku-4.5; metaswarm defaults to premium rotation)"
            echo "  --models <list>    Comma-separated models for rotation (metaswarm rejects cheap/mini models)"
            echo "  --teardown         Stop the session and cleanup"
            echo "  --no-attach        Don't auto-attach to tmux session"
            echo "  --dry-run          Show what would run without creating the session"
            echo "  --preflight        Test that agents can access the queue before launching"
            echo "  --metaswarm        Launch commander panes for Havoc/Swarm metaswarm runs"
            echo "  --agent-cmd <cmd>  Custom CLI agent command template (default: GitHub Copilot CLI)"
            echo "                     Use {prompt} and {model} as placeholders."
            echo "                     Example: --agent-cmd 'claude -p \"{prompt}\"'"
            echo "  -h, --help         Show this help"
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# ─── Process Tree Walker ─────────────────────────────────────────────────────
# Landmine #16: pane PID != worker PID. Prefer the long-lived CLI agent process
# over transient shell children spawned by that agent while it works.
find_leaf_pid() {
    local root="$1"
    local pid child cmd
    local queue=("$root")

    # First search the whole pane process tree for a long-lived CLI agent.
    # If a shell starts helper siblings before the agent, a first-child walk can
    # otherwise record the wrong PID and leave the real agent orphaned.
    while [[ "${#queue[@]}" -gt 0 ]]; do
        pid="${queue[0]}"
        queue=("${queue[@]:1}")
        while read -r child; do
            [[ -n "$child" ]] || continue
            cmd="$(ps -p "$child" -o args= 2>/dev/null || true)"
            if [[ "$cmd" == *"copilot"* || "$cmd" == *"gh copilot"* || "$cmd" == *"claude"* || "$cmd" == *"aider"* ]]; then
                echo "$child"
                return
            fi
            queue+=("$child")
        done < <(pgrep -P "$pid" 2>/dev/null || true)
    done

    # Fallback for non-CLI commands: return the deepest first-child descendant.
    pid="$root"
    while true; do
        child="$(pgrep -P "$pid" 2>/dev/null | head -n1 || true)"
        [[ -z "$child" ]] && break
        pid="$child"
    done
    echo "$pid"
}

# ─── 8-Prerequisite Validation ───────────────────────────────────────────────
# Landmine #22: missing prereqs cause silent fleet no-ops.
check_prereqs() {
    local fail=0
    local bins=(tmux python3 jq openssl git bash)
    local optional_bins=(watch copilot gh)

    for bin in "${bins[@]}"; do
        if command -v "$bin" &>/dev/null; then
            echo "  ✅ $bin"
        else
            echo "  ❌ $bin — MISSING" >&2
            fail=1
        fi
    done

    for bin in "${optional_bins[@]}"; do
        if command -v "$bin" &>/dev/null; then
            echo "  ✅ $bin (optional)"
        else
            echo "  ⚠️  $bin — not found (monitor pane will be skipped)"
        fi
    done

    # Copilot CLI is optional — only needed if using the default agent command.
    if [[ -z "$AGENT_CMD" ]]; then
        if command -v copilot &>/dev/null; then
            echo "  ✅ copilot CLI (default agent)"
        elif command -v gh &>/dev/null; then
            if gh copilot --help &>/dev/null 2>&1; then
                echo "  ✅ gh copilot extension (fallback default agent)"
            else
                echo "  ⚠️  gh copilot extension not found (install with: gh extension install github/gh-copilot)"
                echo "     Or use --agent-cmd to specify a different CLI agent"
            fi
        else
            echo "  ⚠️  copilot/gh — not found (needed for default Copilot CLI agent, or use --agent-cmd)"
        fi
    else
        echo "  ✅ Custom agent command configured"
    fi

    if [[ "$fail" -eq 1 ]]; then
        echo "Prerequisite check failed. Install missing tools." >&2
        exit 1
    fi
    echo "All prerequisites satisfied."
}

mark_run_blocked() {
    local reason="$1"
    local detail="${2:-}"
    python3 - "$BASE_DIR" "$reason" "$detail" <<'PY'
import json
import pathlib
import sys
import time

base = pathlib.Path(sys.argv[1])
reason = sys.argv[2]
detail = sys.argv[3]
now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

def write_json(path: pathlib.Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(data, indent=2))
    tmp.replace(path)

state_path = base / "state.json"
try:
    state = json.loads(state_path.read_text()) if state_path.exists() else {}
    state["phase"] = reason
    state["status"] = "blocked"
    state["blocked_reason"] = reason
    state["blocked_detail"] = detail
    state["updated_at"] = now
    write_json(state_path, state)
except Exception:
    pass

for state_file in sorted(base.glob("commanders/commander-*/swarm-state.json")):
    try:
        commander_state = json.loads(state_file.read_text()) if state_file.exists() else {}
        commander_state["phase"] = reason
        commander_state["status"] = "blocked"
        commander_state["blocked_reason"] = reason
        commander_state["blocked_detail"] = detail
        commander_state["updated_at"] = now
        commander_state["last_heartbeat_at"] = now
        write_json(state_file, commander_state)

        ledger = state_file.parent / "child-agents.jsonl"
        with ledger.open("a") as f:
            f.write(json.dumps({
                "ts": now,
                "event": "commander_blocked",
                "commander_id": state_file.parent.name,
                "reason": reason,
                "detail": detail,
            }) + "\n")
    except Exception:
        continue
PY
}

run_default_agent_launch_preflight() {
    [[ -n "$AGENT_CMD" ]] && return 0

    local probe_agent="stampede-agent"
    if $METASWARM; then
        probe_agent="stampede-commander"
    fi

    local probe_model="${MODEL_LIST[0]:-$MODEL}"
    local session_name="stampede-preflight-${RUN_ID}-$$"
    local probe_script="${BASE_DIR}/scripts/copilot-preflight.sh"
    local runner_script="${BASE_DIR}/scripts/copilot-preflight-runner.sh"
    local log_file="${BASE_DIR}/logs/copilot-preflight.log"

    mkdir -p "${BASE_DIR}/scripts" "${BASE_DIR}/logs"
    rm -f "$log_file" "$probe_script" "$runner_script"

    echo "  ── Copilot CLI tmux preflight ──"
    python3 - "$probe_script" "$REPO_PATH" "$probe_agent" "$probe_model" <<'PY'
import pathlib
import shlex
import sys

path = pathlib.Path(sys.argv[1])
repo_path = sys.argv[2]
agent = sys.argv[3]
model = sys.argv[4]
prompt = "Reply exactly STAMPEDE_PREFLIGHT_OK and nothing else."

script = f"""#!/usr/bin/env bash
set -euo pipefail
cd {shlex.quote(repo_path)}
if command -v copilot >/dev/null 2>&1; then
  copilot \\
    --agent {shlex.quote(agent)} \\
    --model {shlex.quote(model)} \\
    --allow-all-tools \\
    --no-ask-user \\
    -p {shlex.quote(prompt)}
else
  gh copilot -- \\
    --agent {shlex.quote(agent)} \\
    --model {shlex.quote(model)} \\
    --allow-all-tools \\
    --no-ask-user \\
    -p {shlex.quote(prompt)}
fi
"""
path.write_text(script)
path.chmod(0o755)
PY

    cat > "$runner_script" << RUNNEREOF
#!/usr/bin/env bash
set +e
"$probe_script" > "$log_file" 2>&1
code=\$?
echo "EXIT:\$code" >> "$log_file"
exit "\$code"
RUNNEREOF
    chmod +x "$runner_script"

    tmux new-session -d -s "$session_name" "$runner_script"
    local elapsed=0
    while [[ "$elapsed" -lt "$COPILOT_PREFLIGHT_TIMEOUT" ]]; do
        if [[ -f "$log_file" ]] && grep -q '^EXIT:' "$log_file"; then
            break
        fi
        if ! tmux has-session -t "$session_name" 2>/dev/null; then
            break
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    if tmux has-session -t "$session_name" 2>/dev/null; then
        tmux kill-session -t "$session_name" 2>/dev/null || true
    fi

    local exit_code="timeout"
    if [[ -f "$log_file" ]] && grep -q '^EXIT:' "$log_file"; then
        exit_code=$(awk -F: '/^EXIT:/{code=$2} END{print code}' "$log_file")
    fi

    if [[ "$exit_code" == "0" ]] && grep -q "STAMPEDE_PREFLIGHT_OK" "$log_file"; then
        echo "  ✅ Copilot CLI authenticated in tmux runtime"
        return 0
    fi

    local detail=""
    if [[ -f "$log_file" ]]; then
        detail=$(sed -E 's/[A-Za-z0-9_=-]{30,}/[REDACTED]/g' "$log_file" | tr '\n' ' ' | cut -c1-1000)
    else
        detail="Copilot preflight timed out before producing output."
    fi

    echo "  ❌ Copilot CLI preflight failed in tmux runtime"
    echo "     $detail"
    echo ""
    echo "  Fix: re-authenticate Copilot/GitHub CLI, then retry:"
    echo "       copilot  # then run /login"
    echo "       gh auth login -h github.com"
    mark_run_blocked "auth_blocked" "$detail"
    return 1
}

# ─── Teardown ─────────────────────────────────────────────────────────────────
# Landmine #24: teardown must target session-specific PIDs only.
do_teardown() {
    if [[ -z "$RUN_ID" ]]; then
        echo "ERROR: --run-id required for teardown" >&2
        exit 1
    fi

    local session_name="stampede-${RUN_ID}"
    # Search for run dir in repo (.stampede/) or legacy (~/.copilot/stampede/)
    local base_dir=""
    if [[ -n "$REPO_PATH" ]] && [[ -d "$REPO_PATH/.stampede/${RUN_ID}" ]]; then
        base_dir="$REPO_PATH/.stampede/${RUN_ID}"
    elif [[ -d "$REPO_PATH/.stampede/${RUN_ID}" ]]; then
        base_dir="$REPO_PATH/.stampede/${RUN_ID}"
    elif [[ -d "$HOME/.copilot/stampede/${RUN_ID}" ]]; then
        base_dir="$HOME/.copilot/stampede/${RUN_ID}"
    elif [[ -d "$HOME/.stampede/${RUN_ID}" ]]; then
        base_dir="$HOME/.stampede/${RUN_ID}"
    fi

    echo "Tearing down stampede session: $session_name"

    if [[ -d "$base_dir/pids" ]]; then
        for pidfile in "$base_dir/pids"/*.pid; do
            [[ -f "$pidfile" ]] || continue
            local wpid
            wpid=$(cat "$pidfile" 2>/dev/null || true)
            if [[ -n "$wpid" ]]; then
                if kill -0 "$wpid" 2>/dev/null; then
                    kill "$wpid" 2>/dev/null || true
                    echo "  ✓ Stopped worker PID $wpid"
                fi
            fi
        done
        rm -f "$base_dir/pids"/*.pid 2>/dev/null
        echo "  ✓ Cleaned PID files"
    fi

    if tmux has-session -t "$session_name" 2>/dev/null; then
        tmux kill-session -t "$session_name"
        echo "  ✓ Terminated tmux session $session_name"
    else
        echo "  ⚠ No tmux session $session_name found"
    fi

    if [[ -d "$base_dir/commanders" ]]; then
        python3 - "$base_dir" <<'PY'
import json
import pathlib
import re
import sys
import time

base = pathlib.Path(sys.argv[1])
now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

def read_json(path: pathlib.Path, default):
    try:
        return json.loads(path.read_text()) if path.exists() else default
    except Exception:
        return default

def write_json_atomic(path: pathlib.Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(data, indent=2))
    tmp.replace(path)

def metric(state: dict, telemetry: dict, *names: str, default: int = 0) -> int:
    for name in names:
        for source in (telemetry, state):
            value = source.get(name) if isinstance(source, dict) else None
            if value is None:
                continue
            try:
                return int(value)
            except (TypeError, ValueError):
                continue
    return default

def child_level(item: dict, child_id: str) -> str:
    role = str(item.get("role") or item.get("agent_type") or item.get("kind") or "").lower()
    if role in {"squad_lead", "squad-lead", "squad"} or child_id.startswith("sq-"):
        return "squad"
    if role in {"worker", "sub-agent", "sub_agent"} or child_id.startswith("wkr-"):
        return "worker"
    return "other"

def commentary_high_water(base: pathlib.Path, commander_id: str) -> dict:
    high = {
        "squad_leads_launched": 0,
        "workers_launched": 0,
        "child_agents_running": 0,
        "child_agents_completed": 0,
        "child_agents_failed": 0,
    }
    paths = [base / "orchestrator-commentary.jsonl", base / "orchestrator-commentary.json"]
    pattern = re.compile(
        rf"{re.escape(commander_id)}\s+[^·]*·\s+squads\s+(\d+)/(\d+)\s+·\s+"
        r"sub-agents\s+(\d+)/(\d+)\s+·\s+run\s+(\d+)\s+done\s+(\d+)\s+fail\s+(\d+)"
    )
    for path in paths:
        if not path.exists():
            continue
        records = []
        try:
            if path.suffix == ".jsonl":
                for line in path.read_text(errors="replace").splitlines():
                    if not line.strip():
                        continue
                    try:
                        records.append(json.loads(line))
                    except Exception:
                        continue
            else:
                records.append(json.loads(path.read_text()))
        except Exception:
            continue
        for record in records:
            lines = record.get("lines") if isinstance(record, dict) else []
            if not isinstance(lines, list):
                continue
            for line in lines:
                if not isinstance(line, str):
                    continue
                match = pattern.search(line)
                if not match:
                    continue
                squads, _, workers, _, running, done, failed = (int(value) for value in match.groups())
                high["squad_leads_launched"] = max(high["squad_leads_launched"], squads)
                high["workers_launched"] = max(high["workers_launched"], workers)
                high["child_agents_running"] = max(high["child_agents_running"], running)
                high["child_agents_completed"] = max(high["child_agents_completed"], done)
                high["child_agents_failed"] = max(high["child_agents_failed"], failed)
    return high

created = 0
for progress_dir in sorted((base / "commanders").glob("commander-*")):
    if not progress_dir.is_dir():
        continue
    commander_id = progress_dir.name
    result_path = base / "results" / f"{commander_id}.json"
    bundle_path = progress_dir / "bundle.json"
    if result_path.exists() and bundle_path.exists():
        continue

    state_file = progress_dir / "swarm-state.json"
    state = read_json(state_file, {})
    telemetry = state.get("telemetry") if isinstance(state.get("telemetry"), dict) else {}
    ledger = progress_dir / "child-agents.jsonl"
    ledger_counts = {}
    blockers = []
    squad_seen = set()
    squad_done = set()
    squad_failed = set()
    worker_seen = set()
    worker_done = set()
    worker_failed = set()
    if ledger.exists():
        for line in ledger.read_text(errors="replace").splitlines():
            try:
                item = json.loads(line)
            except Exception:
                continue
            event = str(item.get("event") or "unknown")
            status_text = str(item.get("status") or event).lower()
            child_id = str(item.get("child_id") or item.get("agent_id") or item.get("id") or "")
            ledger_counts[event] = ledger_counts.get(event, 0) + 1
            if child_id:
                level = child_level(item, child_id)
                if level == "squad":
                    squad_seen.add(child_id)
                    if event in {"completed", "success"} or status_text in {"success", "done", "completed", "complete"}:
                        squad_done.add(child_id)
                    elif event in {"failed", "launch_failed"} or status_text in {"failed", "error", "blocked"}:
                        squad_failed.add(child_id)
                elif level == "worker":
                    worker_seen.add(child_id)
                    if event in {"completed", "success"} or status_text in {"success", "done", "completed", "complete"}:
                        worker_done.add(child_id)
                    elif event in {"failed", "launch_failed"} or status_text in {"failed", "error", "blocked"}:
                        worker_failed.add(child_id)
            if item.get("error") or event in {"launch_blocked", "launch_failed", "failed", "commander_launch_failed"}:
                blockers.append({
                    k: item.get(k)
                    for k in ("ts", "event", "child_id", "role", "model", "error", "exit_code", "detail", "status")
                    if k in item
                })

    commentary = commentary_high_water(base, commander_id)
    squad_target = metric(state, telemetry, "squad_leads_target", "squads_target", default=50)
    worker_target = metric(state, telemetry, "workers_target", default=250)
    squads_launched = max(
        metric(state, telemetry, "squad_leads_launched", "squad_leads_started"),
        len(squad_seen),
        commentary["squad_leads_launched"],
    )
    squads_done = max(metric(state, telemetry, "squad_leads_completed"), len(squad_done))
    squads_failed = max(metric(state, telemetry, "squad_leads_failed"), len(squad_failed))
    workers_launched = max(
        metric(state, telemetry, "workers_launched", "workers_started"),
        len(worker_seen),
        commentary["workers_launched"],
    )
    workers_done = max(metric(state, telemetry, "workers_completed", "atoms_received"), len(worker_done))
    workers_failed = max(metric(state, telemetry, "workers_failed", "children_failed"), len(worker_failed))
    telemetry = dict(telemetry)
    telemetry.update({
        "squad_leads_launched": squads_launched,
        "squad_leads_completed": squads_done,
        "squad_leads_failed": squads_failed,
        "workers_launched": workers_launched,
        "workers_completed": workers_done,
        "workers_failed": workers_failed,
        "child_agents_seen": max(squads_launched + workers_launched, len(squad_seen) + len(worker_seen)),
        "child_agents_completed": max(squads_done + workers_done, commentary["child_agents_completed"]),
        "child_agents_failed": max(squads_failed + workers_failed, commentary["child_agents_failed"]),
        "child_agents_running": commentary["child_agents_running"],
    })
    telemetry_high_water = {
        "squad_leads_launched": squads_launched,
        "workers_launched": workers_launched,
        "child_agents_seen": telemetry["child_agents_seen"],
        "child_agents_completed": telemetry["child_agents_completed"],
        "child_agents_failed": telemetry["child_agents_failed"],
        "child_agents_running": telemetry["child_agents_running"],
        "sources": ["swarm-state.json", "child-agents.jsonl", "orchestrator-commentary.jsonl"],
    }
    existing_status = str(state.get("status") or "").lower()
    if existing_status in {"failed", "partial"}:
        status = existing_status
    else:
        status = "success" if (
            squads_launched >= squad_target
            and squads_done >= squad_target
            and workers_launched >= worker_target
            and workers_done >= worker_target
            and workers_failed == 0
        ) else "partial"
    if status == "success":
        phase = "complete"
    elif status == "failed":
        phase = "teardown_synthesized_failed"
    else:
        phase = "teardown_synthesized_partial"
    log_path = progress_dir / "logs" / "commander-cli.log"
    detail = ""
    if log_path.exists():
        detail = re.sub(r"[A-Za-z0-9_=-]{30,}", "[REDACTED]", log_path.read_text(errors="replace")[-4000:])
    bundle = {
        "run_id": state.get("run_id"),
        "commander_id": commander_id,
        "task_id": state.get("task_id") or commander_id,
        "status": status,
        "phase": phase,
        "synthesized_by": "stampede-teardown",
        "synthesized_at": now,
        "exit_code": 143,
        "telemetry": telemetry,
        "telemetry_high_water": telemetry_high_water,
        "ledger_counts": ledger_counts,
        "atoms": sorted(p.name for p in (progress_dir / "atoms").glob("*.json")),
        "blockers": blockers[-20:],
        "error": {
            "kind": "teardown_missing_bundle",
            "detail": "Teardown found this commander missing bundle/result artifacts and synthesized a terminal status from recorded launch proof.",
        },
        "log_tail": detail if status != "success" else "",
        "source_refs": [str(state_file), str(ledger), str(log_path)],
    }
    write_json_atomic(bundle_path, bundle)
    write_json_atomic(result_path, bundle)
    state.update({
        "status": status,
        "phase": phase,
        "telemetry": telemetry,
        "telemetry_high_water": telemetry_high_water,
        "updated_at": now,
        "last_heartbeat_at": now,
        "bundle_path": str(bundle_path),
        "result_path": str(result_path),
    })
    write_json_atomic(state_file, state)
    with ledger.open("a") as f:
        f.write(json.dumps({
            "ts": now,
            "event": "bundle_synthesized",
            "commander_id": commander_id,
            "status": status,
            "phase": phase,
            "exit_code": 143,
        }) + "\n")
    created += 1

print(f"  ✓ Synthesized missing commander terminal bundles: {created}")
PY
    fi

    if [[ -f "$base_dir/state.json" ]]; then
        python3 -c "
import json, time
p = '$base_dir/state.json'
with open(p) as f: state = json.load(f)
state['phase'] = 'torn_down'
state['updated_at'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
with open(p, 'w') as f: json.dump(state, f, indent=2)
"
        echo "  ✓ Updated state.json → torn_down"
    fi

    echo "Teardown complete."
    exit 0
}

# ─── Preflight Check ─────────────────────────────────────────────────────────
# Verifies agents can actually read the queue by spawning a test agent.
do_preflight() {
    echo ""
    echo "🦬 Preflight Check"
    echo "═══════════════════════════════════════════"
    local fail=0

    # 1. Prerequisites
    echo "  ── Prerequisites ──"
    check_prereqs

    # 2. Run directory
    echo ""
    echo "  ── Run Directory ──"
    if [[ -d "$BASE_DIR/queue" ]]; then
        local tc
        tc=$(find "$BASE_DIR/queue" -name '*.json' -type f 2>/dev/null | wc -l | tr -d ' ')
        echo "  ✅ Queue exists ($tc tasks)"
    else
        echo "  ❌ Queue not found: $BASE_DIR/queue"
        fail=1
    fi

    # 3. Git repo
    echo ""
    echo "  ── Repository ──"
    if git -C "$REPO_PATH" rev-parse --git-dir &>/dev/null; then
        local branch
        branch=$(git -C "$REPO_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null)
        echo "  ✅ Git repo on branch: $branch"
    else
        echo "  ❌ Not a git repo: $REPO_PATH"
        fail=1
    fi

    # 4. Agent access test — the critical check
    echo ""
    echo "  ── Agent Access (content exclusion test) ──"
    # Write a canary file in the queue, ask the agent to read it
    local canary="$BASE_DIR/queue/.preflight-canary"
    echo "stampede-preflight-ok" > "$canary"

    local agent_output
    if [[ -n "$AGENT_CMD" ]]; then
        echo "  ⚠️  Custom agent command — skipping automated access test"
        echo "     Verify your agent can read: $BASE_DIR/queue/"
        rm -f "$canary"
    else
        if command -v copilot &>/dev/null; then
            agent_output=$(cd "$REPO_PATH" && copilot \
                --agent stampede-agent \
                --model "${MODEL}" \
                --allow-all-tools \
                --autopilot \
                --max-autopilot-continues 2 \
                --no-ask-user \
                -p "Read the file at $canary and print its contents. Only print the file contents, nothing else." 2>&1 | head -20)
        else
            agent_output=$(cd "$REPO_PATH" && gh copilot -- \
                --agent stampede-agent \
                --model "${MODEL}" \
                --allow-all-tools \
                --autopilot \
                --max-autopilot-continues 2 \
                --no-ask-user \
                -p "Read the file at $canary and print its contents. Only print the file contents, nothing else." 2>&1 | head -20)
        fi

        rm -f "$canary"

        if echo "$agent_output" | grep -q "stampede-preflight-ok"; then
            echo "  ✅ Agent can read queue directory"
        elif echo "$agent_output" | grep -qi "permission denied\|content exclusion"; then
            echo "  ❌ Agent BLOCKED by content exclusion policy"
            echo "     The queue is at: $BASE_DIR"
            echo "     Agents cannot read files outside the repo."
            echo ""
            echo "  💡 Fix: ensure .stampede/ is inside the repo (not ~/.copilot/)"
            fail=1
        else
            echo "  ⚠️  Agent response unclear — check manually:"
            echo "$agent_output" | head -5 | sed 's/^/     /'
        fi
    fi

    # 5. Model availability
    echo ""
    echo "  ── Model ──"
    if echo "$agent_output" | grep -qi "invalid\|not found\|not available"; then
        echo "  ❌ Model '$MODEL' may not be available"
        fail=1
    else
        echo "  ✅ Model: $MODEL"
    fi

    # Result
    echo ""
    echo "═══════════════════════════════════════════"
    if [[ $fail -eq 0 ]]; then
        echo "  ✅ PREFLIGHT PASSED — ready to stampede"
    else
        echo "  ❌ PREFLIGHT FAILED — fix issues above"
    fi
    echo "═══════════════════════════════════════════"
    exit $fail
}

# ─── Main ─────────────────────────────────────────────────────────────────────

if ! $DRY_RUN && ! $PREFLIGHT; then
    echo "Checking prerequisites..."
    check_prereqs
fi

if $TEARDOWN; then
    do_teardown
fi

if [[ -z "$RUN_ID" ]]; then
    echo "ERROR: --run-id is required" >&2
    exit 1
fi

if [[ -z "$REPO_PATH" ]]; then
    echo "ERROR: --repo is required" >&2
    exit 1
fi

# Validate run_id format (Landmine #20)
if ! [[ "$RUN_ID" =~ ^run-[0-9]{8}-[0-9]{6}$ ]]; then
    echo "ERROR: Invalid --run-id format: $RUN_ID (expected run-YYYYMMDD-HHMMSS)" >&2
    exit 1
fi

if ! [[ "$WORKER_COUNT" =~ ^[0-9]+$ ]] || [[ "$WORKER_COUNT" -lt 1 ]]; then
    echo "ERROR: --count must be integer >= 1" >&2
    exit 1
fi

if $METASWARM && [[ "$WORKER_COUNT" -gt 5 ]]; then
    echo "ERROR: --metaswarm requires exactly 5 commanders (250 workers each; total cap 1600)" >&2
    exit 1
fi

if $METASWARM && [[ "$WORKER_COUNT" -ne 5 ]]; then
    echo "ERROR: --metaswarm requires exactly 5 commanders; got --count $WORKER_COUNT" >&2
    exit 1
fi

if [[ ! -d "$REPO_PATH/.git" ]] && ! git -C "$REPO_PATH" rev-parse --git-dir &>/dev/null; then
    echo "ERROR: --repo must be a git repository: $REPO_PATH" >&2
    exit 1
fi

if $METASWARM; then
    if ! $MODEL_SET && ! $MODELS_SET; then
        MODELS="$PREMIUM_METASWARM_MODELS"
    fi
    IFS=',' read -ra SELECTED_METASWARM_MODELS <<< "${MODELS:-$MODEL}"
    for selected_model in "${SELECTED_METASWARM_MODELS[@]}"; do
        selected_model="${selected_model//[[:space:]]/}"
        for banned_model in $BANNED_METASWARM_MODELS; do
            if [[ "$selected_model" == "$banned_model" ]]; then
                echo "ERROR: --metaswarm requires premium models; '$selected_model' is banned for metaswarm sub-agents." >&2
                echo "Use --models $PREMIUM_METASWARM_MODELS or omit --model/--models for the premium default rotation." >&2
                exit 1
            fi
        done
    done
fi

seed_metaswarm_commander_manifests() {
    $METASWARM || return 0
    [[ -d "${BASE_DIR}" ]] || return 0

    mkdir -p "${BASE_DIR}/queue"

    python3 - "$BASE_DIR" "$RUN_ID" "$REPO_PATH" "$WORKER_COUNT" "${MODELS:-$MODEL}" "$PREMIUM_METASWARM_MODELS" "$BANNED_METASWARM_MODELS" <<'PY'
import json
import os
import pathlib
import sys
import time

base = pathlib.Path(sys.argv[1])
run_id = sys.argv[2]
repo_path = sys.argv[3]
commander_count = int(sys.argv[4])
models = [m.strip() for m in sys.argv[5].split(",") if m.strip()]
premium_models = [m.strip() for m in sys.argv[6].split(",") if m.strip()]
banned_models = [m.strip() for m in sys.argv[7].split() if m.strip()]
now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

def write_json_atomic(path: pathlib.Path, data: dict) -> None:
    tmp = path.with_name(f".tmp-{path.name}")
    tmp.write_text(json.dumps(data, indent=2))
    tmp.replace(path)

state_path = base / "state.json"
objective = os.environ.get("STAMPEDE_OBJECTIVE", "").strip()
if state_path.exists():
    try:
        state = json.loads(state_path.read_text())
        if isinstance(state, dict) and state.get("objective"):
            objective = str(state["objective"])
    except json.JSONDecodeError as exc:
        print(f"WARN: could not read existing state objective: {exc}", file=sys.stderr)
if not objective:
    objective = f"Metaswarm commander run for {run_id}; inspect the repository and produce a commander bundle."

queue = base / "queue"
claimed = base / "claimed"
queue.mkdir(parents=True, exist_ok=True)
claimed.mkdir(parents=True, exist_ok=True)
created = 0
repaired = 0
for idx in range(1, commander_count + 1):
    commander_id = f"commander-{idx:03d}"
    model = models[(idx - 1) % len(models)]
    manifest = {
        "task_id": commander_id,
        "run_id": run_id,
        "kind": "commander",
        "role": "commander",
        "title": f"Metaswarm commander {idx}",
        "objective": objective,
        "repo_path": repo_path,
        "branch": f"havoc-swarm/{run_id}/{commander_id}",
        "commander_id": commander_id,
        "model": model,
        "profile": "metaswarm",
        "swarm_scale": "ss-250",
        "per_commander_full_swarm": True,
        "model_policy": "premium",
        "premium_model_pool": premium_models,
        "banned_child_models": banned_models,
        "constraints": {
            "max_workers": 250,
            "squad_leads_per_commander": 50,
            "workers_per_squad_lead": 5,
            "workers_per_commander": 250,
            "model_policy": "premium",
            "required_status_values": ["success", "partial", "failed"],
        },
        "depth_config": {
            "current_depth": 1,
            "max_depth": 3,
            "can_launch": True,
        },
        "depth_budget": {
            "squads_allocated": 50,
            "squads_max": 50,
        },
        "collab": {
            "path": str(base / "collab"),
            "protocol": str(base / "collab" / "protocol.json"),
        },
        "created_at": now,
    }
    queue_path = queue / f"{commander_id}.json"
    claimed_path = claimed / f"{commander_id}.json"
    if claimed_path.exists():
        continue
    if queue_path.exists():
        try:
            loaded = json.loads(queue_path.read_text())
        except json.JSONDecodeError:
            loaded = {}
        if not isinstance(loaded, dict) or loaded.get("commander_id") != commander_id or loaded.get("task_id") != commander_id:
            write_json_atomic(queue_path, manifest)
            repaired += 1
        continue
    write_json_atomic(queue_path, manifest)
    created += 1

print(f"  ✓ Ensured {commander_count} deterministic metaswarm commander manifests (created {created}, repaired {repaired})")
PY
}

# Run directory inside the repo — agents can always access repo files
STAMPEDE_BASE="$REPO_PATH/.stampede"
BASE_DIR="${STAMPEDE_BASE}/${RUN_ID}"
SESSION_NAME="stampede-${RUN_ID}"
PIDS_DIR="${BASE_DIR}/pids"
STAMPEDE_EXIT_REASON="launcher_exit"
STAMPEDE_CLEANUP_RUNNING=false

stampede_cleanup_after_failure() {
    local status="$1"
    local reason="${2:-$STAMPEDE_EXIT_REASON}"
    if $TEARDOWN || $DRY_RUN || $PREFLIGHT; then
        return
    fi
    if [[ "$STAMPEDE_CLEANUP_RUNNING" == "true" ]]; then
        return
    fi
    STAMPEDE_CLEANUP_RUNNING=true

    echo "⚠ Stampede launcher exiting non-zero ($status: $reason); cleaning run-owned processes." >&2

    if [[ -d "${PIDS_DIR:-}" ]]; then
        for pidfile in "${PIDS_DIR}"/*.pid; do
            [[ -f "$pidfile" ]] || continue
            local wpid
            wpid=$(cat "$pidfile" 2>/dev/null || true)
            if [[ -n "$wpid" ]] && kill -0 "$wpid" 2>/dev/null; then
                kill "$wpid" 2>/dev/null || true
            fi
        done
        rm -f "${PIDS_DIR}"/*.pid 2>/dev/null || true
    fi

    if [[ -n "${SESSION_NAME:-}" ]] && tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
    fi

    if [[ -f "${BASE_DIR:-}/state.json" ]]; then
        python3 - "${BASE_DIR}/state.json" "$status" "$reason" <<'PY' || true
import json
import pathlib
import sys
import time

path = pathlib.Path(sys.argv[1])
status = int(sys.argv[2])
reason = sys.argv[3]
state = json.loads(path.read_text())
state["status"] = "failed"
state["phase"] = reason
state["exit_code"] = status
state["updated_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
tmp = path.with_name(path.name + ".tmp")
tmp.write_text(json.dumps(state, indent=2))
tmp.replace(path)
PY
    fi
}

stampede_on_exit() {
    local status=$?
    if [[ "$status" -ne 0 ]]; then
        stampede_cleanup_after_failure "$status" "$STAMPEDE_EXIT_REASON"
    fi
}

trap 'STAMPEDE_EXIT_REASON="launcher_error"' ERR
trap 'STAMPEDE_EXIT_REASON="interrupted"; exit 130' INT
trap 'STAMPEDE_EXIT_REASON="terminated"; exit 143' TERM
trap 'stampede_on_exit' EXIT

# Preflight mode: test agent access and exit
if $PREFLIGHT; then
    do_preflight
fi

# Count tasks (for both dry-run and live run)
if [[ -d "${BASE_DIR}/queue" ]]; then
    TASK_COUNT=$(find "${BASE_DIR}/queue" -maxdepth 1 -name '*.json' ! -name '.tmp-*' -type f 2>/dev/null | wc -l | tr -d ' ')
else
    TASK_COUNT=0
fi

# Dry-run mode: print config and exit
if $DRY_RUN; then
    echo "════════════════════════════════════════════════════════"
    echo "  🦬 STAMPEDE DRY RUN"
    echo "════════════════════════════════════════════════════════"
    echo ""
    echo "  Run ID:       $RUN_ID"
    echo "  Repo:         $REPO_PATH"
    if $METASWARM; then
        echo "  Commander Count: $WORKER_COUNT"
        echo "  Profile:      metaswarm (full SS-250 per commander)"
    else
        echo "  Worker Count: $WORKER_COUNT"
    fi
    
    IFS=',' read -ra MODEL_LIST_PREVIEW <<< "${MODELS:-$MODEL}"
    if [[ ${#MODEL_LIST_PREVIEW[@]} -gt 1 ]]; then
        echo "  Models:       ${MODEL_LIST_PREVIEW[*]} (rotating)"
    else
        echo "  Model:        ${MODEL_LIST_PREVIEW[0]}"
    fi
    
    echo "  Tasks:        $TASK_COUNT"
    echo "  Session:      $SESSION_NAME"
    echo "  Base Dir:     $BASE_DIR"
    echo ""
    
    if [[ ! -d "$BASE_DIR" ]]; then
        echo "  ⚠️  Run directory does not exist: $BASE_DIR"
    elif [[ "$TASK_COUNT" -eq 0 ]]; then
        echo "  ⚠️  No tasks in queue"
    else
        echo "  ✅ Run directory exists with $TASK_COUNT tasks ready"
    fi
    
    echo ""
    echo "  Would create tmux session with:"
    for ((i = 1; i <= WORKER_COUNT; i++)); do
        worker_model_idx=$(( (i - 1) % ${#MODEL_LIST_PREVIEW[@]} ))
        worker_model="${MODEL_LIST_PREVIEW[$worker_model_idx]}"
        if $METASWARM; then
            printf "    • Commander %d → %s · full SS-250 swarm · %s/commanders/commander-%03d/\n" "$i" "$worker_model" "$BASE_DIR" "$i"
        else
            echo "    • Worker $i → $worker_model"
        fi
    done
    echo ""
    echo "════════════════════════════════════════════════════════"
    exit 0
fi

if [[ ! -d "$BASE_DIR" ]]; then
    echo "ERROR: Run directory not found: $BASE_DIR" >&2
    exit 1
fi

seed_metaswarm_commander_manifests
if [[ -d "${BASE_DIR}/queue" ]]; then
    TASK_COUNT=$(find "${BASE_DIR}/queue" -maxdepth 1 -name '*.json' ! -name '.tmp-*' -type f 2>/dev/null | wc -l | tr -d ' ')
fi

if [[ "$TASK_COUNT" -eq 0 ]]; then
    echo "ERROR: No tasks in queue (${BASE_DIR}/queue)" >&2
    exit 1
fi

mkdir -p "$PIDS_DIR" "${BASE_DIR}/scripts" "${BASE_DIR}/logs"
if $METASWARM; then
    mkdir -p "${BASE_DIR}/commanders" "${BASE_DIR}/collab"
fi

# Prevent duplicate sessions (Landmine #12)
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "⚠ Existing session $SESSION_NAME found. Tearing down for fresh launch."
    tmux kill-session -t "$SESSION_NAME"
    sleep 1
fi

# ─── Model Rotation ──────────────────────────────────────────────────────────
# Parse --models into an array for per-worker model assignment
IFS=',' read -ra MODEL_LIST <<< "${MODELS:-$MODEL}"
MODEL_COUNT=${#MODEL_LIST[@]}

if $METASWARM; then
    echo "Launching stampede metaswarm: $WORKER_COUNT commanders"
else
    echo "Launching stampede fleet: $WORKER_COUNT workers"
fi
echo "  Run ID:  $RUN_ID"
echo "  Repo:    $REPO_PATH"
echo "  Tasks:   $TASK_COUNT"
echo "  Session: $SESSION_NAME"
if [[ $MODEL_COUNT -gt 1 ]]; then
    if $METASWARM; then
        echo "  Models:  ${MODEL_LIST[*]} (rotating across $WORKER_COUNT commanders)"
    else
        echo "  Models:  ${MODEL_LIST[*]} (rotating across $WORKER_COUNT workers)"
    fi
else
    if $METASWARM; then
        echo "  Model:   ${MODEL_LIST[0]} × $WORKER_COUNT commanders"
    else
        echo "  Model:   ${MODEL_LIST[0]} × $WORKER_COUNT"
    fi
fi
echo ""

# Write fleet.json so the monitor knows which model and role each pane runs
METASWARM_PY=False
if $METASWARM; then METASWARM_PY=True; fi
python3 -c "
import json, os, sys, time
models = '${MODELS:-$MODEL}'.split(',')
metaswarm = ${METASWARM_PY}
base = '${BASE_DIR}'
run_id = '${RUN_ID}'
now = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())

def write_json_atomic(path, data):
    tmp = f'{path}.tmp'
    with open(tmp, 'w') as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, path)

collab = None
if metaswarm:
    collab_dir = f'{base}/collab'
    os.makedirs(collab_dir, exist_ok=True)
    ledger_events = {
        'proposals': 'proposal',
        'reviews': 'peer_review',
        'improvements': 'improvement',
        'consensus': 'consensus',
        'broadcasts': 'broadcast',
    }
    ledgers = {name: f'{collab_dir}/{name}.jsonl' for name in ledger_events}
    for ledger_path in ledgers.values():
        open(ledger_path, 'a').close()
    protocol = {
        'version': '1.0',
        'run_id': run_id,
        'profile': 'metaswarm',
        'ledgers': {
            name: {
                'path': ledgers[name],
                'event': ledger_events[name],
            }
            for name in ledger_events
        },
        'atomic_append_guidance': {
            'mode': 'append-only-jsonl',
            'rules': [
                'Append exactly one complete JSON object per line.',
                'Open ledgers in append mode so writers use O_APPEND semantics.',
                'Never rewrite, truncate, sort, or compact ledgers during a run.',
                'Readers must tolerate absent files and malformed trailing lines.',
                'Use stable item_id values so proposals, reviews, improvements, consensus, and broadcasts can reference each other.',
            ],
        },
        'commander_workflow': {
            'sequence': ['propose', 'peer_review', 'improve', 'consensus', 'broadcast', 'adopt'],
            'description': 'propose -> peer_review -> improve -> consensus -> broadcast -> adopt',
        },
        'required_fields': [
            'ts',
            'run_id',
            'commander_id',
            'event',
            'item_id',
            'summary',
            'evidence',
            'confidence',
            'source_refs',
        ],
    }
    write_json_atomic(f'{collab_dir}/protocol.json', protocol)
    collab = {
        'path': collab_dir,
        'protocol': f'{collab_dir}/protocol.json',
        'ledgers': ledgers,
        'workflow': protocol['commander_workflow']['sequence'],
        'counts': {name: 0 for name in ledger_events},
    }
    state_path = f'{base}/state.json'
    try:
        run_state = {}
        if os.path.exists(state_path):
            with open(state_path) as f:
                loaded_state = json.load(f)
            if isinstance(loaded_state, dict):
                run_state = loaded_state
        run_state.setdefault('run_id', run_id)
        run_state.setdefault('base', base)
        run_state.setdefault('phase', 'launching')
        run_state['profile'] = 'metaswarm'
        run_state['collab'] = collab
        run_state['updated_at'] = now
        write_json_atomic(state_path, run_state)
    except Exception as exc:
        print(f'WARN: failed to update state.json: {exc}', file=sys.stderr)

fleet = {}
for i in range(1, ${WORKER_COUNT} + 1):
    m = models[(i - 1) % len(models)]
    if metaswarm:
        cid = f'commander-{i:03d}'
        progress_dir = f'{base}/commanders/{cid}'
        os.makedirs(f'{progress_dir}/atoms', exist_ok=True)
        os.makedirs(f'{progress_dir}/logs', exist_ok=True)
        fleet[cid] = {
            'model': m,
            'slot': i,
            'role': 'commander',
            'profile': 'metaswarm',
            'swarm_scale': 'ss-250',
            'per_commander_full_swarm': True,
            'squad_leads_per_commander': 50,
            'workers_per_squad_lead': 5,
            'workers_per_commander': 250,
            'model_policy': 'premium',
            'premium_model_pool': [
                'claude-opus-4.7',
                'gpt-5.5',
                'claude-opus-4.6',
                'gpt-5.4',
                'claude-opus-4.5',
                'gpt-5.2',
                'claude-sonnet-4.6',
                'gpt-5.3-codex',
                'claude-sonnet-4.5',
                'gpt-5.2-codex'
            ],
            'banned_child_models': [
                'claude-haiku-4.5',
                'gpt-5.4-mini',
                'gpt-5-mini',
                'gpt-4.1'
            ],
            'depth_budget': {
                'squads_allocated': 50,
                'squads_max': 50
            },
            'telemetry_contract': {
                'state_file': f'{progress_dir}/swarm-state.json',
                'child_ledger': f'{progress_dir}/child-agents.jsonl',
                'sub_agent_ledger': f'{progress_dir}/child-agents.jsonl',
                'launch_proof_required': True
            },
            'progress_dir': progress_dir,
            'collab': collab
        }
        state = {
            'run_id': run_id,
            'commander_id': cid,
            'task_id': None,
            'role': 'commander',
            'profile': 'metaswarm',
            'collab': collab,
            'swarm_scale': 'ss-250',
            'per_commander_full_swarm': True,
            'phase': 'commander_pane_starting',
            'status': 'starting',
            'launch_proof_required': True,
            'launch_proof': {
                'squad_leads_started': 0,
                'workers_started': 0,
                'first_child_started_at': None,
                'last_child_started_at': None
            },
            'depth_budget': {
                'squads_allocated': 50,
                'squads_max': 50
            },
            'model_policy': 'premium',
            'premium_model_pool': [
                'claude-opus-4.7',
                'gpt-5.5',
                'claude-opus-4.6',
                'gpt-5.4',
                'claude-opus-4.5',
                'gpt-5.2',
                'claude-sonnet-4.6',
                'gpt-5.3-codex',
                'claude-sonnet-4.5',
                'gpt-5.2-codex'
            ],
            'banned_child_models': [
                'claude-haiku-4.5',
                'gpt-5.4-mini',
                'gpt-5-mini',
                'gpt-4.1'
            ],
            'telemetry': {
                'squad_leads_target': 50,
                'squad_leads_launched': 0,
                'squad_leads_running': 0,
                'squad_leads_completed': 0,
                'squad_leads_failed': 0,
                'workers_per_squad_lead': 5,
                'workers_target': 250,
                'workers_launched': 0,
                'workers_running': 0,
                'workers_completed': 0,
                'workers_failed': 0,
                'atoms_received': 0,
                'children_failed': 0
            },
            'updated_at': now,
            'last_heartbeat_at': now
        }
        with open(f'{progress_dir}/swarm-state.json', 'w') as sf:
            json.dump(state, sf, indent=2)
        with open(f'{progress_dir}/child-agents.jsonl', 'w') as lf:
            lf.write(json.dumps({
                'ts': now,
                'event': 'commander_registered',
                'commander_id': cid,
                'squad_leads_target': 50,
                'workers_target': 250
            }) + '\n')
    else:
        fleet[f'worker-{i}'] = {'model': m, 'slot': i, 'role': 'worker'}
with open(f'{base}/fleet.json', 'w') as f:
    json.dump(fleet, f, indent=2)
"

if ! run_default_agent_launch_preflight; then
    exit 1
fi

get_worker_model() {
    local worker_num="$1"
    local idx=$(( (worker_num - 1) % MODEL_COUNT ))
    echo "${MODEL_LIST[$idx]}"
}

# ─── Build Worker Command ────────────────────────────────────────────────────
# Escape arbitrary text as a single-quoted bash word (safe to embed in a command line).
shell_escape_squote() {
    local s="$1"
    s=${s//\'/\'"\'"\'}
    printf "'%s'" "$s"
}

build_worker_script() {
    local worker_num="$1"
    local worker_model
    worker_model=$(get_worker_model "$worker_num")
    local script="${BASE_DIR}/scripts/agent-${worker_num}.sh"
    local agent_name="stampede-agent"
    local role_label="agent"
    local agent_log="${BASE_DIR}/logs/agent-${worker_num}.log"
    local prompt="You are stampede agent #${worker_num} for run ${RUN_ID}. FOLLOW YOUR AGENT INSTRUCTIONS EXACTLY. Claim ONE task at a time from ${BASE_DIR}/queue/ via atomic mv to ${BASE_DIR}/claimed/. Fully complete each task before claiming the next. Write results atomically to ${BASE_DIR}/results/. Log to ${BASE_DIR}/logs/. Your repo is ${REPO_PATH}. Work until queue is empty then exit."

    if $METASWARM; then
        local commander_id
        commander_id=$(printf "commander-%03d" "$worker_num")
        local progress_dir="${BASE_DIR}/commanders/${commander_id}"
        local collab_dir="${BASE_DIR}/collab"
        mkdir -p "$progress_dir"/{atoms,logs}
        agent_name="stampede-commander"
        role_label="commander"
        agent_log="${progress_dir}/logs/commander-cli.log"
        prompt="You are ${commander_id} for metaswarm run ${RUN_ID}. FOLLOW YOUR COMMANDER AGENT INSTRUCTIONS EXACTLY. Your exact commander task is pre-claimed at ${BASE_DIR}/claimed/${commander_id}.json by the launcher. Read that manifest; do not claim any other queue item. If task_id or commander_id does not equal ${commander_id}, write a failed bundle and stop."
        prompt="${prompt} Your progress directory is ${progress_dir}. You MUST launch and track your own sub-agent swarm; do not satisfy this by delegating to one wrapped swarm-command agent."
        prompt="${prompt} Build the Swarm Command Context Capsule with profile=metaswarm, swarm_scale=ss-250, per_commander_full_swarm=true, constraints.max_workers=250, depth_budget.squads_allocated=50, squad_leads_per_commander=50, workers_per_squad_lead=5, and workers_per_commander=250."
        prompt="${prompt} Use premium model policy for every Squad Lead and Worker: rotate claude-opus-4.7, gpt-5.5, claude-opus-4.6, gpt-5.4, claude-opus-4.5, gpt-5.2, claude-sonnet-4.6, gpt-5.3-codex, claude-sonnet-4.5, and gpt-5.2-codex. Do NOT use claude-haiku-4.5, gpt-5.4-mini, gpt-5-mini, or gpt-4.1 for metaswarm sub-agents."
        prompt="${prompt} Launch 50 non-leaf Squad Leads and require each Squad Lead to launch exactly 5 premium leaf Workers (250 Workers total) unless a concrete platform launch error or operator stop makes the bundle partial. Use max_in_flight=32 per commander unless the platform reports a lower ceiling; this is a concurrency cap, not a total cap. Squad Leads are supervisors, not leaf nodes: do not leaf-lock Squad Lead prompts, launch them with an agent profile that can use the task tool, and require Worker launch_started telemetry with role=worker and parent_id before incrementing workers_launched. Representative sampling is forbidden: do not stop at 8, 16, 32, or 50 children because the findings feel sufficient; keep refilling bounded batches until workers_launched=250 or a real platform blocker is recorded."
        prompt="${prompt} Append every sub-agent launch/update to ${progress_dir}/child-agents.jsonl including the model field, and keep ${progress_dir}/swarm-state.json updated in real time with launched/running/completed/failed counts."
        prompt="${prompt} Collaboration bus: ${collab_dir}/ contains protocol.json and append-only JSONL ledgers proposals.jsonl, reviews.jsonl, improvements.jsonl, consensus.jsonl, and broadcasts.jsonl. Follow workflow propose -> peer_review -> improve -> consensus -> broadcast -> adopt. Publish a proposal early to proposals.jsonl using required fields ts, run_id, commander_id, event, item_id, summary, evidence, confidence, and source_refs; review other commanders' proposals in real time, append peer reviews to reviews.jsonl, write improvements to improvements.jsonl, promote consensus to consensus.jsonl, consume broadcasts.jsonl, append broadcasts when consensus should be adopted, and include adopted consensus item_ids and source_refs in bundle.json plus the final result."
        prompt="${prompt} Final bundle status must be success, partial, or failed; write it atomically to ${progress_dir}/bundle.json plus ${BASE_DIR}/results/. Your repo is ${REPO_PATH}. Stop after your commander bundle is complete."
        if [[ "${STAMPEDE_METASWARM_NO_GATES:-0}" == "1" ]]; then
            prompt="${prompt} Operator priority for this run: do not abort merely because of elapsed time or local budget estimates, but DO enforce the commander bounded launch, rate-limit backoff, and platform-capacity circuit breaker rules. If the platform refuses launches, record exact blockers, stop request-only spinning, and write a partial terminal bundle with exact counts."
        fi
    fi

    cat > "$script" << AGENTEOF
#!/usr/bin/env bash
set -euo pipefail
cd "${REPO_PATH}"
export STAMPEDE_RUN_ID="${RUN_ID}"
export STAMPEDE_RUN_DIR="${BASE_DIR}"
export STAMPEDE_ROLE="${role_label}"
export STAMPEDE_AGENT_LOG="${agent_log}"
AGENTEOF
    if $METASWARM; then
        cat >> "$script" << AGENTEOF
export STAMPEDE_COMMANDER_ID="${commander_id}"
export STAMPEDE_PROGRESS_DIR="${progress_dir}"
export STAMPEDE_COLLAB_DIR="${BASE_DIR}/collab"
export STAMPEDE_COLLAB_PROTOCOL="${BASE_DIR}/collab/protocol.json"
export STAMPEDE_COLLAB_PROPOSALS="${BASE_DIR}/collab/proposals.jsonl"
export STAMPEDE_COLLAB_REVIEWS="${BASE_DIR}/collab/reviews.jsonl"
export STAMPEDE_COLLAB_IMPROVEMENTS="${BASE_DIR}/collab/improvements.jsonl"
export STAMPEDE_COLLAB_CONSENSUS="${BASE_DIR}/collab/consensus.jsonl"
export STAMPEDE_COLLAB_BROADCASTS="${BASE_DIR}/collab/broadcasts.jsonl"
export STAMPEDE_SWARM_SCALE="ss-250"
export STAMPEDE_PER_COMMANDER_FULL_SWARM="1"
export STAMPEDE_MODEL_POLICY="premium"
export STAMPEDE_COMMANDER_MODEL="${worker_model}"
export STAMPEDE_PREMIUM_MODEL_POOL="${PREMIUM_METASWARM_MODELS}"
export STAMPEDE_BANNED_CHILD_MODELS="${BANNED_METASWARM_MODELS}"
export STAMPEDE_SQUAD_LEADS_PER_COMMANDER="50"
export STAMPEDE_WORKERS_PER_SQUAD_LEAD="5"
export STAMPEDE_WORKERS_PER_COMMANDER="250"
export STAMPEDE_CHILD_AGENT_LEDGER="${progress_dir}/child-agents.jsonl"
AGENTEOF
        cat >> "$script" <<'AGENTEOF'
stampede_synthesize_commander_bundle() {
  local requested_status="$1"
  local phase="$2"
  local exit_code="${3:-0}"
  python3 - "${STAMPEDE_RUN_DIR}" "${STAMPEDE_PROGRESS_DIR}" "${requested_status}" "${phase}" "${exit_code}" "${STAMPEDE_AGENT_LOG}" <<'PY'
import json
import pathlib
import re
import sys
import time

base = pathlib.Path(sys.argv[1])
progress_dir = pathlib.Path(sys.argv[2])
requested_status = sys.argv[3]
phase = sys.argv[4]
exit_code = int(sys.argv[5])
log_path = pathlib.Path(sys.argv[6])
now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

def read_json(path: pathlib.Path, default):
    try:
        return json.loads(path.read_text()) if path.exists() else default
    except Exception:
        return default

def write_json_atomic(path: pathlib.Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(data, indent=2))
    tmp.replace(path)

def scrub(text: str) -> str:
    return re.sub(r"[A-Za-z0-9_=-]{30,}", "[REDACTED]", text)[-4000:]

state_file = progress_dir / "swarm-state.json"
state = read_json(state_file, {})
telemetry = state.get("telemetry") if isinstance(state.get("telemetry"), dict) else {}
commander_id = str(state.get("commander_id") or progress_dir.name)
task_id = str(state.get("task_id") or commander_id)

def metric(*names: str, default: int = 0) -> int:
    for name in names:
        for source in (telemetry, state):
            try:
                value = source.get(name)
            except AttributeError:
                continue
            if value is None:
                continue
            try:
                return int(value)
            except (TypeError, ValueError):
                continue
    return default

def child_level(item: dict, child_id: str) -> str:
    role = str(item.get("role") or item.get("agent_type") or item.get("kind") or "").lower()
    if role in {"squad_lead", "squad-lead", "squad"} or child_id.startswith("sq-"):
        return "squad"
    if role in {"worker", "sub-agent", "sub_agent"} or child_id.startswith("wkr-"):
        return "worker"
    return "other"

def commentary_high_water(base: pathlib.Path, commander_id: str) -> dict:
    high = {
        "squad_leads_launched": 0,
        "workers_launched": 0,
        "child_agents_running": 0,
        "child_agents_completed": 0,
        "child_agents_failed": 0,
    }
    paths = [base / "orchestrator-commentary.jsonl", base / "orchestrator-commentary.json"]
    pattern = re.compile(
        rf"{re.escape(commander_id)}\s+[^·]*·\s+squads\s+(\d+)/(\d+)\s+·\s+"
        r"sub-agents\s+(\d+)/(\d+)\s+·\s+run\s+(\d+)\s+done\s+(\d+)\s+fail\s+(\d+)"
    )
    for path in paths:
        if not path.exists():
            continue
        records = []
        try:
            if path.suffix == ".jsonl":
                for line in path.read_text(errors="replace").splitlines():
                    if not line.strip():
                        continue
                    try:
                        records.append(json.loads(line))
                    except Exception:
                        continue
            else:
                records.append(json.loads(path.read_text()))
        except Exception:
            continue
        for record in records:
            lines = record.get("lines") if isinstance(record, dict) else []
            if not isinstance(lines, list):
                continue
            for line in lines:
                if not isinstance(line, str):
                    continue
                match = pattern.search(line)
                if not match:
                    continue
                squads, _, workers, _, running, done, failed = (int(value) for value in match.groups())
                high["squad_leads_launched"] = max(high["squad_leads_launched"], squads)
                high["workers_launched"] = max(high["workers_launched"], workers)
                high["child_agents_running"] = max(high["child_agents_running"], running)
                high["child_agents_completed"] = max(high["child_agents_completed"], done)
                high["child_agents_failed"] = max(high["child_agents_failed"], failed)
    return high

ledger_counts = {}
blockers = []
ledger = progress_dir / "child-agents.jsonl"
squad_seen = set()
squad_done = set()
squad_failed = set()
worker_seen = set()
worker_done = set()
worker_failed = set()
if ledger.exists():
    for line in ledger.read_text(errors="replace").splitlines():
        try:
            item = json.loads(line)
        except Exception:
            continue
        event = str(item.get("event") or "unknown")
        status_text = str(item.get("status") or event).lower()
        child_id = str(item.get("child_id") or item.get("agent_id") or item.get("id") or "")
        ledger_counts[event] = ledger_counts.get(event, 0) + 1
        if child_id:
            level = child_level(item, child_id)
            if level == "squad":
                squad_seen.add(child_id)
                if event in {"completed", "success"} or status_text in {"success", "done", "completed", "complete"}:
                    squad_done.add(child_id)
                elif event in {"failed", "launch_failed"} or status_text in {"failed", "error", "blocked"}:
                    squad_failed.add(child_id)
            elif level == "worker":
                worker_seen.add(child_id)
                if event in {"completed", "success"} or status_text in {"success", "done", "completed", "complete"}:
                    worker_done.add(child_id)
                elif event in {"failed", "launch_failed"} or status_text in {"failed", "error", "blocked"}:
                    worker_failed.add(child_id)
        if item.get("error") or event in {"launch_blocked", "launch_failed", "failed", "commander_launch_failed"}:
            blockers.append({
                k: item.get(k)
                for k in ("ts", "event", "child_id", "role", "model", "error", "exit_code", "detail")
                if k in item
            })

detail = ""
if log_path.exists():
    detail = scrub(log_path.read_text(errors="replace"))

status = requested_status
if requested_status == "auto":
    existing = str(state.get("status") or "").lower()
    if existing in {"partial", "failed"}:
        status = existing
    else:
        squad_target = metric("squad_leads_target", "squads_target", default=50)
        worker_target = metric("workers_target", default=250)
        commentary = commentary_high_water(base, commander_id)
        squads_launched = max(metric("squad_leads_launched", "squad_leads_started"), len(squad_seen), commentary["squad_leads_launched"])
        squads_done = max(metric("squad_leads_completed"), len(squad_done))
        workers_launched = max(metric("workers_launched", "workers_started"), len(worker_seen), commentary["workers_launched"])
        workers_done = max(metric("workers_completed", "atoms_received"), len(worker_done))
        workers_failed = max(metric("workers_failed", "children_failed"), len(worker_failed))
        launch_proof_verified = (
            squads_launched >= squad_target
            and squads_done >= squad_target
            and workers_launched >= worker_target
            and workers_done >= worker_target
            and workers_failed == 0
        )
        status = "success" if launch_proof_verified else "partial"

reason = phase
if status == "success" and requested_status == "auto":
    reason = "complete"

commentary = commentary_high_water(base, commander_id)
squads_launched = max(metric("squad_leads_launched", "squad_leads_started"), len(squad_seen), commentary["squad_leads_launched"])
squads_done = max(metric("squad_leads_completed"), len(squad_done))
squads_failed = max(metric("squad_leads_failed"), len(squad_failed))
workers_launched = max(metric("workers_launched", "workers_started"), len(worker_seen), commentary["workers_launched"])
workers_done = max(metric("workers_completed", "atoms_received"), len(worker_done))
workers_failed = max(metric("workers_failed", "children_failed"), len(worker_failed))
telemetry = dict(telemetry)
telemetry.update({
    "squad_leads_launched": squads_launched,
    "squad_leads_completed": squads_done,
    "squad_leads_failed": squads_failed,
    "workers_launched": workers_launched,
    "workers_completed": workers_done,
    "workers_failed": workers_failed,
    "child_agents_seen": max(squads_launched + workers_launched, len(squad_seen) + len(worker_seen)),
    "child_agents_completed": max(squads_done + workers_done, commentary["child_agents_completed"]),
    "child_agents_failed": max(squads_failed + workers_failed, commentary["child_agents_failed"]),
    "child_agents_running": commentary["child_agents_running"],
})
telemetry_high_water = {
    "squad_leads_launched": squads_launched,
    "workers_launched": workers_launched,
    "child_agents_seen": telemetry["child_agents_seen"],
    "child_agents_completed": telemetry["child_agents_completed"],
    "child_agents_failed": telemetry["child_agents_failed"],
    "child_agents_running": telemetry["child_agents_running"],
    "sources": ["swarm-state.json", "child-agents.jsonl", "orchestrator-commentary.jsonl"],
}

bundle = {
    "run_id": state.get("run_id"),
    "commander_id": commander_id,
    "task_id": task_id,
    "status": status,
    "phase": reason,
    "synthesized_by": "stampede-launcher",
    "synthesized_at": now,
    "exit_code": exit_code,
    "telemetry": telemetry,
    "telemetry_high_water": telemetry_high_water,
    "ledger_counts": ledger_counts,
    "atoms": sorted(p.name for p in (progress_dir / "atoms").glob("*.json")),
    "blockers": blockers[-20:],
    "error": state.get("error"),
    "log_tail": detail if status == "failed" else "",
    "source_refs": [
        str(state_file),
        str(ledger),
        str(log_path),
    ],
}
write_json_atomic(progress_dir / "bundle.json", bundle)
write_json_atomic(base / "results" / f"{commander_id}.json", bundle)

state["status"] = status
state["phase"] = reason
state["telemetry"] = telemetry
state["telemetry_high_water"] = telemetry_high_water
state["updated_at"] = now
state["last_heartbeat_at"] = now
state["bundle_path"] = str(progress_dir / "bundle.json")
state["result_path"] = str(base / "results" / f"{commander_id}.json")
write_json_atomic(state_file, state)

with ledger.open("a") as f:
    f.write(json.dumps({
        "ts": now,
        "event": "bundle_synthesized",
        "commander_id": commander_id,
        "status": status,
        "phase": reason,
        "exit_code": exit_code,
    }) + "\n")
PY
}

set +e
python3 - "${STAMPEDE_RUN_DIR}" "${STAMPEDE_COMMANDER_ID}" "${STAMPEDE_PROGRESS_DIR}" "${STAMPEDE_COMMANDER_MODEL}" <<'PY'
import json
import pathlib
import sys
import time

base = pathlib.Path(sys.argv[1])
commander_id = sys.argv[2]
progress_dir = pathlib.Path(sys.argv[3])
model = sys.argv[4]
now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

def write_json_atomic(path: pathlib.Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(data, indent=2))
    tmp.replace(path)

def fail(reason: str, detail: str) -> None:
    state_file = progress_dir / "swarm-state.json"
    state = json.loads(state_file.read_text()) if state_file.exists() else {}
    state.update({
        "commander_id": commander_id,
        "task_id": state.get("task_id") or commander_id,
        "status": "failed",
        "phase": reason,
        "updated_at": now,
        "last_heartbeat_at": now,
        "error": {"kind": reason, "detail": detail},
    })
    write_json_atomic(state_file, state)
    with (progress_dir / "child-agents.jsonl").open("a") as f:
        f.write(json.dumps({
            "ts": now,
            "event": reason,
            "commander_id": commander_id,
            "detail": detail,
        }) + "\n")
    raise SystemExit(detail)

queue_path = base / "queue" / f"{commander_id}.json"
claimed_path = base / "claimed" / f"{commander_id}.json"
claimed_path.parent.mkdir(parents=True, exist_ok=True)
if not claimed_path.exists():
    if not queue_path.exists():
        fail("task_binding_failed", f"missing exact commander manifest {queue_path}")
    queue_path.rename(claimed_path)

try:
    manifest = json.loads(claimed_path.read_text())
except json.JSONDecodeError as exc:
    fail("task_binding_failed", f"invalid commander manifest JSON: {exc}")

if manifest.get("commander_id") != commander_id or manifest.get("task_id") != commander_id:
    fail(
        "task_binding_failed",
        f"manifest mismatch: expected {commander_id}, got commander_id={manifest.get('commander_id')} task_id={manifest.get('task_id')}",
    )

manifest["claimed_by"] = commander_id
manifest["claimed_at"] = now
manifest["status"] = "claimed"
write_json_atomic(claimed_path, manifest)

state_file = progress_dir / "swarm-state.json"
state = json.loads(state_file.read_text()) if state_file.exists() else {}
state.update({
    "commander_id": commander_id,
    "task_id": commander_id,
    "claimed_manifest": str(claimed_path),
    "model": model,
    "phase": "commander_claimed",
    "status": "running",
    "updated_at": now,
    "last_heartbeat_at": now,
})
write_json_atomic(state_file, state)
with (progress_dir / "child-agents.jsonl").open("a") as f:
    f.write(json.dumps({
        "ts": now,
        "event": "task_claimed",
        "commander_id": commander_id,
        "task_id": commander_id,
        "claimed_manifest": str(claimed_path),
    }) + "\n")
PY
binding_status=$?
set -e
if [[ "$binding_status" -ne 0 ]]; then
  stampede_synthesize_commander_bundle "failed" "task_binding_failed" "$binding_status"
  exit "$binding_status"
fi
AGENTEOF
    fi
    cat >> "$script" << AGENTEOF
echo '⚡ ${worker_model} · ${role_label} claiming task...'
AGENTEOF

    if [[ -n "$AGENT_CMD" ]]; then
        local prompt_q model_q cmd
        prompt_q=$(shell_escape_squote "$prompt")
        model_q=$(shell_escape_squote "$worker_model")
        local prompt_placeholder model_placeholder dq_prompt_placeholder dq_model_placeholder sq_prompt_placeholder sq_model_placeholder
        prompt_placeholder="{prompt}"
        model_placeholder="{model}"
        dq_prompt_placeholder="\"{prompt}\""
        dq_model_placeholder="\"{model}\""
        sq_prompt_placeholder="'{prompt}'"
        sq_model_placeholder="'{model}'"

        cmd="$AGENT_CMD"
        # Support placeholders used as bare tokens or wrapped in quotes.
        cmd="${cmd//$dq_prompt_placeholder/$prompt_q}"
        cmd="${cmd//$sq_prompt_placeholder/$prompt_q}"
        cmd="${cmd//$prompt_placeholder/$prompt_q}"
        cmd="${cmd//$dq_model_placeholder/$model_q}"
        cmd="${cmd//$sq_model_placeholder/$model_q}"
        cmd="${cmd//$model_placeholder/$model_q}"

        cat >> "$script" <<'AGENTEOF'
set +e
AGENTEOF
        printf '%s\n' "$cmd" >> "$script"
        cat >> "$script" <<'AGENTEOF'
agent_status=$?
set -e
AGENTEOF
    else
        cat >> "$script" << AGENTEOF
set +e
if command -v copilot >/dev/null 2>&1; then
  copilot \\
    --agent "${agent_name}" \\
    --model "${worker_model}" \\
    --allow-all-tools \\
    --autopilot \\
    --max-autopilot-continues "${MAX_AUTOPILOT_CONTINUES}" \\
    --no-ask-user \\
    -p "${prompt}" 2>&1 | tee -a "\${STAMPEDE_AGENT_LOG}"
  agent_status=\${PIPESTATUS[0]}
else
  gh copilot -- \\
    --agent "${agent_name}" \\
    --model "${worker_model}" \\
    --allow-all-tools \\
    --autopilot \\
    --max-autopilot-continues "${MAX_AUTOPILOT_CONTINUES}" \\
    --no-ask-user \\
    -p "${prompt}" 2>&1 | tee -a "\${STAMPEDE_AGENT_LOG}"
  agent_status=\${PIPESTATUS[0]}
fi
set -e
AGENTEOF
    fi

    cat >> "$script" <<'AGENTEOF'
if [[ "${agent_status:-0}" -ne 0 ]]; then
  if [[ "${STAMPEDE_ROLE}" == "commander" ]]; then
    python3 - "${STAMPEDE_PROGRESS_DIR}" "$agent_status" "${STAMPEDE_AGENT_LOG}" <<'PY'
import json
import pathlib
import re
import sys
import time

progress_dir = pathlib.Path(sys.argv[1])
exit_code = int(sys.argv[2])
log_path = pathlib.Path(sys.argv[3])
now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
detail = ""
try:
    detail = log_path.read_text(errors="replace")[-4000:]
    detail = re.sub(r"[A-Za-z0-9_=-]{30,}", "[REDACTED]", detail)
except Exception:
    pass

state_file = progress_dir / "swarm-state.json"
try:
    state = json.loads(state_file.read_text()) if state_file.exists() else {}
    state["phase"] = "commander_launch_failed"
    state["status"] = "failed"
    state["updated_at"] = now
    state["last_heartbeat_at"] = now
    state["error"] = {
        "kind": "copilot_launch_failed",
        "exit_code": exit_code,
        "log": str(log_path),
        "detail": detail,
    }
    tmp = state_file.with_name(state_file.name + ".tmp")
    tmp.write_text(json.dumps(state, indent=2))
    tmp.replace(state_file)
except Exception:
    pass

try:
    with (progress_dir / "child-agents.jsonl").open("a") as f:
        f.write(json.dumps({
            "ts": now,
            "event": "commander_launch_failed",
            "commander_id": progress_dir.name,
            "exit_code": exit_code,
            "log": str(log_path),
            "detail": detail,
        }) + "\n")
except Exception:
    pass
PY
    stampede_synthesize_commander_bundle "failed" "commander_launch_failed" "$agent_status"
  fi
  exit "$agent_status"
fi
if [[ "${STAMPEDE_ROLE}" == "commander" && ! -f "${STAMPEDE_PROGRESS_DIR}/bundle.json" ]]; then
  stampede_synthesize_commander_bundle "auto" "commander_exited_without_bundle" "0"
fi
AGENTEOF

    cat >> "$script" << 'AGENTEOF'
echo '⚡ Done.'
sleep 86400
AGENTEOF
    chmod +x "$script"
    echo "$script"
}

# ─── Create tmux Session with Monitor as pane 0 (top-left) ───────────────────

# Enable remain-on-exit so crashed panes stay visible for debugging
tmux_create_session() {
    tmux new-session -d -s "$SESSION_NAME" -x 220 -y 50 "$1"
    tmux set-option -t "$SESSION_NAME" remain-on-exit on 2>/dev/null || true
}

# Monitor pane starts the session (ensures top-left position)
HAS_MONITOR_PANE=false
if [[ -x "$HOME/bin/stampede-monitor.sh" ]]; then
MONITOR_CMD="$HOME/bin/stampede-monitor.sh ${RUN_ID} ${BASE_DIR}"
tmux_create_session "$MONITOR_CMD"
HAS_MONITOR_PANE=true
elif command -v watch &>/dev/null; then
MONITOR_CMD="watch -n5 'printf \"\033[1;33m\"; \
     echo \"╔══════════════════════════════════════════════════════╗\"; \
     echo \"║  📊 STAMPEDE MONITOR                                ║\"; \
     echo \"║  🏷️  RUN: ${RUN_ID}                  ║\"; \
     echo \"║  📂 REPO: $(basename -- \"${REPO_PATH}\")                                ║\"; \
     echo \"╚══════════════════════════════════════════════════════╝\"; \
     printf \"\033[0m\"; echo; \
     echo \"📋 Queued:  \$(find ${BASE_DIR}/queue -name *.json -type f 2>/dev/null | wc -l | tr -d \" \")\"; \
     echo \"🔧 Claimed: \$(find ${BASE_DIR}/claimed -name *.json -type f 2>/dev/null | wc -l | tr -d \" \")\"; \
     echo \"✅ Done:    \$(find ${BASE_DIR}/results -name *.json -not -name .tmp-* -type f 2>/dev/null | wc -l | tr -d \" \")\"; \
     echo; echo \"── Task Assignments ──\"; \
     for cf in ${BASE_DIR}/claimed/*.json; do \
         [ -f \"\$cf\" ] || continue; \
         tid=\$(python3 -c \"import json; print(json.load(open(\\\"\$cf\\\")).get(\\\"task_id\\\",\\\"?\"))\" 2>/dev/null); \
         who=\$(python3 -c \"import json; print(json.load(open(\\\"\$cf\\\")).get(\\\"claimed_by\\\",\\\"?\"))\" 2>/dev/null); \
         ttl=\$(python3 -c \"import json; print(json.load(open(\\\"\$cf\\\")).get(\\\"title\\\",\\\"?\"))\" 2>/dev/null); \
         echo \"  🔧 \$tid → \$who: \$ttl\"; \
     done; \
     for rf in ${BASE_DIR}/results/*.json; do \
         [ -f \"\$rf\" ] || { echo \"  (none yet)\"; break; }; \
         tid=\$(python3 -c \"import json; print(json.load(open(\\\"\$rf\\\")).get(\\\"task_id\\\",\\\"?\"))\" 2>/dev/null); \
         echo \"  ✅ \$tid — complete\"; \
     done; \
      echo; echo \"── Workers ──\"; \
      for pf in ${PIDS_DIR}/*.pid; do \
          [ -f \"\$pf\" ] || continue; \
          wid=\$(basename \"\$pf\" .pid); \
         wpid=\$(cat \"\$pf\"); \
         if kill -0 \"\$wpid\" 2>/dev/null; then \
             echo \"  🟢 \$wid (PID \$wpid) — alive\"; \
         else \
             echo \"  🔴 \$wid (PID \$wpid) — dead\"; \
         fi; \
     done; \
     echo; echo \"── Recent Logs ──\"; \
     tail -3 ${BASE_DIR}/logs/*.jsonl 2>/dev/null || echo \"  No logs yet\"; \
      echo; echo \"Updated: \$(date +%H:%M:%S)\"'"
tmux_create_session "$MONITOR_CMD"
HAS_MONITOR_PANE=true
else
FIRST_SCRIPT=$(build_worker_script 1)
tmux_create_session "$FIRST_SCRIPT"
fi

# Add worker panes
if $HAS_MONITOR_PANE; then
    START_INDEX=1
else
    START_INDEX=2  # worker 1 is already pane 0
fi

for ((i = START_INDEX; i <= WORKER_COUNT; i++)); do
    WORKER_SCRIPT=$(build_worker_script "$i")
    tmux split-window -t "$SESSION_NAME" "$WORKER_SCRIPT"
    tmux select-layout -t "$SESSION_NAME" tiled 2>/dev/null || true
    sleep 1
done

# Set pane titles for border identification
# Bright cyan borders stand out from code output
tmux set-option -t "$SESSION_NAME" pane-border-status top 2>/dev/null || true
tmux set-option -t "$SESSION_NAME" pane-border-style "fg=colour240" 2>/dev/null || true
tmux set-option -t "$SESSION_NAME" pane-active-border-style "fg=colour51" 2>/dev/null || true
tmux set-option -t "$SESSION_NAME" pane-border-format \
    '#[fg=colour214,bold] ⚡ #{pane_title} #[default]' 2>/dev/null || true

# Name each pane — just model and task name, no "Agent #N"
PANE_IDX=0
if $HAS_MONITOR_PANE; then
    tmux select-pane -t "$SESSION_NAME:0.0" -T "📊 Monitor" 2>/dev/null || true
    PANE_IDX=1
fi

# Read task titles from queue to label each pane with its task
TASK_NAMES=()
for qf in $(ls -1 "${BASE_DIR}/queue/"*.json 2>/dev/null | sort); do
    tname=$(python3 -c "import json; print(json.load(open('$qf')).get('title','task'))" 2>/dev/null || echo "task")
    TASK_NAMES+=("$tname")
done

for ((i = 1; i <= WORKER_COUNT; i++)); do
    task_label="${TASK_NAMES[$((i-1))]:-task}"
    worker_model=$(get_worker_model "$i")
    if $METASWARM; then
        tmux select-pane -t "$SESSION_NAME:0.${PANE_IDX}" \
            -T "Commander #${i} · ${worker_model} · full SS-250" 2>/dev/null || true
    else
        tmux select-pane -t "$SESSION_NAME:0.${PANE_IDX}" \
            -T "Agent #${i} · ${worker_model} · ${task_label}" 2>/dev/null || true
    fi
    PANE_IDX=$((PANE_IDX + 1))
done

tmux select-layout -t "$SESSION_NAME" tiled 2>/dev/null || true

# ─── Note: --autopilot flag in agent scripts handles autonomous mode ──────────
# BTab (Shift+Tab) removed — it conflicts with --autopilot flag and kills agents

# ─── PID Capture with Process Tree Walking ────────────────────────────────────
# Landmine #16: walk process tree to find actual worker PIDs
echo "Capturing worker PIDs..."
sleep 5

WORKER_INDEX=0
while IFS=' ' read -r pane_index pane_pid; do
    if $HAS_MONITOR_PANE && [[ "$pane_index" == "0" ]]; then
        continue
    fi

    WORKER_INDEX=$((WORKER_INDEX + 1))

    if [[ "$WORKER_INDEX" -gt "$WORKER_COUNT" ]]; then
        break
    fi

    LEAF_PID=$(find_leaf_pid "$pane_pid")
    if $METASWARM; then
        WORKER_TAG=$(printf "commander-%03d" "$WORKER_INDEX")
    else
        WORKER_TAG="worker-${WORKER_INDEX}"
    fi

    echo "$LEAF_PID" > "${PIDS_DIR}/${WORKER_TAG}.pid"
    if $METASWARM; then
        echo "  Commander $WORKER_INDEX → PID $LEAF_PID (pane PID $pane_pid)"
    else
        echo "  Worker $WORKER_INDEX → PID $LEAF_PID (pane PID $pane_pid)"
    fi
done < <(tmux list-panes -t "$SESSION_NAME" -F '#{pane_index} #{pane_pid}')

# ─── Fleet Status Summary ────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════"
if $METASWARM; then
    echo "  🦬 METASWARM COMMANDERS LAUNCHED"
else
    echo "  🦬 STAMPEDE FLEET LAUNCHED"
fi
echo "═══════════════════════════════════════════"
echo ""

LAUNCHED=0
if $METASWARM; then
    PID_GLOB="${PIDS_DIR}/commander-*.pid"
else
    PID_GLOB="${PIDS_DIR}/worker-*.pid"
fi
for pf in $PID_GLOB; do
    if [[ -f "$pf" ]]; then
        PID=$(cat "$pf")
        NAME=$(basename "$pf" .pid)
        if kill -0 "$PID" 2>/dev/null; then
            echo "  ✅ $NAME (PID $PID) — running"
            LAUNCHED=$((LAUNCHED + 1))
        else
            echo "  ❌ $NAME (PID $PID) — failed to start"
        fi
    fi
done

echo ""
if $METASWARM; then
    echo "  Commanders launched: $LAUNCHED / $WORKER_COUNT"
    echo "  Swarm scale:         full SS-250 per commander"
    echo "  Required proof:      sub-agent telemetry in child-agents.jsonl + swarm-state.json"
    echo "  Collaboration:       ${BASE_DIR}/collab/ (propose -> peer_review -> improve -> consensus -> broadcast -> adopt)"
    echo "  Progress:            ${BASE_DIR}/commanders/"
else
    echo "  Workers launched: $LAUNCHED / $WORKER_COUNT"
fi
echo "  Tasks in queue:   $TASK_COUNT"
if $HAS_MONITOR_PANE; then
    echo "  Monitor pane:     active (refreshes every 5s)"
else
    echo "  Monitor pane:     unavailable"
fi
echo "  Tmux session:     $SESSION_NAME"
echo ""
echo "  View:      tmux attach -t $SESSION_NAME"
echo "  Teardown:  $0 --teardown --run-id $RUN_ID"
echo ""
echo "═══════════════════════════════════════════"

# ─── Auto-Attach ──────────────────────────────────────────────────────────────
# Opens a new Terminal window attached to the tmux session so you can watch live.
# Use --no-attach to suppress (e.g., when called from an orchestrator skill).
if ! $NO_ATTACH; then
    ATTACHED=false
    if [[ "$(uname)" == "Darwin" ]]; then
        rm -f /tmp/stampede-attach-*.sh 2>/dev/null || true
        # Write task list to a temp file (avoids quoting issues with & in titles)
        TASK_FILE="/tmp/stampede-tasks-${RUN_ID}.txt"
        if [[ -d "${BASE_DIR}/queue" ]]; then
            (cd "${BASE_DIR}/queue" && for qf in *.json; do
                [ -f "$qf" ] || continue
                python3 -c "import json; t=json.load(open('$qf')); print(f\"  ▸ {t['task_id']}: {t['title']}\")" 2>/dev/null
            done) > "$TASK_FILE"
        fi
        ATTACH_SCRIPT="/tmp/stampede-attach-${RUN_ID}.sh"
        cat > "$ATTACH_SCRIPT" << ATTACHEOF
#!/usr/bin/env bash
clear
printf "\033[?25l"
trap 'printf "\033[?25h\033[0m"' EXIT

afplay /System/Library/Sounds/Blow.aiff 2>/dev/null &
osascript -e 'tell application "System Events" to tell process "Terminal" to set value of attribute "AXFullScreen" of window 1 to true' 2>/dev/null &

G="\033[38;5;220m"; GN="\033[38;5;46m"
MT="\033[38;5;240m"; TX="\033[38;5;252m"
B="\033[1m"; R="\033[0m"

printf "\${G}"
cat << 'ART'

       ╭━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╮
       ┃                                                                 ┃
       ┃    t e r m i n a l                                              ┃
       ┃      _____ _                                   _                ┃
       ┃     / ____| |                                 | |               ┃
       ┃    | (___ | |_ __ _ _ __ ___  _ __   ___  __| | ___            ┃
       ┃     \___ \| __/ _\` | '_ \` _ \| '_ \ / _ \/ _\` |/ _ \           ┃
       ┃     ____) | || (_| | | | | | | |_) |  __/ (_| |  __/           ┃
       ┃    |_____/ \__\__,_|_| |_| |_| .__/ \___|\__,_|\___|           ┃
       ┃                               |_|                               ┃
       ┃                                                                 ┃
       ╰━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╯
ART
printf "\${R}"
sleep 1

printf "\n  \${B}\${TX}🦬 ${WORKER_COUNT} agents · ${TASK_COUNT} tasks · $(basename -- "${REPO_PATH}")\${R}\n\n"
sleep 0.5

if [[ -f "$TASK_FILE" ]] && [[ -s "$TASK_FILE" ]]; then
  cat "$TASK_FILE"
  printf "\n"
  sleep 1
fi

CHECKS=("Initializing fleet" "Loading ${TASK_COUNT} task manifests" "Spawning ${WORKER_COUNT} agents" "Connecting monitors" "Engaging stampede")
for c in "\${CHECKS[@]}"; do
  printf "  \${MT}[\${R}\${GN}✓\${R}\${MT}]\${R} \${TX}\${c}\${R}\n"
  sleep 0.3
done
sleep 0.3

printf "\n  "
BAR_W=50
for i in \$(seq 0 \$BAR_W); do
  PCT=\$((i * 100 / BAR_W))
  FILLED=\$(printf '█%.0s' \$(seq 1 \$((i+1))))
  EMPTY=""
  [[ \$i -lt \$BAR_W ]] && EMPTY=\$(printf '░%.0s' \$(seq 1 \$((BAR_W - i))))
  printf "\r  \${G}\${FILLED}\${R}\${MT}\${EMPTY}\${R} \${B}\${TX}\${PCT}%%\${R}"
  sleep 0.02
done
printf "\n"
sleep 0.3

printf "\n  \${B}\${GN}⚡ STAMPEDE ONLINE\${R}  \${MT}${WORKER_COUNT} agents deployed\${R}\n\n"
printf "  \${MT}Attaching in 3...\${R}"; sleep 1
printf "\r  \${MT}Attaching in 2...\${R}"; sleep 1
printf "\r  \${MT}Attaching in 1...\${R}"; sleep 1

printf "\033[?25h"
tmux attach -t $SESSION_NAME
ATTACHEOF
        chmod +x "$ATTACH_SCRIPT"
        # Open a new Terminal window AND bring it to the foreground
        osascript -e "
            tell application \"Terminal\"
                activate
                do script \"exec '$ATTACH_SCRIPT'\"
            end tell
        " 2>/dev/null && ATTACHED=true
        # Fallback to open -a if osascript fails
        if ! $ATTACHED; then
            open -a Terminal "$ATTACH_SCRIPT" 2>/dev/null && ATTACHED=true
        fi
    elif command -v gnome-terminal &>/dev/null; then
        gnome-terminal -- tmux attach -t "$SESSION_NAME" 2>/dev/null &
        ATTACHED=true
    elif command -v xterm &>/dev/null; then
        xterm -e "tmux attach -t $SESSION_NAME" 2>/dev/null &
        ATTACHED=true
    fi

    if $ATTACHED; then
        echo "📺 Opened Terminal attached to $SESSION_NAME"
    else
        echo ""
        echo "═══════════════════════════════════════════"
        echo "  👀 TO WATCH YOUR AGENTS WORK:"
        echo ""
        echo "  tmux attach -t $SESSION_NAME"
        echo ""
        echo "  (Ctrl-B z to zoom a pane, Ctrl-B d to detach)"
        echo "═══════════════════════════════════════════"
    fi
fi
