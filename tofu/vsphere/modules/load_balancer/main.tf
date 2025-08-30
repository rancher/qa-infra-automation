# HAProxy/NGINX Load Balancer using VM
module "load_balancer_vm" {
  count  = var.load_balancer_type != "nsxt" ? 1 : 0
  source = "../vm"

  # vSphere Infrastructure
  vsphere_datacenter = var.vsphere_datacenter
  vsphere_datastore  = var.vsphere_datastore
  vsphere_cluster    = var.vsphere_cluster
  vsphere_network    = var.vsphere_network
  vsphere_folder     = var.vsphere_folder

  # VM Configuration
  vm_name      = "${var.name}-lb"
  vm_template  = var.vm_template
  vm_num_cpus  = var.vm_num_cpus
  vm_memory    = var.vm_memory
  vm_disk_size = var.vm_disk_size

  # Network Configuration
  vm_ipv4_address = var.vm_ipv4_address
  vm_ipv4_netmask = var.vm_ipv4_netmask
  vm_ipv4_gateway = var.vm_ipv4_gateway
  vm_dns_servers  = var.vm_dns_servers

  # Tags
  tags = merge(var.tags, {
    role = "load-balancer"
    type = var.load_balancer_type
  })
}

# Generate HAProxy configuration
resource "local_file" "haproxy_config" {
  count = var.load_balancer_type == "haproxy" ? 1 : 0
  
  filename = "${path.module}/haproxy.cfg"
  content = templatefile("${path.module}/templates/haproxy.cfg.tpl", {
    frontend_ports   = var.frontend_ports
    backend_servers  = var.backend_servers
    health_check_path = var.health_check_path
  })
}

# Generate NGINX configuration
resource "local_file" "nginx_config" {
  count = var.load_balancer_type == "nginx" ? 1 : 0
  
  filename = "${path.module}/nginx.conf"
  content = templatefile("${path.module}/templates/nginx.conf.tpl", {
    frontend_ports   = var.frontend_ports
    backend_servers  = var.backend_servers
    health_check_path = var.health_check_path
  })
}

# Local values for configuration
locals {
  load_balancer_config = var.load_balancer_type == "haproxy" ? {
    config_file = one(local_file.haproxy_config[*].filename)
    service_name = "haproxy"
  } : var.load_balancer_type == "nginx" ? {
    config_file = one(local_file.nginx_config[*].filename)
    service_name = "nginx"
  } : null
}
