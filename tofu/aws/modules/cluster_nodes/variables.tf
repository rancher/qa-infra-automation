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
  description = "Optional list of pre-existing security group IDs to attach to every instance. When empty (the default) the module provisions its own ephemeral security group instead (created and destroyed alongside everything else)."
  type        = list(string)
  default     = []
}
variable "aws_vpc" {
  description = "Pre-existing VPC ID to use for all resources."
  type        = string
}
variable "aws_volume_size" {}
variable "aws_volume_type" {}
variable "aws_subnet" {
  description = "Pre-existing subnet ID to use for all instances."
  type        = string
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

variable "ephemeral_sg_ingress_cidrs" {
  description = "IPv4 CIDRs allowed SSH (22) and the RKE2/Rancher NLB listener ports (80, 443, 6443, 9345) on the self-provisioned ephemeral security group (used only when var.aws_security_group is empty). Must not be 0.0.0.0/0/::/0 - use specific /32s or narrower CIDRs (jumpbox, bastion, office, VPC CIDR, etc.)."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.aws_security_group) > 0 || length(var.ephemeral_sg_ingress_cidrs) > 0
    error_message = "ephemeral_sg_ingress_cidrs must be set when aws_security_group is empty (so the module can open SSH/NLB ports)."
  }

  validation {
    condition = alltrue([
      for c in var.ephemeral_sg_ingress_cidrs :
      c != "0.0.0.0/0" && c != "::/0"
    ])
    error_message = "ephemeral_sg_ingress_cidrs must not contain 0.0.0.0/0 or ::/0 (world-open ingress is not permitted). Use specific /32 or narrower CIDRs."
  }
}

variable "ephemeral_sg_egress_cidrs" {
  description = "IPv4 CIDRs allowed on egress from the self-provisioned ephemeral security group (used only when var.aws_security_group is empty). Defaults to the selected VPC's CIDR block (looked up from var.aws_vpc). Must not be 0.0.0.0/0/::/0 - extend with additional specific CIDRs if nodes need broader outbound access (e.g. via a NAT gateway/proxy)."
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
