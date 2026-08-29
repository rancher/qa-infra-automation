variable "kubernetes_version" {}

variable "is_network_policy" {
    default = false
    type    = bool
}
variable "psa" {
    default = "" # "rancher-privileged"
}
variable "machine_pools" {
  type = list(object({
    control_plane_role        = optional(bool, false)
    worker_role      = optional(bool, false)
    etcd_role     = optional(bool, false)
    quantity = optional(number, 1)
  }))
  default     = [{
    control_plane_role = true
    worker_role = true
    etcd_role = true
    quantity = 1
  }]
}

variable "create_new" {
  type        = bool
  default     = true
  nullable    = false
  description = "Flag defining if a new node template should be created on each tf apply. Useful for scripting purposes"
}

variable "generate_name" {
  type     = string
  default = "tf"
  nullable = false
}

variable "cloud_provider" {
  type     = string
  nullable = false
  validation {
    condition     = contains(["aws", "linode", "harvester"], var.cloud_provider)
    error_message = "Please pass in a case-sensitive string equal to one of the following: [\"aws\", \"linode\", \"harvester\"]."
  }
}

variable "node_config" {
  type        = any
  nullable    = false
  sensitive   = true
  description = "(Optional/Computed) Cloud provider-specific configuration object (object with optional attributes for those defined here https://registry.terraform.io/providers/rancher/rancher2/7.0.0/docs/resources/node_template#argument-reference)"

  validation {
    # Required for the ephemeral network and the amazonec2_config node driver.
    condition     = var.cloud_provider != "aws" || try(var.node_config.aws_region, null) != null
    error_message = "node_config.aws_region is required when cloud_provider = \"aws\"."
  }

  validation {
    condition     = var.cloud_provider != "aws" || try(var.node_config.aws_vpc, null) != null
    error_message = "node_config.aws_vpc is required when cloud_provider = \"aws\"."
  }

  validation {
    condition     = var.cloud_provider != "aws" || try(var.node_config.aws_subnet, null) != null
    error_message = "node_config.aws_subnet is required when cloud_provider = \"aws\"."
  }
}


variable "node_taints" {
  type = list(object({
    key        = optional(string, null)
    value      = optional(string, null)
    effect     = optional(string, null)
    time_added = optional(string, null)
  }))
  default     = []
  description = "Node taints. For Rancher v2.3.3 or above"
}

variable "machine_global_config" {
  type        = any
  default     = null
  description = "Global machine configuration as a map (e.g., {cni = \"calico\"}). Will be YAML-encoded for the rancher2_cluster_v2 resource."
}

variable "fleet_namespace" {
  type        = string
  default     = "fleet-default"
  description = "Cluster V2 fleet namespace"
}

variable "annotations" {
  type        = map(string)
  default     = null
  description = "Annotations for Node Template"
}

variable "labels" {
  type        = map(string)
  default     = null
  description = "Labels for Node Template"
}


variable "rancher_server_security_group_id" {
  description = "Security group ID attached to the Rancher server (e.g. the cluster_nodes module's ephemeral/ssh security group ID). The Rancher server uses this SG's outbound traffic to SSH into downstream nodes to provision them, so it's added as an SSH (22) ingress source on this module's ephemeral security group instead of opening SSH to 0.0.0.0/0. Required when node_config.aws_security_group is empty (i.e. the ephemeral SG is self-provisioned)."
  type        = string
  default     = null
}

variable "ephemeral_sg_ingress_cidrs" {
  description = "IPv4 CIDRs allowed SSH (22) and the LB listener ports (80, 443, 6443, 9345) on the self-provisioned ephemeral security group (aws only, used when node_config.aws_security_group is empty). Must not be 0.0.0.0/0/::/0 - use specific /32s or narrower CIDRs (jumpbox, bastion, office, VPC CIDR, etc.)."
  type        = list(string)
  validation {
    condition = alltrue([
      for c in var.ephemeral_sg_ingress_cidrs :
      c != "0.0.0.0/0" && c != "::/0"
    ])
    error_message = "ephemeral_sg_ingress_cidrs must not contain 0.0.0.0/0 or ::/0 (world-open ingress is not permitted). Use specific /32 or narrower CIDRs."
  }
}

variable "ephemeral_sg_egress_cidrs" {
  description = "IPv4 CIDRs allowed on egress from the self-provisioned ephemeral security group (aws only, used when node_config.aws_security_group is empty). Defaults to the VPC's own CIDR (node_config.aws_vpc). Must not be 0.0.0.0/0/::/0 - extend with additional specific CIDRs if nodes need broader outbound access (e.g. via a NAT gateway/proxy)."
  type        = list(string)
  default     = null
  validation {
    condition = var.ephemeral_sg_egress_cidrs == null || alltrue([
      for c in var.ephemeral_sg_egress_cidrs :
      c != "0.0.0.0/0" && c != "::/0"
    ])
    error_message = "ephemeral_sg_egress_cidrs must not contain 0.0.0.0/0 or ::/0 (world-open egress is not permitted). Use specific CIDRs."
  }
}


variable fqdn {}
variable api_key {}
variable insecure {
    default = true
    type    = bool
}