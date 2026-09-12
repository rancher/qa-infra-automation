variable "security_group_name" {
  description = "Name (tag:Name/group-name) of the existing AWS security group to authorize/revoke rules on. Resolved to its ID via data.aws_security_group."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to scope the security_group_name lookup to. Recommended whenever the name isn't guaranteed unique account/region-wide."
  type        = string
  default     = null
}

variable "allowed_cidrs" {
  description = "List of bare IPv4 addresses (no /32 suffix) to grant temporary all-port ingress/egress access, e.g. a detected CI runner public IP"
  type        = list(string)
  default     = []
}

variable "description" {
  description = "Optional description applied to the created security group rules"
  type        = string
  default     = null
}
