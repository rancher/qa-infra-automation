# External datastore (kine → RDS) module variables.
# Mirrors the legacy distros-test-framework external-db provisioning so K3s/RKE2
# clusters can run with an external datastore instead of embedded etcd.

variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "aws_region" {}

variable "resource_name" {
  description = "Prefix used for the DB identifier and tags."
  type        = string
}

variable "external_db" {
  description = "RDS engine: postgres | mysql | mariadb | aurora-mysql."
  type        = string
  validation {
    condition     = contains(["postgres", "mysql", "mariadb", "aurora-mysql"], lower(var.external_db))
    error_message = "external_db must be one of: postgres, mysql, mariadb, aurora-mysql."
  }
}

variable "external_db_version" {
  description = "Engine version (e.g. 16.3 for postgres, 10.11.9 for mariadb)."
  type        = string
  default     = ""
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.medium"
}

variable "db_group_name" {
  description = "DB parameter group name (e.g. default.postgres16)."
  type        = string
  default     = ""
}

variable "db_username" {
  type    = string
  default = "adminuser"
}

variable "db_password" {
  description = "Master password for the DB (required; no default so callers must pass a secret)."
  type        = string
  sensitive   = true
}

variable "db_name" {
  type    = string
  default = "mydb"
}

variable "engine_mode" {
  description = "Aurora engine mode (provisioned | serverless)."
  type        = string
  default     = "provisioned"
}

variable "availability_zone" {
  type    = string
  default = ""
}

variable "aws_security_group" {
  description = "Cluster nodes' security group IDs; the DB port is opened from these."
  type        = list(string)
  default     = []
}

variable "aws_vpc" {
  description = "VPC ID in which to create the dedicated RDS security group. Empty falls back to attaching aws_security_group directly."
  type        = string
  default     = ""
}

variable "db_subnet_ids" {
  description = "Subnet IDs for the DB subnet group. RDS needs >=2 AZs; empty uses the account default."
  type        = list(string)
  default     = []
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "environment" {
  type    = string
  default = "qa"
}
