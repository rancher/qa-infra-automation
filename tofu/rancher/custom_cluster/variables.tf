variable "kubernetes_version" {
  description = "desired, valid k8s version. Should be available in the rancher setup."
}

variable "is_network_policy" {
  description = "boolean, whether or not to set network policy"
  default = false
  type    = bool
}
variable "psa" {
  description = "valid PSA. Should already be available in rancher setup."
  default = "" # "rancher-privileged"
}

variable "generate_name" {
  description = "short name to append to created resources"
  type     = string
  default = "tf"
  nullable = false
}

variable fqdn {
  description = "https://your-rancher-setup"
}
variable api_key {
  description = "valid api key from your rancher setup."
}
variable insecure {
  description = "use insecure if your TLS certs aren't officially signed."
  default = true
  type    = bool
}