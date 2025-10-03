output "registry_public_dns" {
  value = length(module.registry) > 0 ? module.registry[0].public_dns : null
}

output "bastion_public_dns" {
  value = module.bastion.public_dns
}

output "rancher_servers_private_ips" {
  value = [for s in module.rancher_servers : s.private_ip]
}
