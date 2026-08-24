terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Match the cluster_nodes/qainfra stack (aws 6.x). aws_db_instance takes
      # the DB name via `db_name` (`name` was removed in >= 6.0).
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}
