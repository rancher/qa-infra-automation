terraform {
  required_version = ">= 1.8.2"
  required_providers {
    rancher2 = {
      source  = "rancher/rancher2"
      version = ">= 14.0.0"
    }
  }
}
