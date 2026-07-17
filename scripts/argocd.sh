#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_RELEASE_NAME="${ARGOCD_RELEASE_NAME:-argocd}"
ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-9.7.1}"
GKE_CONTEXT="${GKE_CONTEXT:-}"
AKS_CONTEXT="${AKS_CONTEXT:-}"

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

check_cluster_access() {
  local context="$1"
  local alias="$2"

  kubectl --context "$context" get --raw=/readyz >/dev/null
  if [[ "$(kubectl --context "$context" auth can-i create namespaces)" != "yes" ]]; then
    echo "$alias context cannot provision namespaces; the bootstrap needs operator access for the chart CRDs and namespace" >&2
    exit 1
  fi
}

install_argocd() {
  local context="$1"

  helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null
  helm repo update argo >/dev/null
  helm upgrade --install "$ARGOCD_RELEASE_NAME" argo/argo-cd \
    --kube-context "$context" \
    --namespace "$ARGOCD_NAMESPACE" \
    --create-namespace \
    --reset-values \
    --version "$ARGOCD_CHART_VERSION" \
    --values "$ROOT_DIR/gitops/bootstrap/argocd/values.yaml" \
    --wait \
    --timeout 10m

  kubectl --context "$context" --namespace "$ARGOCD_NAMESPACE" \
    get configmap argocd-cm >/dev/null

  kubectl --context "$context" --namespace "$ARGOCD_NAMESPACE" \
    rollout status statefulset/argocd-application-controller --timeout=10m
  kubectl --context "$context" --namespace "$ARGOCD_NAMESPACE" \
    wait --for=condition=Available deployment --all --timeout=10m
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
    config set-context --current --namespace "$ARGOCD_NAMESPACE" >/dev/null

  KUBECONFIG="$temporary_kubeconfig" argocd --core "$@"
)

apply_bootstrap_config() {
  local context="$1"

  kubectl --context "$context" apply -f "$ROOT_DIR/gitops/bootstrap/argocd/application.yaml"
  run_argocd_core "$context" app sync platform-bootstrap --timeout 300
  run_argocd_core "$context" app wait platform-bootstrap --sync --health --timeout 300
}

bootstrap() {
  for command_name in kubectl helm argocd; do
    require_command "$command_name"
  done
  load_contexts

  check_cluster_access "$GKE_CONTEXT" gke
  check_cluster_access "$AKS_CONTEXT" aks

  install_argocd "$GKE_CONTEXT"
  install_argocd "$AKS_CONTEXT"

  apply_bootstrap_config "$GKE_CONTEXT"
  apply_bootstrap_config "$AKS_CONTEXT"

  echo "Argo CD is ready in both clusters. Run make gitops-status to inspect it."
}

status() {
  for command_name in kubectl argocd; do
    require_command "$command_name"
  done
  load_contexts

  for entry in "gke:$GKE_CONTEXT" "aks:$AKS_CONTEXT"; do
    alias="${entry%%:*}"
    context="${entry#*:}"
    echo "=== ${alias} ==="
    kubectl --context "$context" --namespace "$ARGOCD_NAMESPACE" get pods,applications,appprojects
    run_argocd_core "$context" app get platform-bootstrap
  done
}

port_forward() {
  local alias="$1"
  local context

  require_command kubectl
  load_contexts

  case "$alias" in
    gke) context="$GKE_CONTEXT" ;;
    aks) context="$AKS_CONTEXT" ;;
    *) usage; exit 2 ;;
  esac

  echo "Argo CD is available at https://localhost:8080 while this command runs."
  kubectl --context "$context" --namespace "$ARGOCD_NAMESPACE" \
    port-forward service/argocd-server 8080:443
}

case "${1:-}" in
  bootstrap)
    bootstrap
    ;;
  status)
    status
    ;;
  port-forward)
    [[ $# -eq 2 ]] || { usage; exit 2; }
    port_forward "$2"
    ;;
  *)
    usage
    exit 2
    ;;
esac
