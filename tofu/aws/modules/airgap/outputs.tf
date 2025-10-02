output "registry_public_dns" {
  value = length(module.registry) > 0 ? module.registry[0].public_dns : null
}

output "bastion_public_dns" {
  value = module.bastion.public_dns
}

output "aitgap_nodes_private_ips" {
  value = [for s in module.airgap_nodes : s.private_ip]
}
