variable "public_ssh_key" {} // The corrals public key.  This should be installed on every node.
variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "aws_region" {}
variable "aws_ami" {}
variable "aws_hostname_prefix" {}
variable "aws_route53_zone" {}
variable "aws_ssh_user" {}
variable "private_ssh_key" {
  description = "Absolute path to the SSH private key file used to connect to cluster nodes."
  type        = string
  default     = ""
}
variable "aws_security_group" {
  type = list(string)
}
variable "aws_vpc" {}
variable "aws_volume_size" {}
variable "aws_volume_type" {}
variable "aws_subnet" {}
variable "instance_type" {}
variable "nodes" {
  description = "Configuration for product nodes."
  type = list(object({
    count         = number
    role          = list(string) # Allow multiple roles per node (e.g., ["etcd", "cp"], ["worker"])
    instance_type = optional(string) # Override global instance_type for this node group
  }))
  validation {
    # Need >=1 cp node (count>0). Without it first_master_index = -1 → cryptic plan error.
    condition     = anytrue([for ng in var.nodes : ng.count > 0 && contains(ng.role, "cp")])
    error_message = "At least one node group must include the \"cp\" role with count > 0. K3s/RKE2 clusters need a real control-plane node."
  }
}
variable "airgap_setup" {}
variable "proxy_setup" {}
