# Generate inventory.yml file after Tofu apply
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.yml.tpl", {
    bastion_host = module.bastion.public_dns
    registry_host = module.registry.public_dns
    rancher_server_ips = [for s in module.rancher_servers : s.private_ip]
    ssh_key = var.ssh_key
    aws_ssh_user = var.aws_ssh_user
  })
  
  filename = "${path.module}/../../../../ansible/rke2/airgap/inventory/inventory.yml"
  
  depends_on = [
    module.bastion,
    module.registry,
    module.rancher_servers
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