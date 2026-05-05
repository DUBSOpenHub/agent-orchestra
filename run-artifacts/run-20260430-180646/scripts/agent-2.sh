#!/usr/bin/env bash
set -euo pipefail
cd "/Users/greggcochran/dev/terminal-stampede"
export STAMPEDE_RUN_ID="run-20260430-180646"
export STAMPEDE_RUN_DIR="/Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646"
export STAMPEDE_ROLE="commander"
export STAMPEDE_AGENT_LOG="/Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/commanders/commander-002/logs/commander-cli.log"
export STAMPEDE_COMMANDER_ID="commander-002"
export STAMPEDE_PROGRESS_DIR="/Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/commanders/commander-002"
export STAMPEDE_COLLAB_DIR="/Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/collab"
export STAMPEDE_COLLAB_PROTOCOL="/Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/collab/protocol.json"
export STAMPEDE_COLLAB_PROPOSALS="/Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/collab/proposals.jsonl"
export STAMPEDE_COLLAB_REVIEWS="/Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/collab/reviews.jsonl"
export STAMPEDE_COLLAB_IMPROVEMENTS="/Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/collab/improvements.jsonl"
export STAMPEDE_COLLAB_CONSENSUS="/Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/collab/consensus.jsonl"
export STAMPEDE_COLLAB_BROADCASTS="/Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/collab/broadcasts.jsonl"
echo '⚡ gpt-5.5 · commander claiming task...'
set +e
if command -v copilot >/dev/null 2>&1; then
  copilot \
    --agent "stampede-commander" \
    --model "gpt-5.5" \
    --allow-all-tools \
    --autopilot \
    --max-autopilot-continues "1000" \
    --no-ask-user \
    -p "You are commander-002 for metaswarm run run-20260430-180646. FOLLOW YOUR COMMANDER AGENT INSTRUCTIONS EXACTLY. Claim ONE commander task from /Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/queue/ via atomic mv to /Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/claimed/. Your progress directory is /Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/commanders/commander-002. You MUST launch and track your own sub-agent swarm; do not satisfy this by delegating to one wrapped swarm-command agent. Build the Swarm Command Context Capsule with profile=metaswarm, swarm_scale=ss-250, per_commander_full_swarm=true, constraints.max_workers=250, depth_budget.squads_allocated=50, squad_leads_per_commander=50, workers_per_squad_lead=5, and workers_per_commander=250. Use premium model policy for every Squad Lead and Worker: rotate claude-opus-4.7, gpt-5.5, claude-opus-4.6, gpt-5.4, claude-opus-4.5, gpt-5.2, claude-sonnet-4.6, gpt-5.3-codex, claude-sonnet-4.5, and gpt-5.2-codex. Do NOT use claude-haiku-4.5, gpt-5.4-mini, gpt-5-mini, or gpt-4.1 for metaswarm sub-agents. Launch 50 Squad Leads and require each Squad Lead to launch 5 premium leaf workers (250 workers total) unless a circuit breaker makes the bundle partial. Append every sub-agent launch/update to /Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/commanders/commander-002/child-agents.jsonl including the model field, and keep /Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/commanders/commander-002/swarm-state.json updated in real time with launched/running/completed/failed counts. Collaboration bus: /Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/collab/ contains protocol.json and append-only JSONL ledgers proposals.jsonl, reviews.jsonl, improvements.jsonl, consensus.jsonl, and broadcasts.jsonl. Follow workflow propose -> peer_review -> improve -> consensus -> broadcast -> adopt. Publish a proposal early to proposals.jsonl using required fields ts, run_id, commander_id, event, item_id, summary, evidence, confidence, and source_refs; review other commanders' proposals in real time, append peer reviews to reviews.jsonl, write improvements to improvements.jsonl, promote consensus to consensus.jsonl, consume broadcasts.jsonl, append broadcasts when consensus should be adopted, and include adopted consensus item_ids and source_refs in bundle.json plus the final result. Final bundle status must be success, partial, or failed; write it atomically to /Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/commanders/commander-002/bundle.json plus /Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/results/. Your repo is /Users/greggcochran/dev/terminal-stampede. Stop after your commander bundle is complete." 2>&1 | tee -a "${STAMPEDE_AGENT_LOG}"
  agent_status=${PIPESTATUS[0]}
else
  gh copilot -- \
    --agent "stampede-commander" \
    --model "gpt-5.5" \
    --allow-all-tools \
    --autopilot \
    --max-autopilot-continues "1000" \
    --no-ask-user \
    -p "You are commander-002 for metaswarm run run-20260430-180646. FOLLOW YOUR COMMANDER AGENT INSTRUCTIONS EXACTLY. Claim ONE commander task from /Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/queue/ via atomic mv to /Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/claimed/. Your progress directory is /Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/commanders/commander-002. You MUST launch and track your own sub-agent swarm; do not satisfy this by delegating to one wrapped swarm-command agent. Build the Swarm Command Context Capsule with profile=metaswarm, swarm_scale=ss-250, per_commander_full_swarm=true, constraints.max_workers=250, depth_budget.squads_allocated=50, squad_leads_per_commander=50, workers_per_squad_lead=5, and workers_per_commander=250. Use premium model policy for every Squad Lead and Worker: rotate claude-opus-4.7, gpt-5.5, claude-opus-4.6, gpt-5.4, claude-opus-4.5, gpt-5.2, claude-sonnet-4.6, gpt-5.3-codex, claude-sonnet-4.5, and gpt-5.2-codex. Do NOT use claude-haiku-4.5, gpt-5.4-mini, gpt-5-mini, or gpt-4.1 for metaswarm sub-agents. Launch 50 Squad Leads and require each Squad Lead to launch 5 premium leaf workers (250 workers total) unless a circuit breaker makes the bundle partial. Append every sub-agent launch/update to /Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/commanders/commander-002/child-agents.jsonl including the model field, and keep /Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/commanders/commander-002/swarm-state.json updated in real time with launched/running/completed/failed counts. Collaboration bus: /Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/collab/ contains protocol.json and append-only JSONL ledgers proposals.jsonl, reviews.jsonl, improvements.jsonl, consensus.jsonl, and broadcasts.jsonl. Follow workflow propose -> peer_review -> improve -> consensus -> broadcast -> adopt. Publish a proposal early to proposals.jsonl using required fields ts, run_id, commander_id, event, item_id, summary, evidence, confidence, and source_refs; review other commanders' proposals in real time, append peer reviews to reviews.jsonl, write improvements to improvements.jsonl, promote consensus to consensus.jsonl, consume broadcasts.jsonl, append broadcasts when consensus should be adopted, and include adopted consensus item_ids and source_refs in bundle.json plus the final result. Final bundle status must be success, partial, or failed; write it atomically to /Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/commanders/commander-002/bundle.json plus /Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/results/. Your repo is /Users/greggcochran/dev/terminal-stampede. Stop after your commander bundle is complete." 2>&1 | tee -a "${STAMPEDE_AGENT_LOG}"
  agent_status=${PIPESTATUS[0]}
fi
set -e
if [[ "$agent_status" -ne 0 ]]; then
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
  fi
  exit "$agent_status"
fi
echo '⚡ Done.'
sleep 86400
