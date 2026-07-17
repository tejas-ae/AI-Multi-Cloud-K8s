#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "--execute" ]]; then
  echo "usage: $0 --execute" >&2
  echo "Enables prerequisite APIs/providers and creates state and budget guardrails." >&2
  exit 2
fi

required_values=(
  GCP_PROJECT_ID GCP_REGION GCP_BUDGET_DISPLAY_NAME TF_STATE_BUCKET
  AZURE_SUBSCRIPTION_ID AZURE_BUDGET_NAME BUDGET_ALERT_EMAIL
  DEMO_MAX_BUDGET_USD
)
for name in "${required_values[@]}"; do
  if [[ -z "${!name:-}" || "${!name}" == "replace-me" ]]; then
    echo "$name must be configured" >&2
    exit 1
  fi
done

if ! [[ "$DEMO_MAX_BUDGET_USD" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "DEMO_MAX_BUDGET_USD must be numeric" >&2
  exit 1
fi

BUDGET_CURRENCY="${BUDGET_CURRENCY:-USD}"

echo "Configuring GCP foundation"
gcloud config set project "$GCP_PROJECT_ID" >/dev/null
gcloud auth application-default set-quota-project "$GCP_PROJECT_ID" >/dev/null
gcloud services enable \
  artifactregistry.googleapis.com \
  billingbudgets.googleapis.com \
  cloudbilling.googleapis.com \
  cloudresourcemanager.googleapis.com \
  compute.googleapis.com \
  container.googleapis.com \
  iamcredentials.googleapis.com \
  secretmanager.googleapis.com \
  serviceusage.googleapis.com \
  --project "$GCP_PROJECT_ID"

if ! gcloud storage buckets describe "gs://${TF_STATE_BUCKET}" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://${TF_STATE_BUCKET}" \
    --project "$GCP_PROJECT_ID" \
    --location "$GCP_REGION" \
    --uniform-bucket-level-access
fi
gcloud storage buckets update "gs://${TF_STATE_BUCKET}" --versioning

billing_account="$(gcloud billing projects describe "$GCP_PROJECT_ID" --format='value(billingAccountName)' | sed 's#billingAccounts/##')"
project_number="$(gcloud projects describe "$GCP_PROJECT_ID" --format='value(projectNumber)')"
existing_gcp_budget="$(gcloud billing budgets list \
  --billing-account "$billing_account" \
  --filter="displayName=$GCP_BUDGET_DISPLAY_NAME" \
  --format='value(name)' | head -n1)"
if [[ -z "$existing_gcp_budget" ]]; then
  gcloud billing budgets create \
    --billing-account "$billing_account" \
    --display-name "$GCP_BUDGET_DISPLAY_NAME" \
    --budget-amount "${DEMO_MAX_BUDGET_USD}${BUDGET_CURRENCY}" \
    --filter-projects "projects/${project_number}" \
    --calendar-period month \
    --threshold-rule percent=0.50 \
    --threshold-rule percent=0.80 \
    --threshold-rule percent=1.00
fi

echo "Configuring Azure foundation"
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
for namespace in Microsoft.Compute Microsoft.ContainerService Microsoft.Network Microsoft.Consumption; do
  az provider register --namespace "$namespace" --wait
done

budget_start="$(date +%Y-%m-01T00:00:00Z)"
budget_end="$(date -v+1y +%Y-%m-01T00:00:00Z)"
budget_body="$(jq -n \
  --argjson amount "$DEMO_MAX_BUDGET_USD" \
  --arg start "$budget_start" \
  --arg end "$budget_end" \
  --arg email "$BUDGET_ALERT_EMAIL" \
  '{properties:{category:"Cost",amount:$amount,timeGrain:"Monthly",timePeriod:{startDate:$start,endDate:$end},notifications:{Actual_50_Percent:{enabled:true,operator:"GreaterThan",threshold:50,thresholdType:"Actual",contactEmails:[$email],contactRoles:[],contactGroups:[]},Actual_80_Percent:{enabled:true,operator:"GreaterThan",threshold:80,thresholdType:"Actual",contactEmails:[$email],contactRoles:[],contactGroups:[]},Actual_100_Percent:{enabled:true,operator:"GreaterThan",threshold:100,thresholdType:"Actual",contactEmails:[$email],contactRoles:[],contactGroups:[]}}}}')"
az rest \
  --method put \
  --url "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/providers/Microsoft.Consumption/budgets/${AZURE_BUDGET_NAME}?api-version=2024-08-01" \
  --body "$budget_body" \
  --output none

echo "Cloud foundation is configured. Run make preflight next."
