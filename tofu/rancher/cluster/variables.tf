variable "kubernetes_version" {}

variable "is_network_policy" {
    default = false
    type    = bool
}
variable "psa" {
    default = "" # "rancher-privileged"
}
variable "machine_pool_set" {
  description = "Choose a machine pool set (i.e. ha)"
  type        = string
  default     = "single"
}

# variable "machine_kind" {
#   description = "typically populated from the rancher/machine scripts"
#   type        = string
# }

# variable "machine_name" {
#   description = "typically populated from the rancher/machine scripts"
#   type        = string
# }
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
  default = "ctw"
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