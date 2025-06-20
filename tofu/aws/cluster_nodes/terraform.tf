terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
    ansible = {
      source  = "ansible/ansible"
      version = "1.3.0"
    }
  }
}