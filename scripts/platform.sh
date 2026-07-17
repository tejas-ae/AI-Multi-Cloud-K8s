#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM_NAMESPACE="${PLATFORM_NAMESPACE:-platform}"
GKE_CONTEXT="${GKE_CONTEXT:-}"
AKS_CONTEXT="${AKS_CONTEXT:-}"

usage() {
  echo "usage: $0 bootstrap|status" >&2
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
  if [[ "$(kubectl --context "$context" --namespace "$PLATFORM_NAMESPACE" \
    auth can-i create roles.rbac.authorization.k8s.io)" != "yes" ]]; then
    echo "$alias context cannot create the workload Role" >&2
    exit 1
  fi
  if [[ "$(kubectl --context "$context" --namespace argocd \
    auth can-i create applications.argoproj.io)" != "yes" ]]; then
    echo "$alias context cannot create the Argo CD Application" >&2
    exit 1
  fi
}

wait_for_http() {
  local url="$1"
  local label="$2"
  local attempt

  for ((attempt = 1; attempt <= 30; attempt++)); do
    if curl --fail --silent --show-error \
      --connect-timeout 5 \
      --max-time 10 \
      "$url" >/dev/null 2>&1; then
      echo "$label health route is ready."
      return 0
    fi
    sleep 10
  done

  echo "$label health route did not become ready: $url" >&2
  return 1
}

verify_cluster() {
  local context="$1"
  local alias="$2"
  local ingress_ip="$3"
  local mtls_mode

  kubectl --context "$context" --namespace "$PLATFORM_NAMESPACE" \
    rollout status deployment/platform-api --timeout=10m

  mtls_mode="$(kubectl --context "$context" --namespace "$PLATFORM_NAMESPACE" \
    get peerauthentication default --output jsonpath='{.spec.mtls.mode}')"
  if [[ "$mtls_mode" != "STRICT" ]]; then
    echo "$alias platform namespace is not enforcing strict mTLS" >&2
    return 1
  fi

  if ! kubectl --context "$context" --namespace "$PLATFORM_NAMESPACE" \
    get pods --selector app.kubernetes.io/name=platform-api --output json |
    jq -e '
      (.items | length == 2)
      and all(
        .items[];
        ([.spec.containers[].name] | index("istio-proxy")) != null
      )
    ' >/dev/null; then
    echo "$alias workload does not have two sidecar-injected Pods" >&2
    return 1
  fi

  wait_for_http "http://${ingress_ip}/healthz" "$alias ingress"
}

install_cluster() {
  local context="$1"
  local alias="$2"
  local ingress_ip="$3"

  kubectl --context "$context" apply \
    --kustomize "$ROOT_DIR/gitops/workloads/bootstrap"

  run_argocd_core "$context" app sync platform-api --timeout 300
  run_argocd_core "$context" app wait platform-api --sync --health --timeout 600
  verify_cluster "$context" "$alias" "$ingress_ip"
}

bootstrap() {
  local gke_ingress_ip
  local aks_ingress_ip
  local traffic_manager_fqdn

  for command_name in kubectl terraform argocd curl jq; do
    require_command "$command_name"
  done
  load_contexts

  check_cluster_access "$GKE_CONTEXT" gke
  check_cluster_access "$AKS_CONTEXT" aks

  gke_ingress_ip="$(terraform_output gke_ingress_public_ip)"
  aks_ingress_ip="$(terraform_output aks_ingress_public_ip)"
  traffic_manager_fqdn="$(terraform_output traffic_manager_fqdn)"

  install_cluster "$GKE_CONTEXT" gke "$gke_ingress_ip"
  install_cluster "$AKS_CONTEXT" aks "$aks_ingress_ip"
  wait_for_http "http://${traffic_manager_fqdn}/healthz" "Traffic Manager"

  echo "The platform workload is ready through both ingresses and Traffic Manager."
}

cluster_status() {
  local context="$1"
  local alias="$2"
  local ingress_ip="$3"

  echo "=== ${alias} ==="
  kubectl --context "$context" --namespace "$PLATFORM_NAMESPACE" \
    get deployment,pods,service,poddisruptionbudget
  kubectl --context "$context" --namespace "$PLATFORM_NAMESPACE" \
    get gateway,virtualservice
  run_argocd_core "$context" app get platform-api
  verify_cluster "$context" "$alias" "$ingress_ip"
}

status() {
  local gke_ingress_ip
  local aks_ingress_ip
  local traffic_manager_fqdn

  for command_name in kubectl terraform argocd curl jq; do
    require_command "$command_name"
  done
  load_contexts

  gke_ingress_ip="$(terraform_output gke_ingress_public_ip)"
  aks_ingress_ip="$(terraform_output aks_ingress_public_ip)"
  traffic_manager_fqdn="$(terraform_output traffic_manager_fqdn)"

  cluster_status "$GKE_CONTEXT" gke "$gke_ingress_ip"
  cluster_status "$AKS_CONTEXT" aks "$aks_ingress_ip"
  wait_for_http "http://${traffic_manager_fqdn}/healthz" "Traffic Manager"
}

case "${1:-}" in
  bootstrap)
    bootstrap
    ;;
  status)
    status
    ;;
  *)
    usage
    exit 2
    ;;
esac
