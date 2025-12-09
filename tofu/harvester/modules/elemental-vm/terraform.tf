terraform {
  required_version = ">= 0.13"
  required_providers {
    harvester = {
      source = "harvester/harvester"
      version = ">=1.6.0"
    }
  }
}

locals {
  module_path        = abspath(path.module)
  codebase_root_path = abspath("${path.module}")
}

provider "harvester" {
  kubeconfig = abspath("${local.codebase_root_path}/local.yaml")
}