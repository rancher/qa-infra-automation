terraform {
  required_providers {
    harvester = {
      source  = "harvester/harvester"
      version = ">=1.6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">=2.37.1"
    }
    ansible = {
      source  = "ansible/ansible"
      version = ">= 1.3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">=4.0.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">=2.4.0"
    }
  }
}

locals {
  module_path        = abspath(path.module)
  codebase_root_path = abspath("${path.module}")

  # Trim local.codebase_root_path and one additional slash from local.module_path
  module_rel_path = substr(local.module_path, length(local.codebase_root_path) + 1, length(local.module_path))
}

provider "harvester" {
  # Configuration options
  kubeconfig = abspath("${local.codebase_root_path}/../local.yaml")
}

provider "kubernetes" {
  config_path = abspath("${local.codebase_root_path}/../local.yaml")
}
