 
# Random ID for unique resource naming
resource "random_id" "cluster_id" {
  byte_length = 6
}

# Local values for resource naming
locals {
  resource_prefix = "${var.user_id}-${random_id.cluster_id.hex}"
  common_tags = merge(
    var.additional_tags,
    {
      "distros-qa" = "true"
      "cluster_id" = random_id.cluster_id.hex
      "user_id"    = var.user_id
    }
  )
}

# Create VMs for each node configuration using the VM module
module "node_vm" {
  source = "../vm"
  
  for_each = local.node_map

  # vSphere Infrastructure
  vsphere_datacenter = var.vsphere_datacenter
  vsphere_datastore  = var.vsphere_datastore
  vsphere_cluster    = var.vsphere_cluster
  vsphere_network    = var.vsphere_network
  vsphere_folder     = var.vsphere_folder

  # VM Configuration
  vm_name      = "${local.resource_prefix}-${each.key}"
  vm_template  = var.vm_template
  vm_num_cpus  = var.vm_num_cpus
  vm_memory    = var.vm_memory
  vm_disk_label = var.vm_disk_label
  vm_disk_size = var.vm_disk_size
  vm_domain    = var.vm_domain

  # Network Configuration
  vm_ipv4_address = each.value.static_ip != "" ? each.value.static_ip : ""
  vm_ipv4_netmask = var.vm_ipv4_netmask
  vm_ipv4_gateway = var.vm_ipv4_gateway
  vm_dns_servers  = var.vm_dns_servers

  # SSH Configuration
  vm_ssh_user = var.vm_ssh_user

  # Tags
  tags = local.common_tags
}

# Local node mapping based on nodes variable
locals {
  node_map = {
    for i, node_config in var.nodes : 
    "${node_config.role[0] == "etcd" || contains(node_config.role, "cp") || contains(node_config.role, "controlplane") ? "master" : "worker"}-${i}" => {
      role      = node_config.role
      static_ip = try(node_config.static_ip, "")
      is_server = node_config.role[0] == "etcd" || contains(node_config.role, "cp") || contains(node_config.role, "controlplane")
    }
  }
}

# Bastion VM for airgap environments
module "bastion" {
  count  = var.airgap_setup ? 1 : 0
  source = "../vm"

  # vSphere Infrastructure
  vsphere_datacenter = var.vsphere_datacenter
  vsphere_datastore  = var.vsphere_datastore
  vsphere_cluster    = var.vsphere_cluster
  vsphere_network    = var.vsphere_network
  vsphere_folder     = var.vsphere_folder

  # VM Configuration
  vm_name      = "${local.resource_prefix}-bastion"
  vm_template  = var.vm_template
  vm_num_cpus  = var.bastion_vm_num_cpus
  vm_memory    = var.bastion_vm_memory
  vm_disk_size = var.bastion_vm_disk_size
  vm_domain    = var.vm_domain

  # Network Configuration
  vm_ipv4_address = var.bastion_ipv4_address
  vm_ipv4_netmask = var.vm_ipv4_netmask
  vm_ipv4_gateway = var.vm_ipv4_gateway
  vm_dns_servers  = var.vm_dns_servers

  # SSH Configuration
  vm_ssh_user = var.vm_ssh_user

  # Tags
  tags = merge(local.common_tags, {
    role = "bastion"
  })
}

# Registry VM for airgap environments
module "registry" {
  count  = var.airgap_setup ? 1 : 0
  source = "../vm"

  # vSphere Infrastructure
  vsphere_datacenter = var.vsphere_datacenter
  vsphere_datastore  = var.vsphere_datastore
  vsphere_cluster    = var.vsphere_cluster
  vsphere_network    = var.vsphere_network
  vsphere_folder     = var.vsphere_folder

  # VM Configuration
  vm_name      = "${local.resource_prefix}-registry"
  vm_template  = var.vm_template
  vm_num_cpus  = var.registry_vm_num_cpus
  vm_memory    = var.registry_vm_memory
  vm_disk_size = var.registry_vm_disk_size
  vm_domain    = var.vm_domain

  # Network Configuration
  vm_ipv4_address = var.registry_ipv4_address
  vm_ipv4_netmask = var.vm_ipv4_netmask
  vm_ipv4_gateway = var.vm_ipv4_gateway
  vm_dns_servers  = var.vm_dns_servers

  # SSH Configuration
  vm_ssh_user = var.vm_ssh_user

  # Tags
  tags = merge(local.common_tags, {
    role = "registry"
  })
}

# Load balancer for cluster API
module "load_balancer" {
  count  = var.enable_load_balancer ? 1 : 0
  source = "../load_balancer"

  name               = "${local.resource_prefix}-lb"
  load_balancer_type = var.load_balancer_type

  # vSphere Infrastructure
  vsphere_datacenter = var.vsphere_datacenter
  vsphere_datastore  = var.vsphere_datastore
  vsphere_cluster    = var.vsphere_cluster
  vsphere_network    = var.vsphere_network
  vsphere_folder     = var.vsphere_folder

  # VM Configuration
  vm_template  = var.vm_template
  vm_num_cpus  = 2
  vm_memory    = 4096
  vm_disk_size = 50

  # Network Configuration
  vm_ipv4_address = var.load_balancer_ipv4_address != "" ? var.load_balancer_ipv4_address : ""
  vm_ipv4_netmask = var.vm_ipv4_netmask
  vm_ipv4_gateway = var.vm_ipv4_gateway
  vm_dns_servers  = var.vm_dns_servers

  # Load Balancer Configuration
  frontend_ports = var.load_balancer_ports
  backend_servers = [
    for k, v in module.node_vm : {
      ip   = v.ip_address
      port = 6443  # Kubernetes API port
    }
    if local.node_map[k].is_server
  ]

  # Tags
  tags = merge(local.common_tags, {
    role = "load-balancer"
  })
}

# Ansible host resources for dynamic inventory
resource "ansible_host" "node" {
  for_each = module.node_vm

  name = each.key
  variables = {
    ansible_host       = each.value.ip_address
    ansible_user       = var.vm_ssh_user
    ansible_ssh_private_key_file = var.ssh_private_key_path
    ansible_role       = join(",", local.node_map[each.key].role)
    node_name         = each.value.vm_name
    is_server         = local.node_map[each.key].is_server
  }
}

# Ansible host for bastion (if airgap)
resource "ansible_host" "bastion" {
  count = var.airgap_setup ? 1 : 0
  name  = "bastion"
  
  variables = {
    ansible_host       = one(module.bastion[*].ip_address)
    ansible_user       = var.vm_ssh_user
    ansible_ssh_private_key_file = var.ssh_private_key_path
    ansible_role       = "bastion"
    node_name         = one(module.bastion[*].vm_name)
    is_server         = false
  }
}

# Ansible host for registry (if airgap)
resource "ansible_host" "registry" {
  count = var.airgap_setup ? 1 : 0
  name  = "registry"
  
  variables = {
    ansible_host       = one(module.registry[*].ip_address)
    ansible_user       = var.vm_ssh_user
    ansible_ssh_private_key_file = var.ssh_private_key_path
    ansible_role       = "registry"
    node_name         = one(module.registry[*].vm_name)
    is_server         = false
  }
}

# Ansible host for load balancer (if enabled)
resource "ansible_host" "load_balancer" {
  count = var.enable_load_balancer ? 1 : 0
  name  = "load_balancer"
  
  variables = {
    ansible_host       = one(module.load_balancer[*].load_balancer_ip)
    ansible_user       = var.vm_ssh_user
    ansible_ssh_private_key_file = var.ssh_private_key_path
    ansible_role       = "load_balancer"
    node_name         = "${local.resource_prefix}-lb"
    is_server         = false
  }
}
