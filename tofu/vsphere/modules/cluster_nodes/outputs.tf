# Output all node information
output "nodes" {
  description = "All node information including IPs and roles"
  value = {
    for k, v in module.node_vm : k => {
      name        = v.vm_name
      ip_address  = v.ip_address
      role        = local.node_map[k].role
      is_server   = local.node_map[k].is_server
      vm_id       = v.vm_id
      vm_uuid     = v.vm_uuid
    }
  }
}

# Output master/control-plane node IP for API access
output "kube_api_host" {
  description = "Kubernetes API server host IP"
  value = [
    for k, v in module.node_vm : v.ip_address
    if local.node_map[k].is_server
  ][0] # Get the first master node IP
}

# Output FQDN (using the master node IP as FQDN for now)
output "fqdn" {
  description = "Fully qualified domain name for the cluster"
  value = [
    for k, v in module.node_vm : v.ip_address
    if local.node_map[k].is_server
  ][0] # For vSphere, we'll use IP as FQDN unless DNS is configured
}

# Output master node IPs
output "master_ips" {
  description = "Master node IP addresses"
  value = [
    for k, v in module.node_vm : v.ip_address
    if local.node_map[k].is_server
  ]
}

# Output worker node IPs
output "worker_ips" {
  description = "Worker node IP addresses"
  value = [
    for k, v in module.node_vm : v.ip_address
    if !local.node_map[k].is_server
  ]
}

# Output all node IPs
output "all_ips" {
  description = "All node IP addresses"
  value = [
    for k, v in module.node_vm : v.ip_address
  ]
}

# Output cluster ID for reference
output "cluster_id" {
  description = "Unique cluster identifier"
  value       = random_id.cluster_id.hex
}

# Output resource prefix for naming
output "resource_prefix" {
  description = "Resource prefix used for naming"
  value       = local.resource_prefix
}

# Output SSH configuration
output "ssh_config" {
  description = "SSH configuration for accessing nodes"
  value = {
    user        = var.vm_ssh_user
    private_key = var.ssh_private_key_path
  }
  sensitive = true
}

# Bastion Information (for airgap environments)
output "bastion" {
  description = "Bastion host information"
  value = var.airgap_setup ? {
    vm_id      = one(module.bastion[*].vm_id)
    vm_name    = one(module.bastion[*].vm_name)
    ip_address = one(module.bastion[*].ip_address)
  } : null
}

# Registry Information (for airgap environments)
output "registry" {
  description = "Registry host information"
  value = var.airgap_setup ? {
    vm_id      = one(module.registry[*].vm_id)
    vm_name    = one(module.registry[*].vm_name)
    ip_address = one(module.registry[*].ip_address)
    ports      = var.registry_ports
  } : null
}

# Load Balancer Information (if enabled)
output "load_balancer" {
  description = "Load balancer information"
  value = var.enable_load_balancer ? {
    vm_info        = one(module.load_balancer[*].load_balancer_vm)
    ip_address     = one(module.load_balancer[*].load_balancer_ip)
    fqdn           = one(module.load_balancer[*].load_balancer_fqdn)
    frontend_ports = one(module.load_balancer[*].frontend_ports)
    type           = one(module.load_balancer[*].load_balancer_type)
    backend_servers = one(module.load_balancer[*].backend_servers)
  } : null
}

# Cluster Access Configuration
output "cluster_access" {
  description = "Cluster access configuration"
  value = {
    # Use load balancer IP if available, otherwise use first master IP
    api_endpoint = var.enable_load_balancer ? one(module.load_balancer[*].load_balancer_ip) : [
      for k, v in module.node_vm : v.ip_address
      if local.node_map[k].is_server
    ][0]
    
    # Registry endpoint for airgap environments
    registry_endpoint = var.airgap_setup ? one(module.registry[*].ip_address) : null
    
    # Bastion endpoint for airgap environments
    bastion_endpoint = var.airgap_setup ? one(module.bastion[*].ip_address) : null
  }
}

# Infrastructure Summary
output "infrastructure_summary" {
  description = "Complete infrastructure summary"
  value = {
    cluster_id         = random_id.cluster_id.hex
    resource_prefix    = local.resource_prefix
    total_nodes        = length(module.node_vm)
    master_node_count  = length([for k, v in local.node_map : v if v.is_server])
    worker_node_count  = length([for k, v in local.node_map : v if !v.is_server])
    airgap_enabled     = var.airgap_setup
    load_balancer_enabled = var.enable_load_balancer
    proxy_enabled      = var.proxy_setup
  }
}
