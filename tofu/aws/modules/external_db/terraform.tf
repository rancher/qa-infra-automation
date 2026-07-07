terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Match the cluster_nodes/qainfra stack (aws 3.x). aws_db_instance uses
      # `name` for the DB name in 3.x (`db_name` only exists in >= 4.0).
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}
