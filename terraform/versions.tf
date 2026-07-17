terraform {
  required_version = ">= 1.15.8, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 7.40"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }
}
