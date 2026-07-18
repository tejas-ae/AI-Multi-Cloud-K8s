#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

INCIDENT_FILE="examples/incidents/gke-platform-api-availability.json"
DIAGNOSIS_FILE="examples/responses/gke-platform-api-availability-claude.json"
WEIGHTS_FILE="config/traffic-weights.env"

usage() {
  echo "usage: $0 replay|propose|reject-unsafe|claude" >&2
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
    if run_validator "examples/responses/gke-platform-api-availability-unsafe.json" --format json; then
      echo "unsafe recommendation unexpectedly passed" >&2
      exit 1
    fi
    echo "unsafe recommendation rejected as expected"
    ;;
  claude)
    response_file="$(mktemp)"
    trap 'rm -f "$response_file"' EXIT
    python3 "$ROOT_DIR/ai_copilot/claude.py" \
      "$INCIDENT_FILE" --weights "$WEIGHTS_FILE" >"$response_file"
    if ! python3 "$ROOT_DIR/ai_copilot/incident.py" \
      "$INCIDENT_FILE" "$response_file" --weights "$WEIGHTS_FILE" --format json; then
      echo "Claude returned this sanitized policy input:" >&2
      jq '{incident_id, confidence, evidence_ids, recommendation}' "$response_file" >&2
      exit 1
    fi
    ;;
  *)
    usage
    exit 2
    ;;
esac
