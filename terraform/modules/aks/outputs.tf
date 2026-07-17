output "cluster_name" { value = azurerm_kubernetes_cluster.this.name }
output "resource_group_name" { value = azurerm_resource_group.this.name }
output "node_resource_group_name" { value = azurerm_kubernetes_cluster.this.node_resource_group }
output "ingress_public_ip" { value = azurerm_public_ip.ingress.ip_address }
output "ingress_public_ip_id" { value = azurerm_public_ip.ingress.id }
output "ingress_public_fqdn" { value = azurerm_public_ip.ingress.fqdn }
output "oidc_issuer_url" { value = azurerm_kubernetes_cluster.this.oidc_issuer_url }
