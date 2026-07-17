#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OBSERVABILITY_NAMESPACE="${OBSERVABILITY_NAMESPACE:-observability}"
PLATFORM_NAMESPACE="${PLATFORM_NAMESPACE:-platform}"
KUBE_PROMETHEUS_STACK_VERSION="${KUBE_PROMETHEUS_STACK_VERSION:-87.17.0}"
OTEL_COLLECTOR_VERSION="${OTEL_COLLECTOR_VERSION:-0.165.0}"
TEMPO_VERSION="${TEMPO_VERSION:-2.2.3}"
PROMETHEUS_LOCAL_PORT="${PROMETHEUS_LOCAL_PORT:-19090}"
ALERTMANAGER_LOCAL_PORT="${ALERTMANAGER_LOCAL_PORT:-19093}"
TEMPO_LOCAL_PORT="${TEMPO_LOCAL_PORT:-13200}"
GRAFANA_LOCAL_PORT="${GRAFANA_LOCAL_PORT:-3000}"
GKE_CONTEXT="${GKE_CONTEXT:-}"
AKS_CONTEXT="${AKS_CONTEXT:-}"
PORT_FORWARD_PID=""
PORT_FORWARD_LOG=""

usage() {
  echo "usage: $0 bootstrap|status|port-forward gke|aks" >&2
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "required command missing: $1" >&2
    exit 1
  fi
}

require_value() {
  local name="$1"
  if [[ -z "${!name:-}" || "${!name}" == "replace-me" ]]; then
    echo "$name must be loaded from .env" >&2
    exit 1
  fi
}

load_contexts() {
  require_value GCP_PROJECT_ID
  require_value GCP_ZONE
  require_value GCP_CLUSTER_NAME
  require_value AKS_CLUSTER_NAME

  GKE_CONTEXT="${GKE_CONTEXT:-gke_${GCP_PROJECT_ID}_${GCP_ZONE}_${GCP_CLUSTER_NAME}}"
  AKS_CONTEXT="${AKS_CONTEXT:-$AKS_CLUSTER_NAME}"
}

terraform_output() {
  terraform -chdir="$ROOT_DIR/terraform" output -raw "$1"
}

run_argocd_core() (
  local context="$1"
  shift

  local temporary_kubeconfig
  umask 077
  temporary_kubeconfig="$(mktemp)"
  trap 'rm -f "$temporary_kubeconfig"' EXIT

  kubectl config view --raw --minify --context "$context" >"$temporary_kubeconfig"
  kubectl --kubeconfig "$temporary_kubeconfig" \
    config set-context --current --namespace=argocd >/dev/null

  KUBECONFIG="$temporary_kubeconfig" argocd --core "$@"
)

check_cluster_access() {
  local context="$1"
  local alias="$2"

  kubectl --context "$context" --request-timeout=30s get --raw=/readyz >/dev/null
  if [[ "$(kubectl --context "$context" auth can-i create namespaces)" != "yes" ]]; then
    echo "$alias context cannot create the observability namespace" >&2
    exit 1
  fi
  if [[ "$(kubectl --context "$context" auth can-i create customresourcedefinitions.apiextensions.k8s.io)" != "yes" ]]; then
    echo "$alias context cannot install the Prometheus Operator CRDs" >&2
    exit 1
  fi
  if [[ "$(kubectl --context "$context" auth can-i create clusterroles.rbac.authorization.k8s.io)" != "yes" ]]; then
    echo "$alias context cannot install the observability cluster roles" >&2
    exit 1
  fi
  if [[ "$(kubectl --context "$context" --namespace "$PLATFORM_NAMESPACE" \
    auth can-i create roles.rbac.authorization.k8s.io)" != "yes" ]]; then
    echo "$alias context cannot create the observability policy Role" >&2
    exit 1
  fi
  if [[ "$(kubectl --context "$context" --namespace argocd \
    auth can-i create applications.argoproj.io)" != "yes" ]]; then
    echo "$alias context cannot create the observability policy Application" >&2
    exit 1
  fi
}

helm_upgrade() {
  local -a command=(helm upgrade --install "$@")

  if [[ "$(helm version --template '{{.Version}}')" == v4.* ]]; then
    command+=(--server-side=false)
  fi
  command+=(--wait --timeout 15m)
  "${command[@]}"
}

verify_mesh_provider() {
  local context="$1"
  local alias="$2"

  if ! kubectl --context "$context" --namespace istio-system \
    get configmap istio --output jsonpath='{.data.mesh}' |
    grep -q 'name: otel-tracing'; then
    echo "$alias Istio control plane does not contain the otel-tracing provider" >&2
    echo "Run make mesh-bootstrap before make observability-bootstrap." >&2
    return 1
  fi
}

stop_port_forward() {
  if [[ -n "$PORT_FORWARD_PID" ]]; then
    kill "$PORT_FORWARD_PID" >/dev/null 2>&1 || true
    wait "$PORT_FORWARD_PID" >/dev/null 2>&1 || true
    PORT_FORWARD_PID=""
  fi
  if [[ -n "$PORT_FORWARD_LOG" ]]; then
    rm -f "$PORT_FORWARD_LOG"
    PORT_FORWARD_LOG=""
  fi
}

start_port_forward() {
  local context="$1"
  local resource="$2"
  local mapping="$3"
  local ready_url="$4"
  local attempt

  stop_port_forward
  PORT_FORWARD_LOG="$(mktemp)"
  kubectl --context "$context" --namespace "$OBSERVABILITY_NAMESPACE" \
    port-forward "$resource" "$mapping" >"$PORT_FORWARD_LOG" 2>&1 &
  PORT_FORWARD_PID=$!

  for ((attempt = 1; attempt <= 20; attempt++)); do
    if curl --fail --silent --show-error \
      --connect-timeout 2 --max-time 5 "$ready_url" >/dev/null 2>&1; then
      return 0
    fi
    if ! kill -0 "$PORT_FORWARD_PID" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  echo "port-forward did not become ready for $resource" >&2
  sed -n '1,80p' "$PORT_FORWARD_LOG" >&2
  stop_port_forward
  return 1
}

wait_for_resource() {
  local context="$1"
  local resource="$2"
  local timeout_seconds="$3"
  local elapsed=0

  until kubectl --context "$context" --namespace "$OBSERVABILITY_NAMESPACE" \
    get "$resource" >/dev/null 2>&1; do
    if ((elapsed >= timeout_seconds)); then
      echo "timed out waiting for ${resource} to be created" >&2
      return 1
    fi
    sleep 5
    ((elapsed += 5))
  done
}

generate_trace_traffic() {
  local ingress_ip="$1"
  local alias="$2"
  local request

  for ((request = 1; request <= 20; request++)); do
    curl --fail --silent --show-error \
      --connect-timeout 5 --max-time 10 \
      "http://${ingress_ip}/hostname" >/dev/null
  done
  echo "$alias trace traffic generated."
}

verify_prometheus_data() {
  local context="$1"
  local alias="$2"
  local attempt
  local response

  start_port_forward "$context" \
    service/observability-kube-prometh-prometheus \
    "${PROMETHEUS_LOCAL_PORT}:9090" \
    "http://127.0.0.1:${PROMETHEUS_LOCAL_PORT}/-/ready"

  for ((attempt = 1; attempt <= 36; attempt++)); do
    response="$(curl --fail --silent --show-error --get \
      --connect-timeout 2 --max-time 10 \
      --data-urlencode 'query=sum(istio_requests_total{destination_service_name="platform-api"})' \
      "http://127.0.0.1:${PROMETHEUS_LOCAL_PORT}/api/v1/query" || true)"
    if jq -e '.status == "success" and (.data.result | length > 0)' \
      <<<"$response" >/dev/null 2>&1; then
      stop_port_forward
      echo "$alias Prometheus contains platform-api Istio request metrics."
      return 0
    fi
    sleep 5
  done

  stop_port_forward
  echo "$alias Prometheus did not discover platform-api Istio metrics" >&2
  return 1
}

verify_slo_rules() {
  local context="$1"
  local alias="$2"
  local attempt
  local response

  start_port_forward "$context" \
    service/observability-kube-prometh-prometheus \
    "${PROMETHEUS_LOCAL_PORT}:9090" \
    "http://127.0.0.1:${PROMETHEUS_LOCAL_PORT}/-/ready"

  for ((attempt = 1; attempt <= 36; attempt++)); do
    response="$(curl --fail --silent --show-error \
      --connect-timeout 2 --max-time 10 \
      "http://127.0.0.1:${PROMETHEUS_LOCAL_PORT}/api/v1/rules" || true)"
    if jq -e '
      .status == "success"
      and any(
        .data.groups[];
        .name == "platform-api.slo-recording"
        and all(.rules[]; .health == "ok")
      )
      and any(
        .data.groups[];
        .name == "platform-api.slo-alerting"
        and all(.rules[]; .health == "ok")
      )
    ' <<<"$response" >/dev/null 2>&1; then
      stop_port_forward
      echo "$alias Prometheus loaded healthy platform-api SLO rules."
      return 0
    fi
    sleep 5
  done

  stop_port_forward
  echo "$alias Prometheus did not load healthy platform-api SLO rules" >&2
  return 1
}

verify_alertmanager() {
  local context="$1"
  local alias="$2"
  local response

  start_port_forward "$context" \
    service/observability-kube-prometh-alertmanager \
    "${ALERTMANAGER_LOCAL_PORT}:9093" \
    "http://127.0.0.1:${ALERTMANAGER_LOCAL_PORT}/-/ready"

  response="$(curl --fail --silent --show-error \
    --connect-timeout 2 --max-time 10 \
    "http://127.0.0.1:${ALERTMANAGER_LOCAL_PORT}/api/v2/status")"
  stop_port_forward

  if ! jq -e '
    .config.original | contains("receiver: slo-null")
  ' <<<"$response" >/dev/null 2>&1; then
    echo "$alias Alertmanager did not load the reviewed internal route" >&2
    return 1
  fi

  echo "$alias Alertmanager loaded the internal SLO route."
}

verify_tempo_data() {
  local context="$1"
  local alias="$2"
  local attempt
  local response

  start_port_forward "$context" service/tempo \
    "${TEMPO_LOCAL_PORT}:3200" \
    "http://127.0.0.1:${TEMPO_LOCAL_PORT}/ready"

  for ((attempt = 1; attempt <= 36; attempt++)); do
    response="$(curl --fail --silent --show-error \
      --connect-timeout 2 --max-time 10 \
      "http://127.0.0.1:${TEMPO_LOCAL_PORT}/api/search?limit=1" || true)"
    if jq -e '(.traces // []) | length > 0' \
      <<<"$response" >/dev/null 2>&1; then
      stop_port_forward
      echo "$alias Tempo contains an Istio trace."
      return 0
    fi
    sleep 5
  done

  stop_port_forward
  echo "$alias Tempo did not receive an Istio trace" >&2
  return 1
}

verify_policy() {
  local context="$1"
  local alias="$2"

  if ! kubectl --context "$context" --namespace "$PLATFORM_NAMESPACE" \
    get telemetry platform-tracing --output json |
    jq -e '
      .spec.tracing[0].randomSamplingPercentage == 100
      and .spec.tracing[0].providers[0].name == "otel-tracing"
    ' >/dev/null; then
    echo "$alias tracing policy does not match the reviewed provider and sample rate" >&2
    return 1
  fi

  if ! kubectl --context "$context" --namespace "$PLATFORM_NAMESPACE" \
    get podmonitor platform-api-istio --output json |
    jq -e '
      .metadata.labels["telemetry.ai-multicloud-k8s/enabled"] == "true"
      and .spec.podMetricsEndpoints[0].port == "http-envoy-prom"
    ' >/dev/null; then
    echo "$alias platform-api PodMonitor does not match the reviewed selector" >&2
    return 1
  fi

  if ! kubectl --context "$context" --namespace "$PLATFORM_NAMESPACE" \
    get prometheusrule platform-api-slos --output json |
    jq -e '
      .metadata.labels["telemetry.ai-multicloud-k8s/enabled"] == "true"
      and any(.spec.groups[]; .name == "platform-api.slo-recording")
      and any(
        .spec.groups[].rules[];
        .alert == "PlatformApiAvailabilityBudgetFastBurn"
      )
      and any(
        .spec.groups[].rules[];
        .alert == "PlatformApiAvailabilityBudgetSlowBurn"
      )
      and any(
        .spec.groups[].rules[];
        .alert == "PlatformApiLatencyObjectiveAtRisk"
      )
    ' >/dev/null; then
    echo "$alias platform-api PrometheusRule does not match the reviewed SLO policy" >&2
    return 1
  fi
}

verify_runtime() {
  local context="$1"
  local alias="$2"
  local ingress_ip="$3"

  kubectl --context "$context" --namespace "$OBSERVABILITY_NAMESPACE" \
    rollout status deployment/observability-kube-prometh-operator --timeout=10m
  kubectl --context "$context" --namespace "$OBSERVABILITY_NAMESPACE" \
    rollout status deployment/observability-grafana --timeout=10m
  kubectl --context "$context" --namespace "$OBSERVABILITY_NAMESPACE" \
    rollout status deployment/observability-kube-state-metrics --timeout=10m
  kubectl --context "$context" --namespace "$OBSERVABILITY_NAMESPACE" \
    rollout status daemonset/observability-prometheus-node-exporter --timeout=10m
  kubectl --context "$context" --namespace "$OBSERVABILITY_NAMESPACE" \
    rollout status statefulset/prometheus-observability-kube-prometh-prometheus --timeout=10m
  wait_for_resource "$context" \
    statefulset/alertmanager-observability-kube-prometh-alertmanager 600
  kubectl --context "$context" --namespace "$OBSERVABILITY_NAMESPACE" \
    rollout status statefulset/alertmanager-observability-kube-prometh-alertmanager --timeout=10m
  kubectl --context "$context" --namespace "$OBSERVABILITY_NAMESPACE" \
    rollout status statefulset/tempo --timeout=10m
  kubectl --context "$context" --namespace "$OBSERVABILITY_NAMESPACE" \
    rollout status deployment/otel-collector --timeout=10m

  verify_policy "$context" "$alias"
  generate_trace_traffic "$ingress_ip" "$alias"
  verify_prometheus_data "$context" "$alias"
  verify_slo_rules "$context" "$alias"
  verify_alertmanager "$context" "$alias"
  verify_tempo_data "$context" "$alias"
}

install_cluster() {
  local context="$1"
  local alias="$2"
  local ingress_ip="$3"

  verify_mesh_provider "$context" "$alias"

  kubectl --context "$context" create namespace "$OBSERVABILITY_NAMESPACE" \
    --dry-run=client --output yaml |
    kubectl --context "$context" apply -f -

  helm_upgrade observability prometheus-community/kube-prometheus-stack \
    --kube-context "$context" \
    --namespace "$OBSERVABILITY_NAMESPACE" \
    --version "$KUBE_PROMETHEUS_STACK_VERSION" \
    --values "$ROOT_DIR/gitops/observability/helm/kube-prometheus-stack-values.yaml" \
    --set-string "prometheus.prometheusSpec.externalLabels.cluster=$alias"

  helm_upgrade tempo grafana-community/tempo \
    --kube-context "$context" \
    --namespace "$OBSERVABILITY_NAMESPACE" \
    --version "$TEMPO_VERSION" \
    --values "$ROOT_DIR/gitops/observability/helm/tempo-values.yaml"

  helm_upgrade otel-collector open-telemetry/opentelemetry-collector \
    --kube-context "$context" \
    --namespace "$OBSERVABILITY_NAMESPACE" \
    --version "$OTEL_COLLECTOR_VERSION" \
    --values "$ROOT_DIR/gitops/observability/helm/otel-collector-values.yaml"

  kubectl --context "$context" apply \
    --kustomize "$ROOT_DIR/gitops/observability/bootstrap"

  run_argocd_core "$context" app sync observability-policy --timeout 300
  run_argocd_core "$context" app wait observability-policy \
    --sync --health --timeout 300

  verify_runtime "$context" "$alias" "$ingress_ip"
}

bootstrap() {
  local gke_ingress_ip
  local aks_ingress_ip

  for command_name in kubectl helm terraform argocd curl jq grep; do
    require_command "$command_name"
  done
  load_contexts
  trap stop_port_forward EXIT

  check_cluster_access "$GKE_CONTEXT" gke
  check_cluster_access "$AKS_CONTEXT" aks

  gke_ingress_ip="$(terraform_output gke_ingress_public_ip)"
  aks_ingress_ip="$(terraform_output aks_ingress_public_ip)"

  helm repo add prometheus-community \
    https://prometheus-community.github.io/helm-charts --force-update >/dev/null
  helm repo add open-telemetry \
    https://open-telemetry.github.io/opentelemetry-helm-charts --force-update >/dev/null
  helm repo add grafana-community \
    https://grafana-community.github.io/helm-charts --force-update >/dev/null
  helm repo update prometheus-community open-telemetry grafana-community >/dev/null

  install_cluster "$GKE_CONTEXT" gke "$gke_ingress_ip"
  install_cluster "$AKS_CONTEXT" aks "$aks_ingress_ip"

  echo "Observability is ready in both clusters."
}

cluster_status() {
  local context="$1"
  local alias="$2"
  local ingress_ip="$3"

  echo "=== ${alias} ==="
  helm --kube-context "$context" --namespace "$OBSERVABILITY_NAMESPACE" list
  kubectl --context "$context" --namespace "$OBSERVABILITY_NAMESPACE" \
    get deployment,statefulset,daemonset,pods,service
  kubectl --context "$context" --namespace "$PLATFORM_NAMESPACE" \
    get telemetry,podmonitor,prometheusrule
  run_argocd_core "$context" app get observability-policy
  verify_runtime "$context" "$alias" "$ingress_ip"
}

status() {
  local gke_ingress_ip
  local aks_ingress_ip

  for command_name in kubectl helm terraform argocd curl jq; do
    require_command "$command_name"
  done
  load_contexts
  trap stop_port_forward EXIT

  gke_ingress_ip="$(terraform_output gke_ingress_public_ip)"
  aks_ingress_ip="$(terraform_output aks_ingress_public_ip)"

  cluster_status "$GKE_CONTEXT" gke "$gke_ingress_ip"
  cluster_status "$AKS_CONTEXT" aks "$aks_ingress_ip"
}

port_forward() {
  local alias="${1:-}"
  local context

  require_command kubectl
  load_contexts

  case "$alias" in
    gke)
      context="$GKE_CONTEXT"
      ;;
    aks)
      context="$AKS_CONTEXT"
      ;;
    *)
      usage
      exit 2
      ;;
  esac

  echo "Grafana is available at http://127.0.0.1:${GRAFANA_LOCAL_PORT} while this command runs."
  kubectl --context "$context" --namespace "$OBSERVABILITY_NAMESPACE" \
    port-forward service/observability-grafana "${GRAFANA_LOCAL_PORT}:80"
}

case "${1:-}" in
  bootstrap)
    bootstrap
    ;;
  status)
    status
    ;;
  port-forward)
    port_forward "${2:-}"
    ;;
  *)
    usage
    exit 2
    ;;
esac
