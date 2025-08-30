# Load Balancer Configuration
variable "name" {
  description = "Name for the load balancer"
  type        = string
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

# vSphere Infrastructure Variables (for VM-based load balancers)
variable "vsphere_datacenter" {
  description = "vSphere datacenter name"
  type        = string
}

variable "vsphere_datastore" {
  description = "vSphere datastore name"  
  type        = string
}

variable "vsphere_cluster" {
  description = "vSphere compute cluster name"
  type        = string
}

variable "vsphere_network" {
  description = "vSphere network name"
  type        = string
}

variable "vsphere_folder" {
  description = "vSphere VM folder path"
  type        = string
  default     = ""
}

# VM Configuration (for VM-based load balancers)
variable "vm_template" {
  description = "VM template name for load balancer VM"
  type        = string
}

variable "vm_num_cpus" {
  description = "Number of CPUs for the load balancer VM"
  type        = number
  default     = 2
}

variable "vm_memory" {
  description = "Memory in MB for the load balancer VM"
  type        = number
  default     = 4096
}

variable "vm_disk_size" {
  description = "Disk size in GB for the load balancer VM"
  type        = number
  default     = 50
}

# Network Configuration
variable "vm_ipv4_address" {
  description = "Static IPv4 address for the load balancer VM"
  type        = string
}

variable "vm_ipv4_netmask" {
  description = "IPv4 netmask for the load balancer VM"
  type        = string
  default     = "24"
}

variable "vm_ipv4_gateway" {
  description = "IPv4 gateway for the load balancer VM"
  type        = string
}

variable "vm_dns_servers" {
  description = "DNS servers for the load balancer VM"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

# Load Balancer Backend Configuration
variable "backend_servers" {
  description = "List of backend servers to load balance"
  type = list(object({
    ip   = string
    port = number
  }))
}

variable "frontend_ports" {
  description = "List of frontend ports to expose"
  type        = list(number)
  default     = [80, 443, 6443, 9345]
}

variable "health_check_path" {
  description = "Health check path for HTTP backends"
  type        = string
  default     = "/ping"
}

# NSX-T Configuration (for NSX-T load balancer)
variable "nsxt_manager_host" {
  description = "NSX-T Manager hostname/IP"
  type        = string
  default     = ""
}

variable "nsxt_username" {
  description = "NSX-T username"
  type        = string
  default     = ""
}

variable "nsxt_password" {
  description = "NSX-T password"
  type        = string
  default     = ""
  sensitive   = true
}

variable "nsxt_edge_cluster_path" {
  description = "NSX-T Edge Cluster path"
  type        = string
  default     = ""
}

# Tags
variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
