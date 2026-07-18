#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

INCIDENT_FILE="examples/incidents/gke-platform-api-latency.json"
DIAGNOSIS_FILE="examples/responses/gke-platform-api-latency-claude.json"
WEIGHTS_FILE="config/traffic-weights.env"

usage() {
  echo "usage: $0 replay|propose|reject-unsafe" >&2
}

run_validator() {
  local diagnosis_file="$1"
  shift
  python3 "$ROOT_DIR/ai_copilot/incident.py" \
    "$INCIDENT_FILE" "$diagnosis_file" --weights "$WEIGHTS_FILE" "$@"
}

case "${1:-}" in
  replay)
    run_validator "$DIAGNOSIS_FILE" --format json
    ;;
  propose)
    run_validator "$DIAGNOSIS_FILE" --format diff
    ;;
  reject-unsafe)
    if run_validator "examples/responses/gke-platform-api-latency-unsafe.json" --format json; then
      echo "unsafe recommendation unexpectedly passed" >&2
      exit 1
    fi
    echo "unsafe recommendation rejected as expected"
    ;;
  *)
    usage
    exit 2
    ;;
esac
