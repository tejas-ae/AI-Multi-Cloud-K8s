variable "resource_group_name" { type = string }
variable "dns_relative_name" { type = string }
variable "gke_ingress_ip" { type = string }
variable "aks_public_ip_id" { type = string }
variable "gke_weight" { type = number }
variable "aks_weight" { type = number }
variable "tags" { type = map(string) }
