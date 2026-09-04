variable "security_group_id" {
  description = "ID of the existing AWS security group to authorize/revoke rules on"
  type        = string
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
