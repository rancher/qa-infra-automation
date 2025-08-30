# vSphere Infrastructure Variables
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

# VM Configuration Variables
variable "vm_name" {
  description = "VM name"
  type        = string
}

variable "vm_template" {
  description = "VM template name"
  type        = string
}

variable "vm_num_cpus" {
  description = "Number of CPUs for the VM"
  type        = number
  default     = 2
}

variable "vm_memory" {
  description = "Memory in MB for the VM"
  type        = number  
  default     = 4096
}

variable "vm_disk_label" {
  description = "Disk label for the VM"
  type        = string
  default     = "disk0"
}

variable "vm_disk_size" {
  description = "Disk size in GB for the VM"
  type        = number
  default     = 50
}

variable "vm_domain" {
  description = "Domain name for the VM"
  type        = string
  default     = "local"
}

# Network Configuration
variable "vm_ipv4_address" {
  description = "Static IPv4 address for the VM (optional)"
  type        = string
  default     = ""
}

variable "vm_ipv4_netmask" {
  description = "IPv4 netmask for the VM"
  type        = string
  default     = "24"
}

variable "vm_ipv4_gateway" {
  description = "IPv4 gateway for the VM"
  type        = string
}

variable "vm_dns_servers" {
  description = "DNS servers for the VM"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

# SSH Configuration
variable "vm_ssh_user" {
  description = "SSH user for the VM"
  type        = string
  default     = "root"
}

# Tags
variable "tags" {
  description = "Tags to apply to the VM"
  type        = map(string)
  default     = {}
}
