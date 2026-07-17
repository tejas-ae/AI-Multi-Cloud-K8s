data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "ai-multicloud-k8s-aks-vnet"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = ["10.40.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "aks" {
  name                 = "aks-nodes"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.40.0.0/20"]
}

resource "azurerm_user_assigned_identity" "control_plane" {
  name                = "ai-multicloud-k8s-aks-control-plane"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_role_assignment" "network_contributor" {
  scope                            = azurerm_subnet.aks.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  node_resource_group = "${var.resource_group_name}-nodes"
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  sku_tier            = "Free"
  support_plan        = "KubernetesOfficial"

  role_based_access_control_enabled = true
  local_account_disabled            = true
  oidc_issuer_enabled               = true
  run_command_enabled               = false
  workload_identity_enabled         = true

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = data.azurerm_client_config.current.tenant_id
  }

  api_server_access_profile {
    authorized_ip_ranges = [var.admin_cidr]
  }

  default_node_pool {
    name                         = "system"
    vm_size                      = var.node_vm_size
    orchestrator_version         = var.kubernetes_version
    vnet_subnet_id               = azurerm_subnet.aks.id
    auto_scaling_enabled         = true
    node_count                   = var.min_nodes
    min_count                    = var.min_nodes
    max_count                    = var.max_nodes
    max_pods                     = 50
    os_disk_size_gb              = 64
    os_disk_type                 = "Managed"
    type                         = "VirtualMachineScaleSets"
    only_critical_addons_enabled = false

    upgrade_settings {
      max_surge = "33%"
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.control_plane.id]
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "cilium"
    network_data_plane  = "cilium"
    pod_cidr            = "10.50.0.0/16"
    service_cidr        = "10.60.0.0/16"
    dns_service_ip      = "10.60.0.10"
    outbound_type       = "loadBalancer"
    load_balancer_sku   = "standard"
  }

  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [default_node_pool[0].node_count]
  }

  depends_on = [azurerm_role_assignment.network_contributor]
}

resource "azurerm_role_assignment" "operator_cluster_admin" {
  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_public_ip" "ingress" {
  name                = "ai-multicloud-k8s-aks-ingress"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_kubernetes_cluster.this.node_resource_group
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "ai-multicloud-k8s-aks-${var.dns_suffix}"
  tags                = var.tags
}
