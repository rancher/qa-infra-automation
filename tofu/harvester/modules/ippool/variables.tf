variable "subnet_cidr" {
  description = "the desired CIDR/subnet i.e. 10.10.0.0/26"
  type = string
  default = null
}


variable "backend_network_name" {
  description = "name of VM Network to use that's already up in your harvester ENV. Should exclude namespace"
  type = string
  default = null
}

variable "gateway_ip" {
  description = "gateway IP address"
  default = null
}

variable "range_ip_start" {
  description = "starting IP (included) of the pool range"
  default = null
}

variable "range_ip_end" {
  description = "end IP (included) of the pool range"
  default = null
}


variable "namespace" {
  description = "namespace in harvester to deploy resources"
  default = "default"
}

variable "generate_name" {
  description = "short name to append to created resources"
  type     = string
  default = "tf"
  nullable = false
}

variable "create_new" {
  type = bool
  default = true
  description = "whether to create a new pool or lookup an existing one."
}