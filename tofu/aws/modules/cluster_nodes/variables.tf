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
# Windows Instance Variables (RKE2 Agent only)
variable "aws_ami_windows" {
  description = "Optional specific Windows AMI ID."
  type        = string
  default     = null
}
variable "instance_type_windows" {
  default = null
}
variable "aws_volume_size_windows" {
  default = null
}
variable "aws_volume_type_windows" {
  default = null
}
variable "nodes" {
  description = "Configuration for product nodes."
  type = list(object({
    count         = number
    role          = list(string) # Allow multiple roles per node (e.g., ["etcd", "cp"], ["worker"])
    instance_type = optional(string) # Override global instance_type for this node group
    os            = optional(string, "linux") # Defaults to linux if omitted
  }))
  default = [
    { role = ["etcd", "cp"], count = 1, os = "linux" },
    { role = ["worker"], count = 1, os = "linux" }
  ]
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
