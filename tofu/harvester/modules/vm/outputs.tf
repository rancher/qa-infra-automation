output "ip" {
  value = [for vm in harvester_virtualmachine.vm : vm.network_interface[0].ip_address] 
}

output "kube_api_host" {
  value       = harvester_virtualmachine.vm[local.node_names[local.first_etcd_index].name].network_interface[0].ip_address
  description = "The public IP address of the first etcd node, or 'No etcd node found'."
}

output "fqdn" {
  value = "${harvester_virtualmachine.vm[local.node_names[local.first_etcd_index].name].network_interface[0].ip_address}.sslip.io"
}