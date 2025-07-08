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