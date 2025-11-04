variable "user_id" {}
variable "ssh_key" {}
variable "ssh_key_name" {}
variable "aws_access_key" {
  type       = string
  sensitive  = true
}
variable "aws_secret_key" {
  type      = string
  sensitive = true
}
variable "aws_region" {}
variable "aws_ami" {}
variable "aws_hostname_prefix" {}
variable "aws_route53_zone" {}
variable "aws_ssh_user" {}
variable "aws_security_group" { type = list(string) }
variable "aws_vpc" {}
variable "aws_volume_size" {}
variable "aws_subnet" {}
variable "instance_type" {}
variable "provision_registry" {
  description = "Set to false to not provision a registry instance."
  type        = bool
  default     = true
}
variable "node_groups" {
  description = "Map of how many nodes per group. Keyed by name of group. Group names are used for inventory file. Group of nodes for rancher should be named 'rancher'"
  type        = map(number)
  default = {
    "rancher" = 3
  }
  validation {
    condition     = !anytrue([for name in keys(var.node_groups) : startswith(name, "rancher-")])
    error_message = "node_groups must not contain keys starting with 'rancher-'"
  }

  validation {
    condition     = !anytrue([for size in values(var.node_groups) : size <= 0])
    error_message = "A group must have at least one node"
  }
}
