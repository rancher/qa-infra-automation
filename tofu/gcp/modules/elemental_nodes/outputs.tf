output "public_dns" {
  value = [for e in module.elemental_nodes : e.public_dns]
}

output "ssh_key" {
  value = [for e in module.elemental_nodes : e.ssh_key]
  sensitive = true
}