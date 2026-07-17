#!/usr/bin/env bash
set -euo pipefail

require_value() {
  local name="$1"
  if [[ -z "${!name:-}" || "${!name}" == "replace-me" ]]; then
    echo "$name must be loaded from .env" >&2
    exit 1
  fi
}

require_value GCP_PROJECT_ID
require_value GCP_ZONE
require_value AZURE_LOCATION

gke_json="$(gcloud container get-server-config \
  --zone "$GCP_ZONE" \
  --project "$GCP_PROJECT_ID" \
  --format=json)"

aks_json="$(az aks get-versions \
  --location "$AZURE_LOCATION" \
  --output json)"

echo "GKE Regular channel versions"
jq -r '.channels[]? | select((.channel // "") == "REGULAR") | .validVersions[]?' <<<"$gke_json"

echo
echo "AKS versions in the configured region"
jq -r '[
  (.values[]? | .patchVersions? | objects | keys[]),
  (.values[]?.version? // empty),
  (.orchestrators[]?.orchestratorVersion? // empty)
] | unique[]' <<<"$aks_json"
