locals {
  project_name = "ai-multicloud-k8s"

  tags = {
    project     = local.project_name
    environment = "portfolio"
    managed_by  = "terraform"
  }

  labels = {
    project     = local.project_name
    environment = "portfolio"
    managed_by  = "terraform"
  }
}
