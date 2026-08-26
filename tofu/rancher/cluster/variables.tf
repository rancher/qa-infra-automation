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
    # A supplied subnet must belong to a supplied VPC (mismatched VPCs fail at apply time).
    condition     = var.cloud_provider != "aws" || try(var.node_config.aws_subnet, null) == null || try(var.node_config.aws_vpc, null) != null
    error_message = "node_config.aws_vpc must be set when node_config.aws_subnet is set (the subnet must belong to the VPC used by security groups and other resources)."
  }
}

variable "ephemeral_vpc_cidr" {
  type        = string
  default     = "10.101.0.0/16"
  description = "CIDR block for the ephemeral VPC created when cloud_provider=\"aws\" and node_config.aws_vpc/aws_subnet are omitted. Mirrors tofu/aws/modules/cluster_nodes's self-provisioning behavior."
}

variable "ephemeral_subnet_cidr" {
  type        = string
  default     = "10.101.1.0/24"
  description = "CIDR block for the ephemeral subnet created when cloud_provider=\"aws\" and node_config.aws_vpc/aws_subnet are omitted."
}

variable "ephemeral_ssh_cidrs" {
  type        = list(string)
  default     = []
  description = "CIDR blocks allowed SSH (22) access to the ephemeral security group created when cloud_provider=\"aws\" and node_config.aws_security_group is empty. Defaults to no SSH ingress at all; the caller must opt in with specific CIDRs (e.g. [\"45.33.107.248/32\"])."

  validation {
    # Reject world-open SSH, same policy as tofu/aws/modules/cluster_nodes's ssh_allowed_cidrs.
    condition = alltrue([
      for c in var.ephemeral_ssh_cidrs :
      c != "0.0.0.0/0" && c != "::/0"
    ])
    error_message = "ephemeral_ssh_cidrs must not contain 0.0.0.0/0 or ::/0 (world-open SSH is not permitted). Use specific /32 or narrower CIDRs."
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


variable fqdn {}
variable api_key {}
variable insecure {
    default = true
    type    = bool
}