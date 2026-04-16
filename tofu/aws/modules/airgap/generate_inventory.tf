# Generate inventory.yml file after Tofu apply
locals {
  non_rancher_groups = {for name, size in var.node_groups : name => size if name != "rancher"}
  non_rancher_private_ips = [for node in module.airgap_nodes : node.private_ip if !startswith(node.name, "${var.aws_hostname_prefix}-rancher-")]

  index_list = [
    for i in range(length(local.non_rancher_groups)) :
      sum(slice(values(local.non_rancher_groups), 0, i+1))
  ]

  non_rancher_group_addresses = zipmap(keys(local.non_rancher_groups), [
    for i in range(length(local.non_rancher_groups)) :
    slice( # Distribute the address across the non-rancher groups.
      local.non_rancher_private_ips,
      i > 0? local.index_list[i - 1] : 0,
      local.index_list[i]
    )
  ])

  rancher_private_ips = [for node in module.airgap_nodes : node.private_ip if startswith(node.name, "${var.aws_hostname_prefix}-rancher-")]
  group_addresses = !can(var.node_groups["rancher"]) ? local.non_rancher_group_addresses : merge(
    local.non_rancher_group_addresses,
    { "rancher" = local.rancher_private_ips }
  )
}

output "airgap_inventory_json" {
  description = "Complete airgap inventory data for bridge script consumption"
  value = jsonencode({
    type                 = "airgap"
    bastion_host         = module.bastion.public_dns
    registry_host        = length(module.registry) > 0 ? module.registry[0].public_dns : null
    ssh_key              = var.ssh_key
    ssh_user             = var.aws_ssh_user
    external_lb_hostname = module.route53[0].record_fqdn
    internal_lb_hostname = module.internal_route53[0].record_fqdn
    node_groups          = local.group_addresses
  })
}
