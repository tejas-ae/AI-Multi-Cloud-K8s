#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/terraform"
PLAN_FILE="$TF_DIR/.plans/platform.tfplan"

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "run make tf-plan before reviewing the plan" >&2
  exit 1
fi

umask 077
plan_json="$(mktemp "${TMPDIR:-/tmp}/ai-multicloud-plan.XXXXXX")"
trap 'rm -f "$plan_json"' EXIT

terraform -chdir="$TF_DIR" show -json "$PLAN_FILE" >"$plan_json"

jq '
  def after($address):
    [.resource_changes[] | select(.address == $address) | .change.after][0];

  def expected_creates: [
    "module.aks.azurerm_kubernetes_cluster.this",
    "module.aks.azurerm_public_ip.ingress",
    "module.aks.azurerm_resource_group.this",
    "module.aks.azurerm_role_assignment.network_contributor",
    "module.aks.azurerm_role_assignment.operator_cluster_admin",
    "module.aks.azurerm_subnet.aks",
    "module.aks.azurerm_user_assigned_identity.control_plane",
    "module.aks.azurerm_virtual_network.this",
    "module.gke.google_compute_address.ingress",
    "module.gke.google_compute_network.this",
    "module.gke.google_compute_router.this",
    "module.gke.google_compute_router_nat.this",
    "module.gke.google_compute_subnetwork.this",
    "module.gke.google_container_cluster.this",
    "module.gke.google_container_node_pool.primary",
    "module.gke.google_project_iam_member.node_roles[\"roles/artifactregistry.reader\"]",
    "module.gke.google_project_iam_member.node_roles[\"roles/logging.logWriter\"]",
    "module.gke.google_project_iam_member.node_roles[\"roles/monitoring.metricWriter\"]",
    "module.gke.google_project_iam_member.node_roles[\"roles/monitoring.viewer\"]",
    "module.gke.google_service_account.nodes",
    "module.traffic_manager.azurerm_traffic_manager_azure_endpoint.aks",
    "module.traffic_manager.azurerm_traffic_manager_external_endpoint.gke",
    "module.traffic_manager.azurerm_traffic_manager_profile.this",
    "random_string.dns_suffix"
  ];

  def planned_creates:
    [.resource_changes[] | select(.change.actions == ["create"]) | .address];

  def action_summary:
    [.resource_changes[].change.actions | join("+")]
    | group_by(.)
    | map({action: .[0], count: length});

  (after("module.gke.google_container_cluster.this")) as $gke |
  (after("module.gke.google_container_node_pool.primary")) as $gke_nodes |
  (after("module.aks.azurerm_kubernetes_cluster.this")) as $aks |
  (after("module.traffic_manager.azurerm_traffic_manager_profile.this")) as $traffic |
  {
    action_summary: action_summary,
    scope: {
      expected_create_count: (expected_creates | length),
      planned_create_count: (planned_creates | length),
      unexpected_creates: (planned_creates - expected_creates),
      missing_creates: (expected_creates - planned_creates)
    },
    resources: [
      .resource_changes[]
      | {
          address: .address,
          actions: .change.actions
        }
    ],
    controls: {
      gke: {
        kubernetes_version: $gke.min_master_version,
        private_nodes: $gke.private_cluster_config[0].enable_private_nodes,
        authorized_network_count: ($gke.master_authorized_networks_config[0].cidr_blocks | length),
        min_nodes: $gke_nodes.autoscaling[0].min_node_count,
        max_nodes: $gke_nodes.autoscaling[0].max_node_count
      },
      aks: {
        kubernetes_version: $aks.kubernetes_version,
        local_accounts_disabled: $aks.local_account_disabled,
        run_command_enabled: $aks.run_command_enabled,
        entra_rbac_enabled: $aks.azure_active_directory_role_based_access_control[0].azure_rbac_enabled,
        authorized_network_count: ($aks.api_server_access_profile[0].authorized_ip_ranges | length),
        min_nodes: $aks.default_node_pool[0].min_count,
        max_nodes: $aks.default_node_pool[0].max_count
      },
      traffic_manager: {
        routing_method: $traffic.traffic_routing_method,
        health_path: $traffic.monitor_config[0].path
      }
    }
  }
' "$plan_json"

jq -e '
  def after($address):
    [.resource_changes[] | select(.address == $address) | .change.after][0];

  def expected_creates: [
    "module.aks.azurerm_kubernetes_cluster.this",
    "module.aks.azurerm_public_ip.ingress",
    "module.aks.azurerm_resource_group.this",
    "module.aks.azurerm_role_assignment.network_contributor",
    "module.aks.azurerm_role_assignment.operator_cluster_admin",
    "module.aks.azurerm_subnet.aks",
    "module.aks.azurerm_user_assigned_identity.control_plane",
    "module.aks.azurerm_virtual_network.this",
    "module.gke.google_compute_address.ingress",
    "module.gke.google_compute_network.this",
    "module.gke.google_compute_router.this",
    "module.gke.google_compute_router_nat.this",
    "module.gke.google_compute_subnetwork.this",
    "module.gke.google_container_cluster.this",
    "module.gke.google_container_node_pool.primary",
    "module.gke.google_project_iam_member.node_roles[\"roles/artifactregistry.reader\"]",
    "module.gke.google_project_iam_member.node_roles[\"roles/logging.logWriter\"]",
    "module.gke.google_project_iam_member.node_roles[\"roles/monitoring.metricWriter\"]",
    "module.gke.google_project_iam_member.node_roles[\"roles/monitoring.viewer\"]",
    "module.gke.google_service_account.nodes",
    "module.traffic_manager.azurerm_traffic_manager_azure_endpoint.aks",
    "module.traffic_manager.azurerm_traffic_manager_external_endpoint.gke",
    "module.traffic_manager.azurerm_traffic_manager_profile.this",
    "random_string.dns_suffix"
  ];

  def planned_creates:
    [.resource_changes[] | select(.change.actions == ["create"]) | .address];

  (after("module.gke.google_container_cluster.this")) as $gke |
  (after("module.gke.google_container_node_pool.primary")) as $gke_nodes |
  (after("module.aks.azurerm_kubernetes_cluster.this")) as $aks |

  all(.resource_changes[]; .change.actions == ["create"] or .change.actions == ["read"] or .change.actions == ["no-op"])
  and ((planned_creates | sort) == (expected_creates | sort))
  and $gke.private_cluster_config[0].enable_private_nodes
  and (($gke.master_authorized_networks_config[0].cidr_blocks | length) == 1)
  and ($gke_nodes.autoscaling[0].max_node_count == 2)
  and $aks.local_account_disabled
  and ($aks.run_command_enabled == false)
  and $aks.azure_active_directory_role_based_access_control[0].azure_rbac_enabled
  and (($aks.api_server_access_profile[0].authorized_ip_ranges | length) == 1)
  and ($aks.default_node_pool[0].max_count == 2)
' "$plan_json" >/dev/null || {
  echo "BLOCKED: the Terraform plan failed a required safety assertion" >&2
  exit 1
}

echo "PASS: the Terraform plan satisfies the foundation safety assertions"
