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
  description = "Optional list of pre-existing security group IDs to attach to every instance. When empty (the default) the module provisions its own ephemeral VPC/subnet/security group instead (created and destroyed alongside everything else)."
  type        = list(string)
  default     = []
  nullable    = false
}
variable "aws_vpc" {
  description = "Optional pre-existing VPC ID. When null (the default) the module provisions its own ephemeral VPC instead."
  type        = string
  default     = null
  nullable    = true
}
variable "aws_volume_size" {}
variable "aws_volume_type" {}
variable "aws_subnet" {
  description = "Optional pre-existing subnet ID. When null (the default) the module provisions its own ephemeral subnet instead."
  type        = string
  default     = null
  nullable    = true

  validation {
    # A supplied subnet must belong to a supplied VPC (mismatched VPCs fail at apply time,
    # since security groups/subnets/NLB target groups must all be in the same VPC).
    condition     = var.aws_subnet == null || var.aws_vpc != null
    error_message = "aws_vpc must be set when aws_subnet is set (the subnet's VPC must match the VPC used for security groups and NLB target groups)."
  }
}
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

variable "create_ssh_security_group" {
  description = "Create a dedicated SG that grants SSH (22) from stable CIDRs (ssh_allowed_cidrs) plus the VPC CIDR, and attach it alongside var.aws_security_group. Enable when SSH access is granted only via a managed prefix list - prefix-list rules propagate to each new ENI asynchronously and can silently drop SSH to a freshly launched node; plain CIDR rules realize instantly."
  type        = bool
  default     = false
}

variable "ssh_allowed_cidrs" {
  description = "Stable IPv4 CIDRs allowed SSH (22) when create_ssh_security_group=true. Use /32s for jumpboxes/bastions, e.g. [\"45.33.107.248/32\"]. VPC-internal SSH is allowed automatically in addition to these."
  type        = list(string)
  default     = []
  validation {
    # Reject world-open SSH. Scoped to the genuinely dangerous-but-valid case
    # (0.0.0.0/0, ::/0); narrower-but-broad CIDRs (office /16, /24) are
    # legitimate and left to the caller's judgement.
    condition = alltrue([
      for c in var.ssh_allowed_cidrs :
      c != "0.0.0.0/0" && c != "::/0"
    ])
    error_message = "ssh_allowed_cidrs must not contain 0.0.0.0/0 or ::/0 (world-open SSH is not permitted). Use specific /32 or narrower CIDRs."
  }
}

variable "ephemeral_ssh_cidrs" {
  description = "CIDR blocks allowed SSH (22) access to the ephemeral security group created when var.aws_security_group is empty. Defaults to no SSH ingress at all; the caller must opt in with specific CIDRs (e.g. [\"45.33.107.248/32\"])."
  type        = list(string)
  default     = []
  validation {
    # Reject world-open SSH, same policy as ssh_allowed_cidrs above.
    condition = alltrue([
      for c in var.ephemeral_ssh_cidrs :
      c != "0.0.0.0/0" && c != "::/0"
    ])
    error_message = "ephemeral_ssh_cidrs must not contain 0.0.0.0/0 or ::/0 (world-open SSH is not permitted). Use specific /32 or narrower CIDRs."
  }
}

variable "ephemeral_vpc_cidr" {
  description = "CIDR block for the self-provisioned ephemeral VPC, used only when var.aws_vpc is null."
  type        = string
  default     = "10.100.0.0/16"
}

variable "ephemeral_subnet_cidr" {
  description = "CIDR block for the self-provisioned ephemeral subnet, used only when var.aws_subnet is null."
  type        = string
  default     = "10.100.1.0/24"
}
