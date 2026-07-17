#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

passes=0
warnings=0
failures=0

pass() { passes=$((passes + 1)); printf 'PASS %s\n' "$*"; }
warn() { warnings=$((warnings + 1)); printf 'WARN %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf 'FAIL %s\n' "$*"; }
section() { printf '\n%s\n' "$*"; }
has() { command -v "$1" >/dev/null 2>&1; }

require_command() {
  if has "$1"; then pass "required command available: $1"; else fail "required command missing: $1"; fi
}

recommend_command() {
  if has "$1"; then pass "recommended command available: $1"; else warn "recommended command missing: $1"; fi
}

require_value() {
  local name="$1"
  local value="$2"
  if [[ -n "$value" && "$value" != "replace-me" ]]; then
    pass "$name is configured (value hidden)"
  else
    fail "$name is not configured"
  fi
}

is_number() { [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]; }
gte() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a >= b) }'; }

is_ipv4_cidr32() {
  local cidr="$1"
  local ip
  local first second third fourth
  local octet

  [[ "$cidr" == */32 ]] || return 1
  ip="${cidr%/32}"
  IFS=. read -r first second third fourth <<<"$ip"
  for octet in "$first" "$second" "$third" "$fourth"; do
    [[ "$octet" =~ ^[0-9]{1,3}$ ]] || return 1
    (( 10#$octet <= 255 )) || return 1
  done
}

deadline_epoch() {
  local input="$1"
  local normalized="${input:0:${#input}-3}${input: -2}"
  date -d "$input" +%s 2>/dev/null ||
    date -j -f '%Y-%m-%dT%H:%M:%S%z' "$input" +%s 2>/dev/null ||
    date -j -f '%Y-%m-%dT%H:%M:%S%z' "$normalized" +%s 2>/dev/null
}

section "macOS"
if [[ "$(uname -s)" == "Darwin" ]]; then
  pass "running on macOS"
  macos_major="$(sw_vers -productVersion | cut -d. -f1)"
  if [[ "$macos_major" =~ ^[0-9]+$ ]] && (( macos_major >= 13 )); then
    pass "macOS 13 or newer detected"
  else
    fail "macOS 13 or newer is required by the current Azure CLI package"
  fi
else
  fail "this workstation preflight expects macOS"
fi

section "Toolchain"
for command_name in terraform gcloud az kubectl kubelogin helm docker gh git jq curl openssl; do
  require_command "$command_name"
done
for command_name in shellcheck conftest istioctl k6 trivy cosign syft argocd yq; do
  recommend_command "$command_name"
done

if has docker; then
  if docker info >/dev/null 2>&1; then pass "Docker Desktop is running"; else fail "Docker Desktop is not running"; fi
fi

section "Repository"
if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  pass "working directory is a Git repository"
  branch="$(git -C "$ROOT_DIR" branch --show-current 2>/dev/null || true)"
  if [[ "$branch" == "main" ]]; then pass "branch is $branch"; else fail "unexpected branch: ${branch:-detached}"; fi
  if git -C "$ROOT_DIR" ls-files | grep -Eq '(^|/)([^/]*\.tfstate($|\.)|[^/]*\.tfplan($|\.)|\.env($|\.)|kubeconfig|[^/]*\.pem$|[^/]*\.key$)'; then
    fail "Git tracks a state, plan, environment, kubeconfig, or private-key file"
  else
    pass "common secret and state file types are not tracked"
  fi
else
  fail "working directory is not a Git repository"
fi

GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
GCP_REGION="${GCP_REGION:-us-central1}"
GCP_ZONE="${GCP_ZONE:-us-central1-a}"
GCP_CLUSTER_NAME="${GCP_CLUSTER_NAME:-ai-multicloud-k8s-gke}"
GCP_NODE_MACHINE_TYPE="${GCP_NODE_MACHINE_TYPE:-e2-standard-4}"
GCP_REQUIRED_VCPUS="${GCP_REQUIRED_VCPUS:-8}"
GKE_KUBERNETES_VERSION="${GKE_KUBERNETES_VERSION:-}"
GCP_BUDGET_DISPLAY_NAME="${GCP_BUDGET_DISPLAY_NAME:-}"
TF_STATE_BUCKET="${TF_STATE_BUCKET:-}"

AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-}"
AZURE_LOCATION="${AZURE_LOCATION:-eastus}"
AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-ai-multicloud-k8s-prod}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-ai-multicloud-k8s-aks}"
AZURE_NODE_VM_SIZE="${AZURE_NODE_VM_SIZE:-Standard_D4s_v3}"
AZURE_REQUIRED_VCPUS="${AZURE_REQUIRED_VCPUS:-8}"
AKS_KUBERNETES_VERSION="${AKS_KUBERNETES_VERSION:-}"
AZURE_BUDGET_NAME="${AZURE_BUDGET_NAME:-}"

GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
ADMIN_CIDR="${ADMIN_CIDR:-}"
DEMO_MAX_BUDGET_USD="${DEMO_MAX_BUDGET_USD:-}"
DEMO_DESTRUCTION_DEADLINE="${DEMO_DESTRUCTION_DEADLINE:-}"
ANTHROPIC_KEY="${ANTHROPIC_API_KEY:-}"

section "Cost and time gates"
require_value "DEMO_MAX_BUDGET_USD" "$DEMO_MAX_BUDGET_USD"
if [[ -n "$DEMO_MAX_BUDGET_USD" ]]; then
  if is_number "$DEMO_MAX_BUDGET_USD" && gte 100 "$DEMO_MAX_BUDGET_USD"; then pass "demo cap is at or below USD 100"; else fail "demo cap must be a number no greater than USD 100"; fi
fi
require_value "DEMO_DESTRUCTION_DEADLINE" "$DEMO_DESTRUCTION_DEADLINE"
if [[ -n "$DEMO_DESTRUCTION_DEADLINE" ]]; then
  parsed_deadline="$(deadline_epoch "$DEMO_DESTRUCTION_DEADLINE" || true)"
  if [[ "$parsed_deadline" =~ ^[0-9]+$ ]] && (( parsed_deadline > $(date +%s) )); then pass "destruction deadline is in the future"; else fail "destruction deadline is invalid or has passed"; fi
fi
require_value "ANTHROPIC_API_KEY" "$ANTHROPIC_KEY"

section "Platform versions"
require_value "GKE_KUBERNETES_VERSION" "$GKE_KUBERNETES_VERSION"
require_value "AKS_KUBERNETES_VERSION" "$AKS_KUBERNETES_VERSION"

section "Operator access"
require_value "ADMIN_CIDR" "$ADMIN_CIDR"
if is_ipv4_cidr32 "$ADMIN_CIDR"; then
  pass "operator access is restricted to one IPv4 address"
else
  fail "ADMIN_CIDR must be a valid IPv4 /32"
fi

section "GCP"
require_value "GCP_PROJECT_ID" "$GCP_PROJECT_ID"
require_value "TF_STATE_BUCKET" "$TF_STATE_BUCKET"
require_value "GCP_BUDGET_DISPLAY_NAME" "$GCP_BUDGET_DISPLAY_NAME"
if has gcloud; then
  if gcloud auth print-access-token >/dev/null 2>&1; then pass "Google Cloud authentication works"; else fail "Google Cloud authentication failed"; fi
  if gcloud auth application-default print-access-token >/dev/null 2>&1; then pass "Google Application Default Credentials work"; else fail "Google Application Default Credentials failed"; fi
  if [[ -n "$GCP_PROJECT_ID" && "$GCP_PROJECT_ID" != "replace-me" ]]; then
    if gcloud projects describe "$GCP_PROJECT_ID" >/dev/null 2>&1; then pass "GCP project is accessible"; else fail "GCP project is inaccessible"; fi
    billing="$(gcloud billing projects describe "$GCP_PROJECT_ID" --format='value(billingEnabled)' 2>/dev/null || true)"
    if [[ "$billing" == "True" || "$billing" == "true" ]]; then pass "GCP billing is enabled"; else fail "GCP billing is not enabled"; fi

    required_apis=(artifactregistry.googleapis.com cloudbilling.googleapis.com cloudresourcemanager.googleapis.com compute.googleapis.com container.googleapis.com iamcredentials.googleapis.com secretmanager.googleapis.com serviceusage.googleapis.com)
    enabled_apis="$(gcloud services list --enabled --project "$GCP_PROJECT_ID" --format='value(config.name)' 2>/dev/null || true)"
    for api in "${required_apis[@]}"; do
      if grep -Fqx "$api" <<<"$enabled_apis"; then pass "GCP API enabled: $api"; else fail "GCP API not enabled: $api"; fi
    done

    if gcloud compute machine-types describe "$GCP_NODE_MACHINE_TYPE" --zone "$GCP_ZONE" --project "$GCP_PROJECT_ID" >/dev/null 2>&1; then pass "GKE node machine type is available"; else fail "GKE node machine type is unavailable"; fi
    gke_server_config="$(gcloud container get-server-config --zone "$GCP_ZONE" --project "$GCP_PROJECT_ID" --format=json 2>/dev/null || true)"
    gke_regular_versions="$(jq -r '.channels[]? | select((.channel // "") == "REGULAR") | .validVersions[]?' <<<"$gke_server_config" 2>/dev/null || true)"
    if [[ -n "$GKE_KUBERNETES_VERSION" ]] && grep -Fqx "$GKE_KUBERNETES_VERSION" <<<"$gke_regular_versions"; then
      pass "selected GKE version is available in the Regular channel"
    else
      fail "selected GKE version is unavailable in the Regular channel"
    fi
    region_json="$(gcloud compute regions describe "$GCP_REGION" --project "$GCP_PROJECT_ID" --format=json 2>/dev/null || true)"
    available_gcp_cpu="$(jq -r '.quotas[]? | select(.metric == "CPUS") | (.limit - .usage)' <<<"$region_json" 2>/dev/null | head -n1)"
    if is_number "$available_gcp_cpu" && gte "$available_gcp_cpu" "$GCP_REQUIRED_VCPUS"; then pass "GCP has at least $GCP_REQUIRED_VCPUS regional vCPUs free"; else fail "GCP regional CPU quota is insufficient or unreadable"; fi

    if [[ -n "$TF_STATE_BUCKET" && "$TF_STATE_BUCKET" != "replace-me" ]] && gcloud storage buckets describe "gs://${TF_STATE_BUCKET}" >/dev/null 2>&1; then pass "Terraform state bucket is accessible"; else fail "Terraform state bucket is unavailable"; fi
    billing_account="$(gcloud billing projects describe "$GCP_PROJECT_ID" --format='value(billingAccountName)' 2>/dev/null | sed 's#billingAccounts/##' || true)"
    if [[ -n "$billing_account" && -n "$GCP_BUDGET_DISPLAY_NAME" ]] && gcloud billing budgets list --billing-account "$billing_account" --filter="displayName=$GCP_BUDGET_DISPLAY_NAME" --format='value(name)' 2>/dev/null | grep -q .; then pass "GCP budget exists"; else fail "GCP budget is unavailable"; fi
    existing_gke="$(gcloud container clusters list --project "$GCP_PROJECT_ID" --filter="name=$GCP_CLUSTER_NAME" --format='value(name)' 2>/dev/null || true)"
    if [[ -z "$existing_gke" ]]; then pass "no pre-existing GKE cluster conflicts with the planned name"; else fail "a GKE cluster already uses the planned name"; fi
  fi
fi

section "Azure"
require_value "AZURE_SUBSCRIPTION_ID" "$AZURE_SUBSCRIPTION_ID"
require_value "AZURE_BUDGET_NAME" "$AZURE_BUDGET_NAME"
if has az; then
  if az account show >/dev/null 2>&1; then pass "Azure authentication works"; else fail "Azure authentication failed"; fi
  active_subscription="$(az account show --query id -o tsv 2>/dev/null || true)"
  if [[ -n "$AZURE_SUBSCRIPTION_ID" && "$active_subscription" == "$AZURE_SUBSCRIPTION_ID" ]]; then pass "active Azure subscription is correct"; else fail "active Azure subscription does not match"; fi
  subscription_state="$(az account show --query state -o tsv 2>/dev/null || true)"
  if [[ "$subscription_state" == "Enabled" ]]; then pass "Azure subscription is enabled"; else fail "Azure subscription is not enabled"; fi
  for namespace in Microsoft.Compute Microsoft.ContainerService Microsoft.Network; do
    state="$(az provider show --namespace "$namespace" --query registrationState -o tsv 2>/dev/null || true)"
    if [[ "$state" == "Registered" ]]; then pass "Azure provider registered: $namespace"; else fail "Azure provider is not registered: $namespace"; fi
  done
  sku_json="$(az vm list-skus --location "$AZURE_LOCATION" --size "$AZURE_NODE_VM_SIZE" --all -o json 2>/dev/null || true)"
  sku_count="$(jq -r --arg size "$AZURE_NODE_VM_SIZE" '[.[] | select(.name == $size)] | length' <<<"$sku_json" 2>/dev/null || true)"
  sku_restrictions="$(jq -r --arg size "$AZURE_NODE_VM_SIZE" '[.[] | select(.name == $size) | .restrictions[]? | select(.reasonCode == "NotAvailableForSubscription")] | length' <<<"$sku_json" 2>/dev/null || true)"
  sku_family="$(jq -r --arg size "$AZURE_NODE_VM_SIZE" '[.[] | select(.name == $size)][0].family // empty' <<<"$sku_json" 2>/dev/null || true)"
  if [[ "$sku_count" =~ ^[0-9]+$ ]] && (( sku_count > 0 )) && [[ "$sku_restrictions" == "0" ]]; then
    pass "AKS node VM size is available"
  else
    fail "AKS node VM size is unavailable for this subscription or could not be read"
  fi

  aks_version_json="$(az aks get-versions --location "$AZURE_LOCATION" -o json 2>/dev/null || true)"
  aks_versions="$(jq -r '[
    (.values[]? | .patchVersions? | objects | keys[]),
    (.values[]?.version? // empty),
    (.orchestrators[]?.orchestratorVersion? // empty)
  ] | unique[]' <<<"$aks_version_json" 2>/dev/null || true)"
  if [[ -n "$AKS_KUBERNETES_VERSION" ]] && grep -Fqx "$AKS_KUBERNETES_VERSION" <<<"$aks_versions"; then
    pass "selected AKS version is available in the target region"
  else
    fail "selected AKS version is unavailable in the target region"
  fi

  usage_json="$(az vm list-usage --location "$AZURE_LOCATION" -o json 2>/dev/null || true)"
  available_azure_cpu="$(jq -r '[.[] | select((((.name.value // "") | ascii_downcase) == "cores") or (((.name.localizedValue // "") | test("total regional vcpu"; "i"))))][0] | if . == null then empty else ((.limit | tonumber) - (.currentValue | tonumber)) end' <<<"$usage_json" 2>/dev/null || true)"
  available_azure_family_cpu="$(jq -r --arg family "$sku_family" '[.[] | select((.name.value // "") == $family)][0] | if . == null then empty else ((.limit | tonumber) - (.currentValue | tonumber)) end' <<<"$usage_json" 2>/dev/null || true)"
  if is_number "$available_azure_cpu" && gte "$available_azure_cpu" "$AZURE_REQUIRED_VCPUS"; then
    pass "Azure has at least $AZURE_REQUIRED_VCPUS total regional vCPUs free"
  else
    fail "Azure total regional vCPU quota is insufficient or unreadable"
  fi
  if is_number "$available_azure_family_cpu" && gte "$available_azure_family_cpu" "$AZURE_REQUIRED_VCPUS"; then
    pass "Azure VM-family quota has at least $AZURE_REQUIRED_VCPUS vCPUs free"
  else
    fail "Azure VM-family quota is insufficient or unreadable for $AZURE_NODE_VM_SIZE"
  fi
  if [[ -n "$AZURE_BUDGET_NAME" ]] && az consumption budget show --budget-name "$AZURE_BUDGET_NAME" >/dev/null 2>&1; then pass "Azure budget exists"; else fail "Azure budget is unavailable"; fi
  if az group exists --name "$AZURE_RESOURCE_GROUP" 2>/dev/null | grep -qx false; then pass "no pre-existing Azure resource group conflicts with the planned name"; else fail "the planned Azure resource group already exists or could not be checked"; fi
fi

section "GitHub"
require_value "GITHUB_REPOSITORY" "$GITHUB_REPOSITORY"
if has gh; then
  if gh api user --jq '.login' >/dev/null 2>&1; then pass "GitHub authentication works"; else fail "GitHub authentication failed"; fi
  if [[ -n "$GITHUB_REPOSITORY" && "$GITHUB_REPOSITORY" != "replace-me" ]] && gh repo view "$GITHUB_REPOSITORY" >/dev/null 2>&1; then pass "GitHub repository is accessible"; else fail "GitHub repository is unavailable"; fi
fi

section "Result"
printf 'passes=%d warnings=%d failures=%d\n' "$passes" "$warnings" "$failures"
if (( failures > 0 )); then
  echo "BLOCKED: do not create Kubernetes infrastructure."
  exit 1
fi
echo "READY: preflight passed."
