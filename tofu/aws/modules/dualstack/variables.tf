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
}
# variable "bastion_node" {
#   description = "The index of the node that will be used as a bastion host for SSH access to the cluster nodes."
#   type        = number
#   default     = 0
# }
variable "aws_bastion_subnet" {
  description = "The subnet ID where the bastion host will be created. This subnet should have routes in place for internet access."
  type        = string
  default     = ""
}
variable "key_name" {
  description = "The name of the SSH key pair to use for the bastion host."
  type        = string
  default     = ""
}

variable "no_of_bastion_nodes" {
  default = 0
}
variable "enable_public_ip" {
  description = "Set to true to enable public IPv4 addresses for the nodes. Set to false to disable public IP addresses."
  type    = bool
  default = true
}
variable "enable_ipv6" {
  description = "Set to true to enable IPv6 addresses for the nodes and bastion node. Set to false to disable IPv6 addresses."
  type    = bool
  default = false
}

variable "kube_api_host_ipv6" {
  description = "Set to true to use IPv6 address for kube_api_host. Set to false to use IPv4 address for kube_api_host."
  type    = bool
  default = false
}
