variable "public_ssh_key" {} // The corrals public key.  This should be installed on every node.
variable "aws_access_key" {
  type    = string
  default = null // Optional. When null the AWS provider uses its standard credential chain (~/.aws/credentials, AWS_PROFILE, env vars, SSO, IMDS).
}
variable "aws_secret_key" {
  type    = string
  default = null // Optional. See aws_access_key.
}
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
    role          = list(string)     # Allow multiple roles per node (e.g., ["etcd", "cp"], ["worker"])
    instance_type = optional(string) # Override global instance_type for this node group
  }))
  validation {
    # Need >=1 cp node (count>0). Without it first_master_index = -1 → cryptic plan error.
    condition     = anytrue([for ng in var.nodes : ng.count > 0 && contains(ng.role, "cp")])
    error_message = "At least one node group must include the \"cp\" role with count > 0. K3s/RKE2 clusters need a real control-plane node."
  }
}
variable "aws_bastion_subnet" {
  description = "The subnet ID where the bastion host will be created. This subnet should have routes in place for internet access."
  type        = string
  default     = ""

  validation {
    condition     = var.no_of_bastion_nodes == 0 || length(var.aws_bastion_subnet) > 0
    error_message = "aws_bastion_subnet must be set when no_of_bastion_nodes > 0."
  }
}
variable "key_name" {
  description = "The name of the SSH key pair to use for the bastion host."
  type        = string
  default     = ""
}

variable "no_of_bastion_nodes" {
  description = "Number of bastion hosts to create. Only 0 or 1 is supported; 1 is required when the cluster nodes have no public IPv4."
  type        = number
  default     = 0

  validation {
    condition     = contains([0, 1], var.no_of_bastion_nodes)
    error_message = "no_of_bastion_nodes must be 0 or 1."
  }
}

variable "enable_public_ip" {
  description = "Set to true to enable public IPv4 addresses for the nodes. Set to false to disable public IP addresses."
  type        = bool
  default     = true

  validation {
    condition     = var.enable_public_ip || var.enable_ipv6
    error_message = "enable_ipv6 must be true when enable_public_ip is false, otherwise the nodes have no reachable address."
  }
}
variable "enable_ipv6" {
  description = "Set to true to enable IPv6 addresses for the nodes and bastion node. Set to false to disable IPv6 addresses."
  type        = bool
  default     = false
}

variable "kube_api_host_ipv6" {
  description = "Set to true to use IPv6 address for kube_api_host. Set to false to use IPv4 address for kube_api_host."
  type        = bool
  default     = false

  validation {
    condition     = !var.kube_api_host_ipv6 || var.enable_ipv6
    error_message = "kube_api_host_ipv6 requires enable_ipv6 = true; there is no IPv6 address to publish otherwise."
  }
}

variable "ipv6_manage_dns" {
  description = "On IPv6-only nodes (enable_public_ip = false), replace /etc/resolv.conf with ipv6_dns64_resolvers and stop systemd-resolved. Set to false to leave the image's existing DNS configuration untouched - use this when the VPC already provides DNS64 or the AMI manages its own resolver."
  type        = bool
  default     = true
}

variable "ipv6_dns64_resolvers" {
  description = "DNS64 resolver(s) for IPv6-only nodes. Defaults to the public nat64.net service; override with a VPC DNS64 resolver where available. Ignored when ipv6_manage_dns = false."
  type        = list(string)
  default     = ["2a00:1098:2c::1"]
}
