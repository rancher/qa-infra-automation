variable "ssh_key" {
  description = "your public ssh key"
  type = string
}

variable "cloud_init" {
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
  default = "20Gi"
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
  type     = string
  default = "tf"
  nullable = false
}
