resource "random_string" "dns_suffix" {
  length  = 6
  upper   = false
  special = false
}

module "gke" {
  source = "./modules/gke"

  project_id         = var.gcp_project_id
  region             = var.gcp_region
  zone               = var.gcp_zone
  cluster_name       = var.gke_cluster_name
  node_machine_type  = var.gke_node_machine_type
  kubernetes_version = var.gke_kubernetes_version
  min_nodes          = var.gke_min_nodes
  max_nodes          = var.gke_max_nodes
  admin_cidr         = var.admin_cidr
  labels             = local.labels
}

module "aks" {
  source = "./modules/aks"

  subscription_id     = var.azure_subscription_id
  location            = var.azure_location
  resource_group_name = var.azure_resource_group_name
  cluster_name        = var.aks_cluster_name
  node_vm_size        = var.aks_node_vm_size
  kubernetes_version  = var.aks_kubernetes_version
  min_nodes           = var.aks_min_nodes
  max_nodes           = var.aks_max_nodes
  admin_cidr          = var.admin_cidr
  dns_suffix          = random_string.dns_suffix.result
  tags                = local.tags
}

module "traffic_manager" {
  source = "./modules/traffic-manager"

  resource_group_name = module.aks.resource_group_name
  dns_relative_name   = "ai-multicloud-k8s-${random_string.dns_suffix.result}"
  gke_ingress_ip      = module.gke.ingress_public_ip
  aks_public_ip_id    = module.aks.ingress_public_ip_id
  gke_weight          = var.traffic_weight_gke
  aks_weight          = var.traffic_weight_aks
  tags                = local.tags
}
