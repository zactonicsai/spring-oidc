terraform {
  required_version = ">= 1.10"
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # 5.x is current (GA July 2026). Everything used here also exists in 4.40+.
      version = ">= 4.40, < 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}
