# vSphere connection variables
variable "vsphere_user" {}
variable "vsphere_password" {
  sensitive   = true
}
variable "vsphere_server" {}
variable "vsphere_datacenter" {}
variable "vsphere_datastore" {}
variable "vsphere_cluster" {}
variable "vsphere_network" {}
variable "vsphere_folder" {}
variable "vm_template" {}
variable "vm_num_cpus" {}
variable "vm_memory" {}
variable "vm_disk_label" {}
variable "vm_disk_size" {}
variable "vm_domain" {}

# Network configuration
variable "vm_ipv4_gateway" {}
variable "vm_ipv4_netmask" {}
variable "vm_dns_servers" {}

# SSH configuration
variable "vm_ssh_user" {}
variable "ssh_private_key_path" {}
variable "public_ssh_key" {}

# Cluster configuration
variable "user_id" {}
variable "nodes" {
  type = list(object({
    count = number
    role  = list(string)
  }))
}
variable "airgap_setup" {
  description = "Enable airgap setup with bastion and registry"
  type        = bool
  default     = false
}

variable "proxy_setup" {
  description = "Enable proxy setup"
  type        = bool
  default     = false
}

# Load Balancer Configuration
variable "enable_load_balancer" {
  description = "Enable load balancer for cluster API"
  type        = bool
  default     = false
}

variable "load_balancer_type" {
  description = "Type of load balancer to deploy"
  type        = string
  default     = "haproxy"
  validation {
    condition     = contains(["haproxy", "nginx", "nsxt"], var.load_balancer_type)
    error_message = "Load balancer type must be one of: haproxy, nginx, nsxt."
  }
}

variable "load_balancer_ipv4_address" {
  description = "Static IPv4 address for load balancer VM"
  type        = string
  default     = ""
}

variable "load_balancer_ports" {
  description = "Ports to expose on the load balancer"
  type        = list(number)
  default     = [80, 443, 6443, 9345]
}

# Airgap Infrastructure Configuration
variable "bastion_ipv4_address" {
  description = "Static IPv4 address for bastion VM (required if airgap_setup is true)"
  type        = string
  default     = ""
}

variable "registry_ipv4_address" {
  description = "Static IPv4 address for registry VM (required if airgap_setup is true)"
  type        = string
  default     = ""
}

variable "bastion_vm_num_cpus" {
  description = "Number of CPUs for bastion VM"
  type        = number
  default     = 2
}

variable "bastion_vm_memory" {
  description = "Memory in MB for bastion VM"
  type        = number
  default     = 4096
}

variable "bastion_vm_disk_size" {
  description = "Disk size in GB for bastion VM"
  type        = number
  default     = 50
}

variable "registry_vm_num_cpus" {
  description = "Number of CPUs for registry VM"
  type        = number
  default     = 4
}

variable "registry_vm_memory" {
  description = "Memory in MB for registry VM"
  type        = number
  default     = 8192
}

variable "registry_vm_disk_size" {
  description = "Disk size in GB for registry VM"
  type        = number
  default     = 100
}

variable "registry_ports" {
  description = "Ports to expose on the registry"
  type        = list(number)
  default     = [80, 443, 5000]
}

# Additional tags for resources
variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
