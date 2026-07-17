output "gke_cluster_name" {
  value = module.gke.cluster_name
}

output "gke_location" {
  value = module.gke.location
}

output "gke_ingress_public_ip" {
  value = module.gke.ingress_public_ip
}

output "gke_credentials_command" {
  value = "gcloud container clusters get-credentials ${module.gke.cluster_name} --zone ${module.gke.location} --project ${var.gcp_project_id}"
}

output "aks_cluster_name" {
  value = module.aks.cluster_name
}

output "aks_resource_group_name" {
  value = module.aks.resource_group_name
}

output "aks_ingress_public_ip" {
  value = module.aks.ingress_public_ip
}

output "aks_ingress_public_fqdn" {
  value = module.aks.ingress_public_fqdn
}

output "aks_credentials_command" {
  value = "az aks get-credentials --resource-group ${module.aks.resource_group_name} --name ${module.aks.cluster_name} --overwrite-existing"
}

output "traffic_manager_fqdn" {
  value = module.traffic_manager.fqdn
}
