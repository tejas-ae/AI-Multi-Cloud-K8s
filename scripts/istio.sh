#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISTIO_VERSION="${ISTIO_VERSION:-1.30.3}"
ISTIO_SYSTEM_NAMESPACE="${ISTIO_SYSTEM_NAMESPACE:-istio-system}"
ISTIO_INGRESS_NAMESPACE="${ISTIO_INGRESS_NAMESPACE:-istio-ingress}"
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
  require_value AZURE_RESOURCE_GROUP
  require_value AKS_CLUSTER_NAME

  GKE_CONTEXT="${GKE_CONTEXT:-gke_${GCP_PROJECT_ID}_${GCP_ZONE}_${GCP_CLUSTER_NAME}}"
  AKS_CONTEXT="${AKS_CONTEXT:-$AKS_CLUSTER_NAME}"
}

terraform_output() {
  terraform -chdir="$ROOT_DIR/terraform" output -raw "$1"
}

check_cluster_access() {
  local context="$1"
  local alias="$2"

  kubectl --context "$context" get --raw=/readyz >/dev/null
  if [[ "$(kubectl --context "$context" auth can-i create customresourcedefinitions.apiextensions.k8s.io)" != "yes" ]]; then
    echo "$alias context cannot create the Istio CRDs" >&2
    exit 1
  fi
  if [[ "$(kubectl --context "$context" auth can-i create namespaces)" != "yes" ]]; then
    echo "$alias context cannot create the Istio namespaces" >&2
    exit 1
  fi
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

wait_for_ingress_ip() {
  local context="$1"
  local expected_ip="$2"
  local actual_ip=""
  local attempt

  for ((attempt = 1; attempt <= 60; attempt++)); do
    actual_ip="$(kubectl --context "$context" --namespace "$ISTIO_INGRESS_NAMESPACE" \
      get service istio-ingress \
      --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
    if [[ "$actual_ip" == "$expected_ip" ]]; then
      echo "ingress address is ready: $actual_ip"
      return 0
    fi
    sleep 10
  done

  echo "Istio ingress did not claim the expected address" >&2
  echo "expected: $expected_ip" >&2
  echo "observed: ${actual_ip:-not assigned}" >&2
  return 1
}

install_cluster() {
  local context="$1"
  local alias="$2"
  local expected_ip="$3"
  local mesh_id="mesh-${alias}"
  local trust_domain="${alias}.ai-multicloud.local"
  local network="network-${alias}"
  local cluster_name="$alias"
  local -a gateway_provider_values
  local -a istiod_command

  kubectl --context "$context" apply \
    -f "$ROOT_DIR/gitops/mesh/bootstrap/namespaces.yaml"

  helm upgrade --install istio-base istio/base \
    --kube-context "$context" \
    --namespace "$ISTIO_SYSTEM_NAMESPACE" \
    --version "$ISTIO_VERSION" \
    --wait \
    --timeout 10m

  kubectl --context "$context" wait \
    --for=condition=Established \
    customresourcedefinition/peerauthentications.security.istio.io \
    --timeout=5m

  istiod_command=(helm upgrade --install istiod istio/istiod \
    --kube-context "$context" \
    --namespace "$ISTIO_SYSTEM_NAMESPACE" \
    --version "$ISTIO_VERSION" \
    --values "$ROOT_DIR/gitops/mesh/helm/istiod-values.yaml" \
    --set-string "global.meshID=$mesh_id" \
    --set-string "global.multiCluster.clusterName=$cluster_name" \
    --set-string "global.network=$network" \
    --set-string "meshConfig.trustDomain=$trust_domain")

  if [[ "$(helm version --template '{{.Version}}')" == v4.* ]]; then
    istiod_command+=(--server-side=false)
  fi

  istiod_command+=(--wait --timeout 10m)
  "${istiod_command[@]}"

  case "$alias" in
    gke)
      gateway_provider_values=(
        --set-string "service.annotations.cloud\\.google\\.com/l4-rbs=enabled"
        --set-string "service.annotations.cloud\\.google\\.com/network-tier=Premium"
        --set-string "service.annotations.networking\\.gke\\.io/load-balancer-ip-addresses=ai-multicloud-k8s-gke-ingress"
      )
      ;;
    aks)
      local aks_node_resource_group
      aks_node_resource_group="$(az aks show \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --name "$AKS_CLUSTER_NAME" \
        --query nodeResourceGroup \
        --output tsv)"
      gateway_provider_values=(
        --set-string "service.annotations.service\\.beta\\.kubernetes\\.io/azure-pip-name=ai-multicloud-k8s-aks-ingress"
        --set-string "service.annotations.service\\.beta\\.kubernetes\\.io/azure-load-balancer-resource-group=$aks_node_resource_group"
        --set-string "service.annotations.service\\.beta\\.kubernetes\\.io/azure-load-balancer-health-probe-request-path=/healthz/ready"
      )
      ;;
    *)
      echo "unsupported cluster alias: $alias" >&2
      exit 2
      ;;
  esac

  helm upgrade --install istio-ingress istio/gateway \
    --kube-context "$context" \
    --namespace "$ISTIO_INGRESS_NAMESPACE" \
    --version "$ISTIO_VERSION" \
    --values "$ROOT_DIR/gitops/mesh/helm/gateway-values.yaml" \
    --set-string "service.loadBalancerIP=$expected_ip" \
    "${gateway_provider_values[@]}" \
    --wait \
    --timeout 15m

  kubectl --context "$context" --namespace "$ISTIO_SYSTEM_NAMESPACE" \
    rollout status deployment/istiod --timeout=10m
  kubectl --context "$context" --namespace "$ISTIO_INGRESS_NAMESPACE" \
    rollout status deployment/istio-ingress --timeout=10m

  kubectl --context "$context" apply \
    -f "$ROOT_DIR/gitops/mesh/bootstrap/argocd-rbac.yaml"
  kubectl --context "$context" apply \
    -f "$ROOT_DIR/gitops/mesh/argocd/project.yaml"
  kubectl --context "$context" apply \
    -f "$ROOT_DIR/gitops/mesh/argocd/application.yaml"

  run_argocd_core "$context" app sync mesh-security --timeout 300
  run_argocd_core "$context" app wait mesh-security --sync --health --timeout 300
  wait_for_ingress_ip "$context" "$expected_ip"
}

bootstrap() {
  local gke_ingress_ip
  local aks_ingress_ip

  for command_name in kubectl helm terraform argocd az; do
    require_command "$command_name"
  done
  load_contexts

  check_cluster_access "$GKE_CONTEXT" gke
  check_cluster_access "$AKS_CONTEXT" aks

  gke_ingress_ip="$(terraform_output gke_ingress_public_ip)"
  aks_ingress_ip="$(terraform_output aks_ingress_public_ip)"

  helm repo add istio https://istio-release.storage.googleapis.com/charts --force-update >/dev/null
  helm repo update istio >/dev/null

  install_cluster "$GKE_CONTEXT" gke "$gke_ingress_ip"
  install_cluster "$AKS_CONTEXT" aks "$aks_ingress_ip"

  echo "Istio is ready in both clusters. Run make mesh-status to inspect it."
}

cluster_status() {
  local context="$1"
  local alias="$2"
  local expected_ip="$3"
  local actual_ip

  echo "=== ${alias} ==="
  helm --kube-context "$context" --namespace "$ISTIO_SYSTEM_NAMESPACE" list
  helm --kube-context "$context" --namespace "$ISTIO_INGRESS_NAMESPACE" list
  kubectl --context "$context" --namespace "$ISTIO_SYSTEM_NAMESPACE" get pods
  kubectl --context "$context" --namespace "$ISTIO_INGRESS_NAMESPACE" get pods,service
  kubectl --context "$context" get namespace "$PLATFORM_NAMESPACE" --show-labels
  kubectl --context "$context" --namespace "$PLATFORM_NAMESPACE" get peerauthentication
  run_argocd_core "$context" app get mesh-security

  actual_ip="$(kubectl --context "$context" --namespace "$ISTIO_INGRESS_NAMESPACE" \
    get service istio-ingress \
    --output jsonpath='{.status.loadBalancer.ingress[0].ip}')"
  if [[ "$actual_ip" != "$expected_ip" ]]; then
    echo "$alias ingress address mismatch: expected $expected_ip, observed $actual_ip" >&2
    return 1
  fi
  echo "$alias ingress address matches the Terraform reservation."
}

status() {
  local gke_ingress_ip
  local aks_ingress_ip

  for command_name in kubectl helm terraform argocd; do
    require_command "$command_name"
  done
  load_contexts

  gke_ingress_ip="$(terraform_output gke_ingress_public_ip)"
  aks_ingress_ip="$(terraform_output aks_ingress_public_ip)"

  cluster_status "$GKE_CONTEXT" gke "$gke_ingress_ip"
  cluster_status "$AKS_CONTEXT" aks "$aks_ingress_ip"
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
