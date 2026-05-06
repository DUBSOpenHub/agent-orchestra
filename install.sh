#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/bin"
LAUNCHER="${BIN_DIR}/agent-orchestra-pulse"
STAMPEDE_LAUNCHER="${BIN_DIR}/stampede.sh"
STAMPEDE_MONITOR="${BIN_DIR}/stampede-monitor.sh"
FLEET_SCORECARD="${BIN_DIR}/fleet-scorecard"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

need python3
need git

if [[ ! -f "${ROOT}/ORCHESTRA.json" ]]; then
  echo "ORCHESTRA.json not found. Run install.sh from the Agent Orchestra repo." >&2
  exit 1
fi

if [[ ! -d "${ROOT}/run-artifacts/run-20260430-180646" ]]; then
  echo "Fleet run artifacts are missing." >&2
  exit 1
fi

if [[ ! -f "${ROOT}/agent-pulse-current/agent_pulse.py" ]]; then
  echo "Agent Pulse source is missing." >&2
  exit 1
fi

if [[ -x "${ROOT}/tests/smoke.sh" ]]; then
  "${ROOT}/tests/smoke.sh"
fi

mkdir -p "${BIN_DIR}"
install -m 755 "${ROOT}/bin/stampede.sh" "${STAMPEDE_LAUNCHER}"
install -m 755 "${ROOT}/bin/stampede-monitor.sh" "${STAMPEDE_MONITOR}"
install -m 755 "${ROOT}/bin/fleet-scorecard" "${FLEET_SCORECARD}"

cat > "${LAUNCHER}" <<EOF
#!/usr/bin/env bash
set -euo pipefail

export AGENT_ORCHESTRA_ROOT="${ROOT}"
export AGENT_PULSE_SCAN_ROOTS="\${AGENT_PULSE_SCAN_ROOTS:-${ROOT}}"
cd "${ROOT}/agent-pulse-current"
exec python3 agent_pulse.py --no-splash "\$@"
EOF
chmod +x "${LAUNCHER}"

echo
echo "Agent Orchestra is installed."
echo "Launcher: ${LAUNCHER}"
echo "Stampede launcher: ${STAMPEDE_LAUNCHER}"
echo "Fleet Scorecard: ${FLEET_SCORECARD}"
echo
echo "Run Agent Pulse for Agent Orchestra with:"
echo "  agent-orchestra-pulse"
