#!/usr/bin/env bash
# Local smoke gate for Agent Orchestra.
#
# This validates fleet metadata, commander bundle integrity, and Agent Pulse
# import/poll behavior without launching real Copilot agents.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="$ROOT/run-artifacts/run-20260430-180646"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

require_dir() {
  [[ -d "$1" ]] || fail "missing directory: $1"
}

require_file "$ROOT/README.md"
require_file "$ROOT/ORCHESTRA.json"
require_file "$ROOT/UPSTREAM-TERMINAL-STAMPEDE-README.md"
require_file "$ROOT/agents/stampede-agent.agent.md"
require_file "$ROOT/agents/stampede-commander.agent.md"
require_file "$ROOT/agents/stampede-merger.agent.md"
require_file "$ROOT/schemas/commander-bundle.schema.json"
require_file "$ROOT/schemas/collab-record.schema.json"
require_dir "$RUN_DIR"
require_dir "$ROOT/agent-pulse-current"
require_file "$ROOT/agent-pulse-current/agent_pulse.py"

bash -n "$ROOT/bin/stampede.sh"
grep -q "stampede_synthesize_commander_bundle" "$ROOT/bin/stampede.sh" || fail "stampede runtime missing bundle synthesis"
grep -q "telemetry_high_water" "$ROOT/bin/stampede.sh" || fail "stampede runtime missing high-water telemetry preservation"
grep -q "requires exactly 5 commanders" "$ROOT/bin/stampede.sh" || fail "stampede runtime missing commander cardinality guard"

python3 - "$ROOT" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
metadata = json.loads((root / "ORCHESTRA.json").read_text())
run = root / "run-artifacts" / "run-20260430-180646"

assert metadata["name"] == "Agent Orchestra"
assert metadata["run_id"] == "run-20260430-180646"
assert metadata["terminal_stampede_commit"] == "dc14bdefa5d084002fcbcad2a3cc6aa6fa2328c5"

results = sorted((run / "results").glob("*.json"))
bundles = sorted((run / "commanders").glob("commander-*/bundle.json"))
assert len(results) == metadata["result_files"] == 9
assert len(bundles) == metadata["commander_bundles"] == 5

expected_commanders = {f"commander-{idx:03d}" for idx in range(1, 6)}
bundle_schema = json.loads((root / "schemas" / "commander-bundle.schema.json").read_text())
collab_schema = json.loads((root / "schemas" / "collab-record.schema.json").read_text())
assert {"run_id", "commander_id", "task_id", "status", "telemetry", "source_refs"}.issubset(
    set(bundle_schema["required"])
)
assert {"ts", "run_id", "commander_id", "event", "item_id", "summary", "evidence", "confidence", "source_refs"}.issubset(
    set(collab_schema["required"])
)
seen = set()
for bundle_path in bundles:
    data = json.loads(bundle_path.read_text())
    commander_id = data.get("commander_id") or bundle_path.parent.name
    task_id = data.get("task_id")
    status = data.get("status")
    assert commander_id in expected_commanders, (bundle_path, commander_id)
    assert task_id == commander_id, (bundle_path, task_id, commander_id)
    assert status in {"success", "partial", "failed"}, (bundle_path, status)
    seen.add(commander_id)
assert seen == expected_commanders

metadata_commanders = {item["commander_id"] for item in metadata["commanders"]}
assert metadata_commanders == expected_commanders

print("fleet_artifacts_ok=1")
PY

workflow_count="$(find "$ROOT" -path '*/.github/workflows/*' -type f | wc -l | tr -d ' ')"
[[ "$workflow_count" == "0" ]] || fail "workflow files are active under .github/workflows; archive them before publishing"

(
  cd "$ROOT/agent-pulse-current"
  AGENT_PULSE_SCAN_ROOTS="$ROOT" python3 - <<'PY'
from agent_pulse import MetricsEngine, PulseStore

store = PulseStore()
metrics = MetricsEngine(store).poll()
assert type(metrics).__name__ == "PulseMetrics"
print("agent_pulse_import_ok=1")
print(f"running_subagents={getattr(metrics, 'running_subagents', 'n/a')}")
PY
)

echo "Agent Orchestra smoke test passed."
