#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM_NAMESPACE="${PLATFORM_NAMESPACE:-platform}"
OBSERVABILITY_NAMESPACE="${OBSERVABILITY_NAMESPACE:-observability}"
PROMETHEUS_LOCAL_PORT="${PROMETHEUS_LOCAL_PORT:-19090}"
FAULT_DELAY="${FAULT_DELAY:-3s}"
FAULT_LOAD_DURATION_SECONDS="${FAULT_LOAD_DURATION_SECONDS:-180}"
GKE_CONTEXT="${GKE_CONTEXT:-}"
PORT_FORWARD_PID=""
PORT_FORWARD_LOG=""

usage() {
  echo "usage: $0 inject|clear|status|load|capture" >&2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "required command missing: $1" >&2
    exit 1
  }
}

require_value() {
  local name="$1"
  if [[ -z "${!name:-}" || "${!name}" == "replace-me" ]]; then
    echo "$name must be loaded from .env" >&2
    exit 1
  fi
}

load_context() {
  require_value GCP_PROJECT_ID
  require_value GCP_ZONE
  require_value GCP_CLUSTER_NAME
  GKE_CONTEXT="${GKE_CONTEXT:-gke_${GCP_PROJECT_ID}_${GCP_ZONE}_${GCP_CLUSTER_NAME}}"
}

stop_port_forward() {
  if [[ -n "$PORT_FORWARD_PID" ]]; then
    kill "$PORT_FORWARD_PID" >/dev/null 2>&1 || true
    wait "$PORT_FORWARD_PID" >/dev/null 2>&1 || true
  fi
  [[ -z "$PORT_FORWARD_LOG" ]] || rm -f "$PORT_FORWARD_LOG"
}

start_prometheus_port_forward() {
  local attempt

  PORT_FORWARD_LOG="$(mktemp)"
  kubectl --context "$GKE_CONTEXT" --namespace "$OBSERVABILITY_NAMESPACE" \
    port-forward service/observability-kube-prometh-prometheus \
    "${PROMETHEUS_LOCAL_PORT}:9090" >"$PORT_FORWARD_LOG" 2>&1 &
  PORT_FORWARD_PID=$!

  for ((attempt = 1; attempt <= 20; attempt++)); do
    if curl --fail --silent --show-error --connect-timeout 2 --max-time 5 \
      "http://127.0.0.1:${PROMETHEUS_LOCAL_PORT}/-/ready" >/dev/null 2>&1; then
      return 0
    fi
    kill -0 "$PORT_FORWARD_PID" >/dev/null 2>&1 || break
    sleep 1
  done

  echo "Prometheus port-forward did not become ready" >&2
  sed -n '1,80p' "$PORT_FORWARD_LOG" >&2
  return 1
}

require_fault_confirmation() {
  if [[ "${CONFIRM_FAULT_INJECTION:-}" != "AI-Multi-Cloud-K8s" ]]; then
    echo "set CONFIRM_FAULT_INJECTION=AI-Multi-Cloud-K8s to change the GKE fault state" >&2
    exit 1
  fi
}

verify_virtual_service() {
  kubectl --context "$GKE_CONTEXT" --namespace "$PLATFORM_NAMESPACE" \
    get virtualservice platform-api --output json |
    jq -e '
      (.spec.http | length) >= 2
      and .spec.http[1].name == "application"
    ' >/dev/null
}

inject() {
  for command_name in kubectl jq; do require_command "$command_name"; done
  load_context
  require_fault_confirmation
  [[ "$FAULT_DELAY" =~ ^[1-9][0-9]*(ms|s)$ ]] || {
    echo "FAULT_DELAY must be a positive millisecond or second duration" >&2
    exit 1
  }
  verify_virtual_service

  if kubectl --context "$GKE_CONTEXT" --namespace "$PLATFORM_NAMESPACE" \
    get virtualservice platform-api --output json |
    jq -e '.spec.http[1].fault.delay' >/dev/null; then
    echo "GKE latency fault is already active" >&2
    exit 1
  fi

  kubectl --context "$GKE_CONTEXT" --namespace "$PLATFORM_NAMESPACE" \
    patch virtualservice platform-api --type=json --patch "[
      {\"op\":\"add\",\"path\":\"/spec/http/1/fault\",\"value\":{
        \"delay\":{\"fixedDelay\":\"${FAULT_DELAY}\",\"percentage\":{\"value\":100}}
      }}
    ]" >/dev/null
  echo "GKE application-route latency fault is active. Run make fault-load, then make fault-capture."
}

clear() {
  for command_name in kubectl jq; do require_command "$command_name"; done
  load_context
  require_fault_confirmation
  verify_virtual_service

  if ! kubectl --context "$GKE_CONTEXT" --namespace "$PLATFORM_NAMESPACE" \
    get virtualservice platform-api --output json |
    jq -e '.spec.http[1].fault.delay' >/dev/null; then
    echo "GKE latency fault is already clear."
    return 0
  fi

  kubectl --context "$GKE_CONTEXT" --namespace "$PLATFORM_NAMESPACE" \
    patch virtualservice platform-api --type=json \
    --patch '[{"op":"remove","path":"/spec/http/1/fault"}]' >/dev/null
  echo "GKE application-route latency fault is clear."
}

status() {
  for command_name in kubectl jq; do require_command "$command_name"; done
  load_context
  verify_virtual_service
  kubectl --context "$GKE_CONTEXT" --namespace "$PLATFORM_NAMESPACE" \
    get virtualservice platform-api --output json |
    jq '{active: (.spec.http[1].fault.delay != null), delay: .spec.http[1].fault.delay}'
}

load() {
  local ingress_ip
  local deadline

  for command_name in curl terraform; do require_command "$command_name"; done
  load_context
  [[ "$FAULT_LOAD_DURATION_SECONDS" =~ ^[1-9][0-9]*$ ]] || {
    echo "FAULT_LOAD_DURATION_SECONDS must be a positive integer" >&2
    exit 1
  }
  ingress_ip="$(terraform -chdir="$ROOT_DIR/terraform" output -raw gke_ingress_public_ip)"
  deadline=$((SECONDS + FAULT_LOAD_DURATION_SECONDS))
  while ((SECONDS < deadline)); do
    curl --silent --show-error --connect-timeout 2 --max-time 10 \
      "http://${ingress_ip}/hostname" >/dev/null || true
  done
  echo "GKE fault traffic generation complete."
}

capture() {
  local alert_response
  local latency_response

  for command_name in kubectl curl jq; do require_command "$command_name"; done
  load_context
  trap stop_port_forward EXIT
  start_prometheus_port_forward
  alert_response="$(curl --fail --silent --show-error --get \
    --data-urlencode 'query=ALERTS{alertname="PlatformApiLatencyDemo",alertstate="firing"}' \
    "http://127.0.0.1:${PROMETHEUS_LOCAL_PORT}/api/v1/query")"
  latency_response="$(curl --fail --silent --show-error --get \
    --data-urlencode 'query=histogram_quantile(0.95,sum by (le) (rate(istio_request_duration_milliseconds_bucket{reporter="destination",destination_service_name="platform-api"}[1m])))' \
    "http://127.0.0.1:${PROMETHEUS_LOCAL_PORT}/api/v1/query")"
  jq -n --argjson alerts "$alert_response" --argjson latency "$latency_response" '
    {
      alert_firing: ($alerts.data.result | length > 0),
      p95_milliseconds: ($latency.data.result[0].value[1] // null)
    }
  '
}

case "${1:-}" in
  inject) inject ;;
  clear) clear ;;
  status) status ;;
  load) load ;;
  capture) capture ;;
  *) usage; exit 2 ;;
esac
