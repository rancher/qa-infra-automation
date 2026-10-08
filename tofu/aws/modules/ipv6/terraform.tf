terraform {
  # >= 1.9 required for cross-variable references in validation blocks
  # (kube_api_host_ipv6/enable_public_ip validate against enable_ipv6).
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
