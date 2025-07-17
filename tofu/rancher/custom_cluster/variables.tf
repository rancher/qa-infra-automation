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

variable "generate_name" {
  type     = string
  default = "tf"
  nullable = false
}

variable fqdn {}
variable api_key {}
variable insecure {
    default = true
    type    = bool
}