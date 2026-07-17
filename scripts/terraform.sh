#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/terraform"
PLAN_DIR="$TF_DIR/.plans"
PLAN_FILE="$PLAN_DIR/platform.tfplan"
ACTION="${1:-}"

usage() {
  echo "usage: $0 init|fmt|validate|plan|apply|destroy|output" >&2
}

require_value() {
  local name="$1"
  if [[ -z "${!name:-}" || "${!name}" == "replace-me" ]]; then
    echo "$name must be loaded from .env" >&2
    exit 1
  fi
}

require_value GCP_PROJECT_ID
require_value AZURE_SUBSCRIPTION_ID
require_value TF_STATE_BUCKET
require_value ADMIN_CIDR
require_value GKE_KUBERNETES_VERSION
require_value AKS_KUBERNETES_VERSION

GCP_REGION="${GCP_REGION:-us-central1}"
GCP_ZONE="${GCP_ZONE:-us-central1-a}"
GCP_CLUSTER_NAME="${GCP_CLUSTER_NAME:-ai-multicloud-k8s-gke}"
GCP_NODE_MACHINE_TYPE="${GCP_NODE_MACHINE_TYPE:-e2-standard-4}"
AZURE_LOCATION="${AZURE_LOCATION:-eastus}"
AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-ai-multicloud-k8s-prod}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-ai-multicloud-k8s-aks}"
AZURE_NODE_VM_SIZE="${AZURE_NODE_VM_SIZE:-Standard_D4s_v3}"
TF_STATE_PREFIX="${TF_STATE_PREFIX:-ai-multicloud-k8s/portfolio}"

common_vars=(
  -var "gcp_project_id=$GCP_PROJECT_ID"
  -var "gcp_region=$GCP_REGION"
  -var "gcp_zone=$GCP_ZONE"
  -var "gke_cluster_name=$GCP_CLUSTER_NAME"
  -var "gke_node_machine_type=$GCP_NODE_MACHINE_TYPE"
  -var "gke_kubernetes_version=$GKE_KUBERNETES_VERSION"
  -var "azure_subscription_id=$AZURE_SUBSCRIPTION_ID"
  -var "azure_location=$AZURE_LOCATION"
  -var "azure_resource_group_name=$AZURE_RESOURCE_GROUP"
  -var "aks_cluster_name=$AKS_CLUSTER_NAME"
  -var "aks_node_vm_size=$AZURE_NODE_VM_SIZE"
  -var "aks_kubernetes_version=$AKS_KUBERNETES_VERSION"
  -var "admin_cidr=$ADMIN_CIDR"
)

case "$ACTION" in
  init)
    terraform -chdir="$TF_DIR" init \
      -backend-config="bucket=$TF_STATE_BUCKET" \
      -backend-config="prefix=$TF_STATE_PREFIX"
    ;;
  fmt)
    terraform -chdir="$TF_DIR" fmt -recursive
    ;;
  validate)
    terraform -chdir="$TF_DIR" validate
    ;;
  plan)
    mkdir -p "$PLAN_DIR"
    terraform -chdir="$TF_DIR" plan \
      -lock-timeout=10m \
      -out="$PLAN_FILE" \
      "${common_vars[@]}"
    echo "saved plan: terraform/.plans/platform.tfplan"
    ;;
  apply)
    if [[ "${CONFIRM_APPLY:-}" != "AI-Multi-Cloud-K8s" ]]; then
      echo "set CONFIRM_APPLY=AI-Multi-Cloud-K8s to apply the saved plan" >&2
      exit 1
    fi
    [[ -f "$PLAN_FILE" ]] || { echo "run make tf-plan first" >&2; exit 1; }
    terraform -chdir="$TF_DIR" apply -lock-timeout=10m "$PLAN_FILE"
    ;;
  destroy)
    if [[ "${CONFIRM_DESTROY:-}" != "AI-Multi-Cloud-K8s" ]]; then
      echo "set CONFIRM_DESTROY=AI-Multi-Cloud-K8s to destroy the platform" >&2
      exit 1
    fi
    mkdir -p "$PLAN_DIR"
    terraform -chdir="$TF_DIR" plan \
      -destroy \
      -lock-timeout=10m \
      -out="$PLAN_FILE" \
      "${common_vars[@]}"
    terraform -chdir="$TF_DIR" show "$PLAN_FILE"
    terraform -chdir="$TF_DIR" apply -lock-timeout=10m "$PLAN_FILE"
    ;;
  output)
    terraform -chdir="$TF_DIR" output
    ;;
  *)
    usage
    exit 2
    ;;
esac
