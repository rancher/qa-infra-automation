output "ip" {
  value = [for vm in harvester_virtualmachine.vm : vm.network_interface[0].ip_address]
}

output "kube_api_host" {
  value       = harvester_virtualmachine.vm[local.node_names[local.first_etcd_index].name].network_interface[0].ip_address
  description = "The public IP address of the first etcd node, or 'No etcd node found'."
}

output "fqdn" {
  value = var.create_loadbalancer ? "${module.harvester_loadbalancer.ip_address}.sslip.io" : "${harvester_virtualmachine.vm[local.node_names[local.first_etcd_index].name].network_interface[0].ip_address}.sslip.io"
}

output "ssh_public_key" {
  value       = local.ssh_public_key
  description = "The public key used for the VMs, either provided via var.ssh_key or auto-generated."
}

output "ssh_private_key_path" {
  value       = local.generate_ssh_key ? local.ssh_private_key_path : null
  description = "Path to the auto-generated private key file, when one was generated."
}