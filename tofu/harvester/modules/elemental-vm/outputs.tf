output "ip" {
  value       = [for vm in harvester_virtualmachine.elemental-vm : vm.network_interface[0].ip_address]
  description = "The IP addresses of the Elemental VMs, in creation order."
}

output "kube_api_host" {
  value       = harvester_virtualmachine.elemental-vm[0].network_interface[0].ip_address
  description = "The IP address of the first Elemental VM, used as the Kubernetes API host."
}

output "image_id" {
  value       = harvester_image.elemental.id
  description = "The ID of the Harvester image created from var.image_url, in <namespace>/<name> form."
}
