#!/usr/bin/env bash
# Pre-publish smoke test for Agent Orchestra.
#
# This validates the preserved reference artifacts and current Agent Pulse import
# path without launching real Copilot agents.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="$ROOT/known-good-runs/run-20260430-180646"

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
require_file "$ROOT/BASELINE.json"
require_file "$ROOT/REFERENCE-NOTES.md"
require_file "$ROOT/UPSTREAM-TERMINAL-STAMPEDE-README.md"
require_dir "$RUN_DIR"
require_dir "$ROOT/agent-pulse-current"
require_file "$ROOT/agent-pulse-current/agent_pulse.py"

python3 - "$ROOT" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
baseline = json.loads((root / "BASELINE.json").read_text())
run = root / "known-good-runs" / "run-20260430-180646"

assert baseline["baseline_name"] == "Agent Orchestra"
assert baseline["known_good_run"] == "run-20260430-180646"
assert baseline["terminal_stampede_commit"] == "dc14bdefa5d084002fcbcad2a3cc6aa6fa2328c5"

results = sorted((run / "results").glob("*.json"))
bundles = sorted((run / "commanders").glob("commander-*/bundle.json"))
assert len(results) == baseline["result_files"] == 9
assert len(bundles) == baseline["commander_bundles"] == 5

expected_commanders = {f"commander-{idx:03d}" for idx in range(1, 6)}
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

metadata_commanders = {item["commander_id"] for item in baseline["commanders"]}
assert metadata_commanders == expected_commanders

print("reference_artifacts_ok=1")
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

echo "Agent Orchestra pre-publish smoke test passed."
