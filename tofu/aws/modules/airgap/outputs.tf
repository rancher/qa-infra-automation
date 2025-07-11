output "registry_public_dns" {
  value = module.registry.public_dns
}

output "bastion_public_dns" {
  value = module.bastion.public_dns
}

output "rancher_servers_private_ips" {
  value = [for s in module.rancher_servers : s.private_ip]
}
