terraform {
  required_version = ">= 0.13"
  required_providers {
    harvester = {
      source = "harvester/harvester"
      version = ">=1.6.0"
    }
  }
}

provider "harvester" {
  kubeconfig = var.kubeconfig
}