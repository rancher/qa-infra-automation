# Load Balancer VM Information (for VM-based LBs)
output "load_balancer_vm" {
  description = "Load balancer VM information"
  value = var.load_balancer_type != "nsxt" ? {
    vm_id      = one(module.load_balancer_vm[*].vm_id)
    vm_name    = one(module.load_balancer_vm[*].vm_name)
    ip_address = one(module.load_balancer_vm[*].ip_address)
  } : null
}

# Load Balancer IP Address
output "load_balancer_ip" {
  description = "Load balancer IP address"
  value       = var.load_balancer_type != "nsxt" ? one(module.load_balancer_vm[*].ip_address) : var.vm_ipv4_address
}

# Load Balancer FQDN (using IP as FQDN for vSphere)
output "load_balancer_fqdn" {
  description = "Load balancer FQDN"
  value       = var.load_balancer_type != "nsxt" ? one(module.load_balancer_vm[*].ip_address) : var.vm_ipv4_address
}

# Frontend Ports
output "frontend_ports" {
  description = "Frontend ports exposed by the load balancer"
  value       = var.frontend_ports
}

# Configuration File Path (for VM-based LBs)
output "config_file_path" {
  description = "Path to the load balancer configuration file"
  value       = local.load_balancer_config != null ? local.load_balancer_config.config_file : null
}

# Load Balancer Type
output "load_balancer_type" {
  description = "Type of load balancer deployed"
  value       = var.load_balancer_type
}

# Backend Servers Configuration
output "backend_servers" {
  description = "Backend servers configuration"
  value       = var.backend_servers
}
