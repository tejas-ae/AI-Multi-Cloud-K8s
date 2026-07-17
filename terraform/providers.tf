provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "azurerm" {
  subscription_id = var.azure_subscription_id
  features {}
}
