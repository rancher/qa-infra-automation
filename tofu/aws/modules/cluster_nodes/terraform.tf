terraform {
  # >= 1.9 required for cross-variable references in validation blocks
  # (ephemeral_sg_ingress_cidrs validates against var.aws_security_group).
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
}
}
