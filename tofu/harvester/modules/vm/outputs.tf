output "ip" {
  value = [for vm in harvester_virtualmachine.vm : vm.network_interface[0].ip_address] 
}

output "kube_api_host" {
  value       = aws_instance.node[local.node_names[local.first_etcd_index].name].public_ip
  description = "The public IP address of the first etcd node, or 'No etcd node found'."
}