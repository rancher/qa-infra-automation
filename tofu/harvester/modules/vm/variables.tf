variable "ssh_key" {
  description = "your public ssh key"
  type = string
}

variable "cloud_init" {
  description = "valid cloud-init that applies to each node. Default updates Ubuntu."
  default = <<-EOT
    #cloud-config
    package_update: true
    package_upgrade: true
    package_reboot_if_required: true
    packages:
      - qemu-guest-agent
    runcmd:
      - - systemctl
        - enable
        - --now
        - qemu-guest-agent.service
  EOT
}

variable "cpu" {
  description = "the desired cpu count"
  type = number
  default = 4
}

variable "mem" {
  description = "the desired memory amount"
  type = string
  default = "6Gi"
}

variable "disk_size" {
  description = "disk size"
  type = string 
  default = "30Gi"
}

variable "network_name" {
  description = "name of VM Network to use that's already up in your harvester ENV"
  type = string
  default = "harvester-public/vlan2011"
}

variable "image_id" {
  description = "ID of pre-downloaded image to use for VMs"
  type = string
  default = "harvester-public/noble-cloudimg-amd64"
}
variable "nodes" {
  description = "Configuration for RKE2 nodes."
  type = list(object({
    count = number
    role  = list(string)
  }))
}

variable "ssh_user" {
  description = "Username to ssh into VM"
  default = "ubuntu"
}
variable "machine_type" {
  description = "VM machine type"
  default = "q35"
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

variable "labels" {
  type        = map(string)
  description = "labels for each VM"
  default     = {}
}

// for LB
variable "create_loadbalancer" {
  type = bool
  description = "set to true if using an HA setup"
  default = false
}

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