resource "azurerm_traffic_manager_profile" "this" {
  name                   = "ai-multicloud-k8s"
  resource_group_name    = var.resource_group_name
  traffic_routing_method = "Weighted"

  dns_config {
    relative_name = var.dns_relative_name
    ttl           = 30
  }

  monitor_config {
    protocol                     = "HTTP"
    port                         = 80
    path                         = "/healthz"
    interval_in_seconds          = 30
    timeout_in_seconds           = 10
    tolerated_number_of_failures = 3
  }

  tags = var.tags
}

resource "azurerm_traffic_manager_external_endpoint" "gke" {
  name       = "gke"
  profile_id = azurerm_traffic_manager_profile.this.id
  target     = "${replace(var.gke_ingress_ip, ".", "-")}.nip.io"
  weight     = var.gke_weight
  enabled    = true
}

resource "azurerm_traffic_manager_azure_endpoint" "aks" {
  name               = "aks"
  profile_id         = azurerm_traffic_manager_profile.this.id
  target_resource_id = var.aks_public_ip_id
  weight             = var.aks_weight
  enabled            = true
}
