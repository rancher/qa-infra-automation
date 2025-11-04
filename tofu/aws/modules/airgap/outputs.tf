output "registry_public_dns" {
  value = length(module.registry) > 0 ? module.registry[0].public_dns : null
}

output "bastion_public_dns" {
  value = module.bastion.public_dns
}

output "rancher_airgap_nodes_private_ips" {
  value = [for key, instance in module.airgap_nodes : instance.private_ip if startswith(instance.name, "${var.aws_hostname_prefix}-rancher-")]
}

output "non_rancher_airgap_nodes_private_ips" {
  value = [for key, instance in module.airgap_nodes : instance.private_ip if !startswith(instance.name, "${var.aws_hostname_prefix}-rancher-")]
}

output "external_lb_hostname" {
  value = module.route53[0].record_fqdn
}

output "internal_lb_hostname" {
  value = module.internal_route53[0].record_fqdn
}
