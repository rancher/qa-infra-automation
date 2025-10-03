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

variable "ippool_name" {
  description = "if an existing IP Pool should be used, specify its name here to avoid creating a new resource"
  default = null
  nullable = true
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


variable "lookup_label_key" {
  type = string
  description = "label that belongs to VMs which will be paired to this LB"
  default     = "rancher"
}

variable "lookup_label_values" {
  type =list(string)
  default = ["true"]
  description = "values for the label"
}

variable "ports" {
  type = list(number)
  description = "all ports to asociate with this LB. Defaults are for a rancher HA setup."
  default = [
    80,
    443,
    6443,
    9443,
    8472,
    22,
    2736,
    10250,
    9345,
    2379,
    2380,
    2381,
    2382,
    30000,
    30001,
    5473
  ]
}

variable "ipam" {
  description = "pool or dhcp. Typically set to pool in the lab"
  default = "pool"
}

variable "workload_type" {
  type = string
  description = "type of workloads targeted by the backend service"
  default = "vm"
}

variable "healthcheck_failure_threshold" {
  type = number
  description = "how many times a failed health check triggers unhealthy"
  default = 5
}
variable "healthcheck_success_threshold" {
  type = number
  description = "how many times a successful health check triggers healthy"
  default = 2
}
variable "healthcheck_heartbeat" {
  type = number
  description = "how often (in seconds) to check health"
  default = 15
}
variable "healthcheck_timeout" {
  type = number
  description = "timeout (in seconds) of given health check"
  default = 120
}

variable "create_new" {
  type = bool
  default = true
}