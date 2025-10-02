# Generate inventory.yml file after Tofu apply
locals {
  group_sizes = values(var.node_groups)

  index_list = [
    for i in range(length(local.group_sizes)) :
      sum([for s in slice(local.group_sizes, 0, i+1) : s])
  ]

  group_addresses = [
    for i in range(length(local.group_sizes)) :
    slice(
      [for s in module.airgap_nodes : s.private_ip],
      i > 0? local.index_list[i - 1] : 0,
      local.index_list[i]-1
    )
  ]
}

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.yml.tpl", {
    group_names = keys(var.node_groups)
    group_addresses = local.group_addresses
    bastion_host = module.bastion.public_dns
    registry_host = length(module.registry) > 0 ? module.registry[0].public_dns : null
    node_ips = [for s in module.airgap_nodes : s.private_ip]
    ssh_key = var.ssh_key
    aws_ssh_user = var.aws_ssh_user
  })

  filename = "${path.module}/../../../../ansible/rke2/airgap/inventory/inventory.yml"

  depends_on = [
    module.bastion,
    module.registry,
    module.airgap_nodes
  ]
}

# Optional: Run ansible-inventory command to validate the generated inventory
resource "null_resource" "validate_inventory" {
  provisioner "local-exec" {
    command = "cd ${path.module}/../../../../ansible/rke2/airgap && ansible-inventory -i inventory/inventory.yml --list > /dev/null && echo 'Inventory validation successful'"
    on_failure = continue
  }

  depends_on = [local_file.ansible_inventory]
}
