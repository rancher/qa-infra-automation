variable "create_new" {
  type        = bool
  default     = true
  description = "Flag defining if a new rancher2_cloud_credential should be created on each tf apply. Useful for scripting purposes"
}

variable "name" {
  type        = string
  description = "Display name of the rancher2_cloud_credential"
  nullable    = false
}

variable "cloud_provider" {
  type        = string
  description = "A string defining which cloud provider to dynamically create a rancher2_cloud_credential for"
  nullable    = false
  validation {
    condition     = contains(["aws", "linode", "harvester"], var.cloud_provider)
    error_message = "Please pass in a case-sensitive string equal to one of the following: [\"aws\", \"linode\", \"harvester\"]."
  }
}

variable "node_config" {
  type = object({
    aws_access_key         = optional(string)             # for amazonec2_credential_config
    aws_secret_key         = optional(string)             # for amazonec2_credential_config
    aws_region             = optional(string)             # for amazonec2_credential_config
    linode_token              = optional(string)             # for linode_credential_config
    harvester_cluster_v1_id      = optional(string)             # for harvester_credential_config
    harvester_cluster_type       = optional(string, "imported") # for harvester_credential_config
    harvester_kubeconfig_content = optional(string)             # for harvester_credential_config
  })
  description = "An object containing your cloud provider's specific rancher2_cloud_credential config fields in order to dynamically map to them"
  nullable    = false
  sensitive   = true
}

variable fqdn {}
variable api_key {}
variable insecure {
    default = true
    type    = bool
}