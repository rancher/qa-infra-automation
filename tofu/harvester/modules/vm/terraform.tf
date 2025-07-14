terraform {
  required_providers {
    harvester = {
      source = "harvester/harvester"
      version = "0.6.7"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      version = "2.37.1"
    }
  }
}

locals {
  module_path        = abspath(path.module)
  codebase_root_path = abspath("${path.module}")

  # Trim local.codebase_root_path and one additional slash from local.module_path
  module_rel_path    = substr(local.module_path, length(local.codebase_root_path)+1, length(local.module_path))
}

provider "harvester" {
  # Configuration options
  kubeconfig = abspath("${local.codebase_root_path}/local.yaml")
}

provider "kubernetes" {
  config_path = abspath("${local.codebase_root_path}/local.yaml")
}