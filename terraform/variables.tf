variable "gcp_project_id" {
  description = "GCP project that owns the GKE platform."
  type        = string
}

variable "gcp_region" {
  description = "GCP region for networking and public addresses."
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "GCP zone for the GKE cluster."
  type        = string
  default     = "us-central1-a"
}

variable "gke_cluster_name" {
  description = "GKE cluster name."
  type        = string
  default     = "ai-multicloud-k8s-gke"
}

variable "gke_node_machine_type" {
  description = "GKE worker machine type."
  type        = string
  default     = "e2-standard-4"
}

variable "gke_kubernetes_version" {
  description = "Exact GKE patch version selected from the Regular release channel."
  type        = string
}

variable "gke_min_nodes" {
  description = "Minimum GKE worker count."
  type        = number
  default     = 2
}

variable "gke_max_nodes" {
  description = "Maximum GKE worker count."
  type        = number
  default     = 2
}

variable "azure_subscription_id" {
  description = "Azure subscription that owns the AKS platform."
  type        = string
}

variable "azure_location" {
  description = "Azure region for AKS and Traffic Manager resources."
  type        = string
  default     = "eastus"
}

variable "azure_resource_group_name" {
  description = "Azure resource group for platform resources."
  type        = string
  default     = "ai-multicloud-k8s-prod"
}

variable "aks_cluster_name" {
  description = "AKS cluster name."
  type        = string
  default     = "ai-multicloud-k8s-aks"
}

variable "aks_node_vm_size" {
  description = "AKS worker VM size."
  type        = string
  default     = "Standard_D4s_v3"
}

variable "aks_kubernetes_version" {
  description = "Exact AKS patch version available in the selected Azure region."
  type        = string
}

variable "aks_min_nodes" {
  description = "Minimum AKS worker count."
  type        = number
  default     = 2
}

variable "aks_max_nodes" {
  description = "Maximum AKS worker count."
  type        = number
  default     = 2
}

variable "admin_cidr" {
  description = "Single public operator IPv4 address allowed to reach both Kubernetes API servers."
  type        = string

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/32$", var.admin_cidr)) && can(cidrnetmask(var.admin_cidr))
    error_message = "admin_cidr must be a valid IPv4 /32 CIDR."
  }
}

variable "traffic_weight_gke" {
  description = "Initial public traffic weight for GKE."
  type        = number
  default     = 50
}

variable "traffic_weight_aks" {
  description = "Initial public traffic weight for AKS."
  type        = number
  default     = 50
}
